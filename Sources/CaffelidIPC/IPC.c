#include "CaffelidIPC.h"
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/IOPM.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

static int make_socket(void) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    int yes = 1;
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) < 0 ||
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes)) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static int address(const char *path, struct sockaddr_un *value) {
    memset(value, 0, sizeof(*value));
    if (strlen(path) >= sizeof(value->sun_path)) { errno = ENAMETOOLONG; return -1; }
    value->sun_family = AF_UNIX;
    value->sun_len = sizeof(*value);
    strlcpy(value->sun_path, path, sizeof(value->sun_path));
    return 0;
}

int caffelid_connect_service(void) {
    struct sockaddr_un value;
    if (address(CAFFELID_SOCKET_PATH, &value) < 0) return -1;
    int fd = make_socket();
    if (fd < 0) return -1;
    uid_t uid;
    gid_t gid;
#ifdef CAFFELID_TESTING
    uid_t expected = geteuid();
#else
    uid_t expected = 0;
#endif
    if (connect(fd, (struct sockaddr *)&value, sizeof(value)) < 0 ||
        getpeereid(fd, &uid, &gid) < 0 || uid != expected) {
        close(fd);
        return -1;
    }
    return fd;
}

int caffelid_write_line(int fd, const char *line) {
    size_t remaining = strlen(line);
    while (remaining > 0) {
        ssize_t count = write(fd, line, remaining);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return -1;
        line += count;
        remaining -= (size_t)count;
    }
    return 0;
}

int caffelid_read_line(int fd, char *buffer, size_t capacity, int timeout_ms) {
    if (capacity < 2) return -1;
    size_t used = 0;
    // A single deadline prevents a slow sender from extending the timeout.
    struct timespec start;
    clock_gettime(CLOCK_MONOTONIC, &start);
    while (used + 1 < capacity) {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        long elapsed = (now.tv_sec - start.tv_sec) * 1000 + (now.tv_nsec - start.tv_nsec) / 1000000;
        int remaining = timeout_ms - (int)elapsed;
        if (remaining <= 0) return -1;
        struct pollfd item = { .fd = fd, .events = POLLIN };
        int result = poll(&item, 1, remaining);
        if (result < 0 && errno == EINTR) continue;
        if (result <= 0) return -1;
        char byte;
        ssize_t count = read(fd, &byte, 1);
        if (count < 0 && errno == EINTR) continue;
        if (count != 1) return -1;
        if (byte == '\n') { buffer[used] = '\0'; return 0; }
        buffer[used++] = byte;
    }
    return -1;
}

void caffelid_close(int fd) { if (fd >= 0) close(fd); }

// The SDK's function-like macro is not imported by Swift.
unsigned int caffelid_clamshell_message(void) { return kIOPMMessageClamshellStateChange; }
