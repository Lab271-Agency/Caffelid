#include "CaffelidIPC.h"
#include <Security/Security.h>
#include <bsm/audit.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#include <string.h>

static CFStringRef copy_signing_team(void) {
    SecCodeRef self = NULL;
    SecRequirementRef apple = NULL;
    CFDictionaryRef info = NULL;
    CFStringRef team = NULL;
    OSStatus status = SecRequirementCreateWithString(CFSTR("anchor apple generic"),
        kSecCSDefaultFlags, &apple);
    if (status == errSecSuccess) status = SecCodeCopySelf(kSecCSDefaultFlags, &self);
    if (status == errSecSuccess) status = SecCodeCheckValidity(self, kSecCSDefaultFlags, apple);
    if (status == errSecSuccess) status = SecCodeCopySigningInformation(self, kSecCSSigningInformation, &info);
    if (status == errSecSuccess && info) {
        CFTypeRef value = CFDictionaryGetValue(info, kSecCodeInfoTeamIdentifier);
        if (value && CFGetTypeID(value) == CFStringGetTypeID()) {
            char text[64];
            if (CFStringGetCString((CFStringRef)value, text, sizeof(text), kCFStringEncodingASCII)) {
                bool valid = text[0] != '\0';
                for (const char *p = text; *p; p++)
                    if (!((*p >= 'A' && *p <= 'Z') || (*p >= '0' && *p <= '9'))) valid = false;
                if (valid) team = CFStringCreateCopy(NULL, (CFStringRef)value);
            }
        }
    }
    if (info) CFRelease(info);
    if (self) CFRelease(self);
    if (apple) CFRelease(apple);
    return team;
}

int caffelid_signing_team_available(void) {
    CFStringRef team = copy_signing_team();
    if (!team) return 0;
    CFRelease(team);
    return 1;
}

#ifdef CAFFELID_TESTING
static int trusted_file(const char *path) {
    int fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) return -1;
    struct stat info;
    uid_t expected = geteuid();
    if (fstat(fd, &info) < 0 || !S_ISREG(info.st_mode) || info.st_uid != expected ||
        (info.st_mode & 0022) != 0 || info.st_nlink != 1) {
        close(fd);
        return -1;
    }
    return fd;
}

void *caffelid_load_requirement(void) {
    int fd = trusted_file(CAFFELID_CLIENT_PATH);
    if (fd < 0) return NULL;
    struct stat info;
    if (fstat(fd, &info) < 0 || info.st_size <= 0 || info.st_size > 16384) {
        close(fd);
        return NULL;
    }
    unsigned char bytes[16384];
    ssize_t count = read(fd, bytes, (size_t)info.st_size);
    close(fd);
    if (count != info.st_size) return NULL;
    CFDataRef data = CFDataCreate(NULL, bytes, count);
    if (!data) return NULL;
    SecRequirementRef requirement = NULL;
    OSStatus status = SecRequirementCreateWithData(data, kSecCSDefaultFlags, &requirement);
    CFRelease(data);
    return status == errSecSuccess ? (void *)requirement : NULL;
}

#else
void *caffelid_load_requirement(void) {
    // Trust this helper's Apple-issued signing team and the app's exact identifier.
    // The requirement remains valid across releases signed by the same developer.
    CFStringRef team = copy_signing_team();
    if (!team) return NULL;
    CFStringRef source = CFStringCreateWithFormat(NULL, NULL,
        CFSTR("anchor apple generic and identifier \"app.caffelid.desktop\" and certificate leaf[subject.OU] = \"%@\""), team);
    CFRelease(team);
    if (!source) return NULL;
    SecRequirementRef requirement = NULL;
    OSStatus status = SecRequirementCreateWithString(source, kSecCSDefaultFlags, &requirement);
    CFRelease(source);
    return status == errSecSuccess ? (void *)requirement : NULL;
}
#endif

void caffelid_free_requirement(void *requirement) {
    if (requirement) CFRelease((SecRequirementRef)requirement);
}

int caffelid_peer_matches(int fd, const void *requirement) {
    // A kernel audit token includes the process generation, avoiding PID reuse.
    audit_token_t token;
    socklen_t length = sizeof(token);
    if (!requirement || getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) < 0 ||
        length != sizeof(token)) return 0;
    CFDataRef data = CFDataCreate(NULL, (const UInt8 *)&token, sizeof(token));
    if (!data) return 0;
    const void *keys[] = { kSecGuestAttributeAudit };
    const void *values[] = { data };
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    SecCodeRef code = NULL;
    OSStatus status = attributes ? SecCodeCopyGuestWithAttributes(NULL, attributes,
        kSecCSDefaultFlags, &code) : errSecAllocate;
    if (status == errSecSuccess) status = SecCodeCheckValidity(code,
        kSecCSDefaultFlags, (SecRequirementRef)requirement);
    if (code) CFRelease(code);
    if (attributes) CFRelease(attributes);
    CFRelease(data);
    return status == errSecSuccess;
}

