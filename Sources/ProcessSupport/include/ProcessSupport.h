#include <sys/types.h>
int ps_spawn(const char *path, char *const argv[], char *const envp[], int input, int output, int error, pid_t *pid);
int ps_wait(pid_t pid, int *status);
void ps_ignore_sigpipe(void);
