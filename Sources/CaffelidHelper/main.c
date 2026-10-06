#include "CaffelidIPC.h"
#include "LegacyMigration.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <launch.h>
#include <sys/socket.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

// Test builds replace these at compile time; the shipped helper has fixed paths.
#if defined(CAFFELID_TESTING) && (!defined(CAFFELID_PMSET_PATH) || !defined(CAFFELID_LOCK_PATH))
#error "Test builds must define isolated power command and lock paths."
#endif
#ifndef CAFFELID_PMSET_PATH
#define CAFFELID_PMSET_PATH "/usr/bin/pmset"
#endif
#ifndef CAFFELID_LOCK_PATH
// Share the lock with the Lungo beta to prevent simultaneous power-setting owners.
#define CAFFELID_LOCK_PATH "/private/var/run/lungo.sleep.lock"
#endif

static volatile sig_atomic_t stopping = 0;
static void stop_handler(int signal_number) { (void)signal_number; stopping = 1; }

static int set_sleep(bool disabled) {
    char *arguments[] = { CAFFELID_PMSET_PATH, "-a", "disablesleep", disabled ? "1" : "0", NULL };
    char *environment[] = { "PATH=/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL=C", NULL };
    pid_t child;
    if (posix_spawn(&child, CAFFELID_PMSET_PATH, NULL, NULL, arguments, environment) != 0) return -1;
    int status;
    while (waitpid(child, &status, 0) < 0) { if (errno != EINTR) return -1; }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : -1;
}

static int restore_sleep(void) {
    for (int attempt = 0; attempt < 3; attempt++) {
        if (set_sleep(false) == 0) return 0;
        sleep(1);
    }
    return -1;
}

static int acquire_lock(void) {
    int fd = open(CAFFELID_LOCK_PATH, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) return -1;
    struct stat info;
    if (fstat(fd, &info) < 0 || !S_ISREG(info.st_mode) || info.st_uid != geteuid() ||
        info.st_nlink != 1 || fchmod(fd, 0600) < 0 || flock(fd, LOCK_EX | LOCK_NB) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static int serve_session(int connection, const void *requirement) {
    if (!caffelid_peer_matches(connection, requirement)) return 77;
    if (caffelid_write_line(connection, "READY\n") < 0) return 74;
    char command[32];
    if (caffelid_read_line(connection, command, sizeof(command), 5000) < 0) return 74;
    // Check the live sender again before changing settings.
    if (!caffelid_peer_matches(connection, requirement)) return 77;
    if (strcmp(command, "RESET") == 0) {
        int restored = restore_sleep();
        caffelid_write_line(connection, restored == 0 ? "OFF\n" : "ERROR\n");
        return restored == 0 ? 0 : 74;
    }
    if (strcmp(command, "ON") != 0) {
        caffelid_write_line(connection, "ERROR\n");
        return 64;
    }
    int enabled = stopping ? -1 : set_sleep(true);
    bool valid_off = false;
    if (enabled == 0 && !stopping && caffelid_write_line(connection, "ON\n") == 0) {
        struct pollfd item = { .fd = connection, .events = POLLIN };
        while (!stopping) {
            int result = poll(&item, 1, 1000);
            if (result < 0 && errno == EINTR) continue;
            if (result == 0) continue;
            if (result > 0 && caffelid_read_line(connection, command, sizeof(command), 1000) == 0)
                valid_off = strcmp(command, "OFF") == 0 && caffelid_peer_matches(connection, requirement);
            break;
        }
    }
    // A failed enable, EOF, invalid message or signal always restores sleep.
    int restored = restore_sleep();
    caffelid_write_line(connection, restored == 0 && (valid_off || stopping) ? "OFF\n" : "ERROR\n");
    return restored == 0 ? (enabled == 0 ? 0 : 74) : 74;
}

int main(int argc, char **argv) {
#ifndef CAFFELID_TESTING
    if (geteuid() != 0) { fputs("Administrator authorization required.\n", stderr); return 77; }
    if (argc != 1) return 64;
    (void)argv;
    int *fds = NULL;
    size_t count = 0;
    if (launch_activate_socket("Control", &fds, &count) != 0 || count != 1) {
        if (fds) { for (size_t i = 0; i < count; i++) close(fds[i]); free(fds); }
        return 78;
    }
    int listener = fds[0];
    free(fds);
#else
    // Tests pass an inherited listener, never a production socket or command.
    if (argc != 3 || strcmp(argv[1], "--serve-test") != 0) return 64;
    char *end;
    long descriptor = strtol(argv[2], &end, 10);
    if (*argv[2] == '\0' || *end != '\0' || descriptor < 3 || descriptor > INT_MAX) return 64;
    int listener = (int)descriptor;
#endif
    struct sigaction action = {0};
    action.sa_handler = stop_handler;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGHUP, &action, NULL);
    signal(SIGPIPE, SIG_IGN);
    void *requirement = caffelid_load_requirement();
    if (!requirement) { close(listener); return 77; }
    if (caffelid_remove_legacy_support() != 0) {
        caffelid_free_requirement(requirement);
        close(listener);
        return 78;
    }
    int lock = acquire_lock();
    // The old service may still be exiting after launchctl bootout.
    for (int attempt = 0; lock < 0 && attempt < 30 && !stopping; attempt++) {
        usleep(100000);
        lock = acquire_lock();
    }
    if (lock < 0) { caffelid_free_requirement(requirement); close(listener); return 75; }
    int result = restore_sleep(); // Boot/relaunch starts inactive, even after a hard kill.
    while (result == 0 && !stopping) {
        struct pollfd item = { .fd = listener, .events = POLLIN };
        int ready = poll(&item, 1, 10000);
        if (ready < 0 && errno == EINTR) continue;
        if (ready == 0) continue;
        if (ready < 0) { result = -1; break; }
        int connection = accept(listener, NULL, NULL);
        if (connection < 0) continue;
        int yes = 1;
        if (fcntl(connection, F_SETFD, FD_CLOEXEC) == 0 &&
            setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes)) == 0) {
            int session_result = serve_session(connection, requirement);
            if (session_result == 74) result = restore_sleep();
        }
        close(connection);
    }
    // Also restore after ordinary service shutdown or background permission revocation.
    if (restore_sleep() != 0) result = -1;
    close(lock);
    close(listener);
    caffelid_free_requirement(requirement);
    return result == 0 ? 0 : 74;
}
