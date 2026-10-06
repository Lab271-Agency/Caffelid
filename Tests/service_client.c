#include "CaffelidIPC.h"
#include <stdio.h>
#include <string.h>
#include <poll.h>
#include <unistd.h>

// Signed test client. stdin chooses protocol messages, never executable commands.
int main(void) {
    int fd = caffelid_connect_service();
    if (fd < 0) return 77;
    char line[32];
    if (caffelid_read_line(fd, line, sizeof(line), 5000) < 0) return 74;
    puts(line);
    fflush(stdout);
    struct pollfd items[] = { { .fd = fd, .events = POLLIN }, { .fd = STDIN_FILENO, .events = POLLIN } };
    while (poll(items, 2, 10000) > 0) {
        if (items[0].revents) {
            if (caffelid_read_line(fd, line, sizeof(line), 5000) < 0) break;
            puts(line);
            fflush(stdout);
            if (strcmp(line, "OFF") == 0 || strcmp(line, "ERROR") == 0) break;
        }
        if (items[1].revents) {
            if (!fgets(line, sizeof(line), stdin)) break;
            if (caffelid_write_line(fd, line) < 0) { caffelid_close(fd); return 74; }
        }
    }
    caffelid_close(fd);
    return 0;
}
