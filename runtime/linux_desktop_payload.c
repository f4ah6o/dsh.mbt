#define _GNU_SOURCE 1
#include <stdint.h>
#include <stddef.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(__linux__)
#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/prctl.h>
#include <unistd.h>

/* Wire format shared with scripts/package-linux-desktop.py. FNV-1a detects
 * accidental corruption only: release authenticity belongs to distribution. */
#define FOOTER_SIZE 40
#define MAX_PAYLOAD (512ULL * 1024 * 1024)
static const unsigned char magic[16] = "DSH-LINUX-GUI\0\0\0";
static uint64_t le64(const unsigned char *p) {
  uint64_t n = 0; for (int i = 7; i >= 0; --i) n = (n << 8) | p[i]; return n;
}
static int read_at(int fd, void *out, size_t n, off_t at) {
  unsigned char *p = out;
  while (n) { ssize_t k = pread(fd, p, n, at); if (k < 0 && errno == EINTR) continue;
    if (k <= 0) return -1;
    p += k; n -= (size_t)k; at += k; }
  return 0;
}
static volatile sig_atomic_t child_pid;
static volatile sig_atomic_t received_signal;

/* Extraction keeps shutdown signals blocked. Consume them synchronously so a
 * cancellation aborts copying instead of starting a GUI only to kill it later.
 * The same drain before restoring dispositions prevents an already-pending
 * signal from bypassing the supervisor's normal 128 + signal return after cleanup. */
static int shutdown_requested(const sigset_t *signals) {
  const struct timespec immediate = {0, 0};
  for (;;) {
    int sig = sigtimedwait(signals, NULL, &immediate);
    if (sig > 0) {
      if (!received_signal) received_signal = sig;
    } else if (errno != EINTR) {
      break;
    }
  }
  return received_signal != 0;
}

static int copy_part(int source, off_t at, uint64_t size, int dir_fd, const char *path,
                     uint64_t *hash, const sigset_t *signals) {
  int out = openat(dir_fd, path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0700);
  if (out < 0) return -1;
  unsigned char buf[65536]; int result = 0;
  *hash = UINT64_C(14695981039346656037);
  while (size) {
    if (shutdown_requested(signals)) { result = -1; break; }
    size_t n = size < sizeof(buf) ? (size_t)size : sizeof(buf);
    if (read_at(source, buf, n, at)) { result = -1; break; }
    for (size_t i = 0; i < n; i++) { *hash ^= buf[i]; *hash *= UINT64_C(1099511628211); }
    size_t written = 0;
    while (written < n) { ssize_t k = write(out, buf + written, n - written);
      if (k < 0 && errno == EINTR) continue;
      if (k <= 0) { result = -1; break; } written += (size_t)k; }
    if (result || shutdown_requested(signals)) { result = -1; break; }
    at += (off_t)n; size -= n;
  }
  if (!result && fchmod(out, 0700)) result = -1;
  if (close(out)) result = -1;
  return result;
}
extern char **environ;
static void forward_signal(int sig) {
  int saved = errno; received_signal = sig;
  if (child_pid > 0) kill(-child_pid, sig == SIGHUP || sig == SIGQUIT ? SIGTERM : sig);
  errno = saved;
}

/* payload is path NUL followed by each argument NUL; empty path selects the
 * embedded companion. No argv splitting, shell, PATH search, or network. */
int dsh_linux_desktop_launch(const unsigned char *payload, int length) {
  if (getuid() != geteuid() || getgid() != getegid()) return -2;
  if (!payload || length < 1 || payload[length - 1]) return -2;
  size_t count = 0;
  for (int i = 0; i < length; i++) if (!payload[i]) count++;
  char **argv = calloc(count + 1, sizeof(char *));
  if (!argv) return -3;
  size_t index = 0; argv[index++] = (char *)payload;
  for (int i = 0; i < length - 1; i++) if (!payload[i]) argv[index++] = (char *)payload + i + 1;
  if (argv[0][0] && argv[0][0] != '/') { free(argv); return -2; }
  int source = open("/proc/self/exe", O_RDONLY | O_CLOEXEC);
  struct stat st; int result = -2;
  char *dir = NULL, *gui = NULL, *helper = NULL;
  int handlers_set = 0, dir_fd = -1, gui_fd = -1;
  char **environment = NULL, *worker_environment = NULL;
  sigset_t blocked, oldmask;
  int signals[] = {SIGINT, SIGTERM, SIGHUP, SIGQUIT};
  struct sigaction old[4], action;
  sigemptyset(&blocked);
  for (int i = 0; i < 4; i++) sigaddset(&blocked, signals[i]);
  if (source < 0 || fstat(source, &st) || !S_ISREG(st.st_mode) || st.st_size < 4) goto done;
  uint64_t base_size = (uint64_t)st.st_size, gui_size = 0, expected = 0;
  unsigned char footer[FOOTER_SIZE];
  if (st.st_size >= FOOTER_SIZE && !read_at(source, footer, FOOTER_SIZE, st.st_size - FOOTER_SIZE) &&
      !memcmp(footer, magic, sizeof(magic))) {
    if (le64(footer + 16) != 1) goto done; /* version32=1, reserved32=0 */
    gui_size = le64(footer + 24); expected = le64(footer + 32);
    if (st.st_size < FOOTER_SIZE + 64 + 64 || gui_size < 64 || gui_size > MAX_PAYLOAD || gui_size > (uint64_t)st.st_size - FOOTER_SIZE - 64) goto done;
    base_size = (uint64_t)st.st_size - FOOTER_SIZE - gui_size;
  } else if (!argv[0][0]) { result = -1; goto done; }
  unsigned char elf[20], gui_elf[20];
  if (read_at(source, elf, 20, 0) || memcmp(elf, "\177ELF", 4)) goto done;
  if (!argv[0][0] && (gui_size < 20 || read_at(source, gui_elf, 20, (off_t)base_size) ||
      memcmp(gui_elf, "\177ELF", 4) || memcmp(elf + 4, gui_elf + 4, 2) ||
      memcmp(elf + 18, gui_elf + 18, 2))) goto done;
  if (sigprocmask(SIG_BLOCK, &blocked, &oldmask)) { result = -5; goto done; }
  memset(&action, 0, sizeof(action)); action.sa_handler = forward_signal;
  sigemptyset(&action.sa_mask);
  for (int i = 0; i < 4; i++) {
    if (sigaction(signals[i], &action, &old[i])) {
      for (int j = 0; j < i; j++) sigaction(signals[j], &old[j], NULL);
      sigprocmask(SIG_SETMASK, &oldmask, NULL); result = -5; goto done;
    }
  }
  handlers_set = 1; received_signal = 0; child_pid = 0;
  const char *tmp = getenv("TMPDIR"); if (!tmp || tmp[0] != '/') tmp = "/tmp";
  if (asprintf(&dir, "%s/dsh-desktop-XXXXXX", tmp) < 0) { dir = NULL; result = -3; goto done; }
  if (!mkdtemp(dir)) { free(dir); dir = NULL; result = -3; goto done; }
  dir_fd = open(dir, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  struct stat dir_stat;
  if (dir_fd < 0 || fstat(dir_fd, &dir_stat) || dir_stat.st_uid != geteuid() ||
      (dir_stat.st_mode & 0777) != 0700) { result = -3; goto done; }
  if (asprintf(&gui, "%s/dsh-desktop", dir) < 0 ||
      asprintf(&helper, "%s/dsh", dir) < 0) { result = -3; goto done; }
  uint64_t hash;
  if (copy_part(source, 0, base_size, dir_fd, "dsh", &hash, &blocked)) { result = -3; goto done; }
  if (!argv[0][0]) {
    if (copy_part(source, (off_t)base_size, gui_size, dir_fd, "dsh-desktop", &hash, &blocked)) { result = -3; goto done; }
    if (hash != expected) goto done;
    gui_fd = openat(dir_fd, "dsh-desktop", O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (gui_fd < 0) { result = -3; goto done; }
    argv[0] = gui;
  }
  close(source); source = -1;
  size_t env_count = 0;
  while (environ[env_count]) env_count++;
  environment = calloc(env_count + 2, sizeof(char *));
  if (!environment || asprintf(&worker_environment, "DSH_NATIVE_WORKER_BIN=%s", helper) < 0) {
    result = -3; goto done;
  }
  size_t env_index = 0;
  for (size_t i = 0; i < env_count; i++) {
    if (strncmp(environ[i], "DSH_NATIVE_WORKER_BIN=", 22)) environment[env_index++] = environ[i];
  }
  environment[env_index] = worker_environment;
  if (shutdown_requested(&blocked)) goto done;
  int errors[2]; if (pipe2(errors, O_CLOEXEC)) { result = -3; goto done; }
  pid_t supervisor = getpid();
  if (shutdown_requested(&blocked)) {
    close(errors[0]); close(errors[1]); goto done;
  }
  /* Signals arriving after this check remain blocked until child_pid is
   * published, then the installed handler forwards them to the child. */
  pid_t pid = fork();
  if (pid == 0) {
    close(errors[0]);
    if (setpgid(0, 0) || prctl(PR_SET_PDEATHSIG, SIGTERM) || getppid() != supervisor) {
      int e = errno ? errno : ESRCH; (void)write(errors[1], &e, sizeof(e)); _exit(127);
    }
    for (int i = 0; i < 4; i++) { struct sigaction reset; memset(&reset, 0, sizeof(reset));
      reset.sa_handler = SIG_DFL; sigemptyset(&reset.sa_mask); sigaction(signals[i], &reset, NULL); }
    sigprocmask(SIG_SETMASK, &oldmask, NULL);
    if (gui_fd >= 0) fexecve(gui_fd, argv, environment);
    else execve(argv[0], argv, environment);
    int e = errno; (void)write(errors[1], &e, sizeof(e)); _exit(127);
  }
  close(errors[1]); child_pid = pid > 0 ? pid : 0;
  if (pid > 0) setpgid(pid, pid);
  sigprocmask(SIG_SETMASK, &oldmask, NULL);
  int status = 0, exec_error = 0; ssize_t n;
  do { n = read(errors[0], &exec_error, sizeof(exec_error)); } while (n < 0 && errno == EINTR);
  close(errors[0]);
  if (pid < 0) result = -5;
  else {
    siginfo_t info; int observed;
    do { observed = waitid(P_PID, (id_t)pid, &info, WEXITED | WNOWAIT); } while (observed < 0 && errno == EINTR);
    sigprocmask(SIG_BLOCK, &blocked, NULL);
    child_pid = 0;
    /* The unreaped leader reserves this process-group ID. Kill remaining
     * workers before removing the helper; they belong to this GUI session. */
    if (observed == 0) kill(-pid, SIGTERM);
    pid_t waited; do { waited = waitpid(pid, &status, 0); } while (waited < 0 && errno == EINTR);
    if (observed < 0 || waited < 0) result = -6;
    else if (n > 0) result = exec_error == EACCES ? -4 : -5;
    else if (received_signal) result = 128 + received_signal;
    else result = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
  }
  child_pid = 0;
done:
  if (source >= 0) close(source);
  if (gui_fd >= 0) close(gui_fd);
  if (dir_fd >= 0) {
    unlinkat(dir_fd, "dsh-desktop", 0); unlinkat(dir_fd, "dsh", 0); close(dir_fd);
  }
  if (dir) rmdir(dir);
  free(gui); free(helper); free(dir); free(argv);
  free(environment); free(worker_environment);
  if (handlers_set) {
    sigprocmask(SIG_BLOCK, &blocked, NULL);
    child_pid = 0;
    if (shutdown_requested(&blocked)) result = 128 + received_signal;
    for (int i = 0; i < 4; i++) sigaction(signals[i], &old[i], NULL);
    sigprocmask(SIG_SETMASK, &oldmask, NULL);
  }
  return result;
}
#else
int dsh_linux_desktop_launch(const unsigned char *payload, int length) {
  (void)payload; (void)length; return -1;
}
#endif
