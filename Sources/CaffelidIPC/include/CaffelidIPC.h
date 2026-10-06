#ifndef CAFFELID_IPC_H
#define CAFFELID_IPC_H
#include <sys/types.h>
#if defined(CAFFELID_TESTING) && (!defined(CAFFELID_SOCKET_PATH) || !defined(CAFFELID_CLIENT_PATH))
#error "Test builds must define isolated socket and client requirement paths."
#endif
#ifndef CAFFELID_SOCKET_PATH
#define CAFFELID_SOCKET_PATH "/private/var/run/app.caffelid.desktop.sleep.sock"
#endif

int caffelid_signing_team_available(void);
int caffelid_connect_service(void);
int caffelid_peer_matches(int fd, const void *requirement);
void *caffelid_load_requirement(void);
void caffelid_free_requirement(void *requirement);
int caffelid_write_line(int fd, const char *line);
int caffelid_read_line(int fd, char *buffer, size_t capacity, int timeout_ms);
void caffelid_close(int fd);
unsigned int caffelid_clamshell_message(void);
#endif
