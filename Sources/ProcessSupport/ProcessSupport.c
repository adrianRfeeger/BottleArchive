#include "ProcessSupport.h"
#include <spawn.h>
#include <signal.h>
#include <sys/wait.h>
#include <errno.h>
#include <libproc.h>
#include <unistd.h>
int ps_executable_path(char *buffer, uint32_t size) { return proc_pidpath(getpid(), buffer, size); }
void ps_ignore_sigpipe(void) { signal(SIGPIPE, SIG_IGN); }
int ps_spawn(const char *path, char *const argv[], char *const envp[], int input, int output, int error, pid_t *pid) {
    posix_spawnattr_t attr;
    posix_spawn_file_actions_t actions;
    int rc = posix_spawnattr_init(&attr);
    if (rc) return rc;
    rc = posix_spawn_file_actions_init(&actions);
    if (rc) { posix_spawnattr_destroy(&attr); return rc; }
    if (!(rc = posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)) &&
        !(rc = posix_spawnattr_setpgroup(&attr, 0)) &&
        !(rc = posix_spawn_file_actions_adddup2(&actions, input, 0)) &&
        !(rc = posix_spawn_file_actions_adddup2(&actions, output, 1)) &&
        !(rc = posix_spawn_file_actions_adddup2(&actions, error, 2))) {
        rc = posix_spawn(pid, path, &actions, &attr, argv, envp);
    }
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attr);
    return rc;
}
int ps_wait(pid_t pid, int *status) {
    int raw;
    while (waitpid(pid, &raw, 0) < 0) { if (errno != EINTR) return errno; }
    *status = WIFEXITED(raw) ? WEXITSTATUS(raw) : 128 + WTERMSIG(raw);
    return 0;
}
