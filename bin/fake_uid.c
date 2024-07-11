#include <stdlib.h>
#include <unistd.h>

// sufficiently high to be unused
#define INVALID_ID 1000000

static uid_t get_fake_uid(void)
{
    char *uid_str = getenv("NETHACK_FRIENDS_UID");
    if (!uid_str)
        return INVALID_ID;

    int uid = atoi(uid_str);
    if (uid == 0)
        return INVALID_ID;

    return uid;
}

uid_t getuid(void)  { return get_fake_uid(); }
uid_t geteuid(void) { return get_fake_uid(); }
uid_t getgid(void)  { return get_fake_uid(); }
uid_t getegid(void) { return get_fake_uid(); }

int setuid(uid_t uid)   { (void)uid;  return 0; }
int seteuid(uid_t euid) { (void)euid; return 0; }
int setgid(gid_t gid)   { (void)gid;  return 0; }
int setegid(gid_t egid) { (void)egid; return 0; }
