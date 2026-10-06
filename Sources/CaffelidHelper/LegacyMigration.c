#include "LegacyMigration.h"
#include <CoreFoundation/CoreFoundation.h>
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdbool.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

// Only the earlier Lungo package and exact native beta jobs are eligible.
#if defined(CAFFELID_TESTING) && (!defined(CAFFELID_LEGACY_PLIST_PATH) || \
    !defined(CAFFELID_LEGACY_EXECUTABLE_PATH) || !defined(CAFFELID_LEGACY_REQUIREMENT_PATH) || \
    !defined(CAFFELID_LAUNCHCTL_PATH) || !defined(CAFFELID_PKGUTIL_PATH))
#error "Test builds must define isolated migration files and commands."
#endif
#ifndef CAFFELID_LEGACY_PLIST_PATH
#define CAFFELID_LEGACY_PLIST_PATH "/Library/LaunchDaemons/app.lungo.mac.helper.plist"
#endif
#ifndef CAFFELID_LEGACY_EXECUTABLE_PATH
#define CAFFELID_LEGACY_EXECUTABLE_PATH "/Library/PrivilegedHelperTools/app.lungo.mac.helper"
#endif
#ifndef CAFFELID_LEGACY_REQUIREMENT_PATH
#define CAFFELID_LEGACY_REQUIREMENT_PATH "/Library/PrivilegedHelperTools/app.lungo.mac.client"
#endif
#ifndef CAFFELID_LAUNCHCTL_PATH
#define CAFFELID_LAUNCHCTL_PATH "/bin/launchctl"
#endif
#ifndef CAFFELID_PKGUTIL_PATH
#define CAFFELID_PKGUTIL_PATH "/usr/sbin/pkgutil"
#endif

static int trusted_file(const char *path) {
    int fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) return -1;
    struct stat info;
#ifdef CAFFELID_TESTING
    uid_t owner = geteuid();
#else
    uid_t owner = 0;
#endif
    if (fstat(fd, &info) < 0 || !S_ISREG(info.st_mode) || info.st_uid != owner ||
        (info.st_mode & 0022) != 0 || info.st_nlink != 1) {
        close(fd);
        errno = EPERM;
        return -1;
    }
    return fd;
}

static bool correct_job(int fd) {
    struct stat info;
    unsigned char bytes[16384];
    if (fstat(fd, &info) < 0 || info.st_size <= 0 || info.st_size > (off_t)sizeof(bytes) ||
        read(fd, bytes, (size_t)info.st_size) != info.st_size) return false;
    CFDataRef data = CFDataCreate(NULL, bytes, info.st_size);
    if (!data) return false;
    CFPropertyListRef value = CFPropertyListCreateWithData(NULL, data, kCFPropertyListImmutable, NULL, NULL);
    CFRelease(data);
    bool valid = false;
    if (value && CFGetTypeID(value) == CFDictionaryGetTypeID()) {
        CFTypeRef label = CFDictionaryGetValue(value, CFSTR("Label"));
        CFTypeRef arguments = CFDictionaryGetValue(value, CFSTR("ProgramArguments"));
        if (label && CFEqual(label, CFSTR("app.lungo.mac.helper")) && arguments &&
            CFGetTypeID(arguments) == CFArrayGetTypeID() && CFArrayGetCount(arguments) == 1 &&
            CFEqual(CFArrayGetValueAtIndex(arguments, 0), CFSTR(CAFFELID_LEGACY_EXECUTABLE_PATH))) valid = true;
    }
    if (value) CFRelease(value);
    return valid;
}

static int run_fixed(const char *path, char *const arguments[]) {
    posix_spawn_file_actions_t actions;
    if (posix_spawn_file_actions_init(&actions) != 0) return -1;
    int error = posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    if (error == 0) error = posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
    pid_t pid;
    char *environment[] = { "PATH=/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL=C", NULL };
    if (error == 0) error = posix_spawn(&pid, path, &actions, NULL, arguments, environment);
    posix_spawn_file_actions_destroy(&actions);
    if (error != 0) return -1;
    int status;
    while (waitpid(pid, &status, 0) < 0) { if (errno != EINTR) return -1; }
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static int remove_package_support(void) {
    int plist = trusted_file(CAFFELID_LEGACY_PLIST_PATH);
    if (plist < 0) return errno == ENOENT ? 0 : -1;
    bool valid = correct_job(plist);
    close(plist);
    if (!valid) return -1;
    const char *paths[] = { CAFFELID_LEGACY_EXECUTABLE_PATH, CAFFELID_LEGACY_REQUIREMENT_PATH };
    for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
        int fd = trusted_file(paths[i]);
        if (fd < 0 && errno != ENOENT) return -1;
        if (fd >= 0) close(fd);
    }
    char *bootout[] = { CAFFELID_LAUNCHCTL_PATH, "bootout", "system/app.lungo.mac.helper", NULL };
    int result = run_fixed(CAFFELID_LAUNCHCTL_PATH, bootout);
    if (result != 0 && result != 3 && result != 113) return -1;
    // Parent directories are system-owned; unprivileged clients cannot swap these paths.
    const char *remove[] = { CAFFELID_LEGACY_PLIST_PATH, CAFFELID_LEGACY_EXECUTABLE_PATH, CAFFELID_LEGACY_REQUIREMENT_PATH };
    for (size_t i = 0; i < sizeof(remove) / sizeof(remove[0]); i++)
        if (unlink(remove[i]) < 0 && errno != ENOENT) return -1;
    char *forget[] = { CAFFELID_PKGUTIL_PATH, "--forget", "app.lungo.mac.support", NULL };
    (void)run_fixed(CAFFELID_PKGUTIL_PATH, forget);
    return 0;
}

static int stop_beta_job(const char *job) {
    char *inspect[] = { CAFFELID_LAUNCHCTL_PATH, "print", (char *)job, NULL };
    int found = run_fixed(CAFFELID_LAUNCHCTL_PATH, inspect);
    if (found == 3 || found == 113) return 0;
    if (found != 0) return -1;
    char *stop[] = { CAFFELID_LAUNCHCTL_PATH, "bootout", (char *)job, NULL };
    int stopped = run_fixed(CAFFELID_LAUNCHCTL_PATH, stop);
    return stopped == 0 || stopped == 3 || stopped == 113 ? 0 : -1;
}

int caffelid_remove_legacy_support(void) {
    if (remove_package_support() != 0) return -1;
    // Fixed beta job names only. Bootout stops KeepAlive and releases the shared
    // lock; it does not delete files or change another app's background approval.
    if (stop_beta_job("system/app.lungo.mac.sleep-service") != 0) return -1;
    return stop_beta_job("system/app.caffelid.mac.sleep-service");
}
