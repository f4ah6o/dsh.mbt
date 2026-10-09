#define _DARWIN_C_SOURCE 1
#define _GNU_SOURCE 1

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#if defined(__APPLE__) || defined(__linux__)
#include <signal.h>
#endif

static int dsh_auth_read_random(uint8_t *out, int length) {
  if (!out || length < 0 || length > 4096) return EINVAL;
#if defined(__APPLE__)
  arc4random_buf(out, (size_t)length);
  return 0;
#else
  int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
  if (fd < 0) return errno;
  int offset = 0;
  while (offset < length) {
    ssize_t count = read(fd, out + offset, (size_t)(length - offset));
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) {
      int saved = count == 0 ? EIO : errno;
      close(fd);
      return saved;
    }
    offset += (int)count;
  }
  close(fd);
  return 0;
#endif
}

int dsh_auth_random(uint8_t *out, int length) {
  return dsh_auth_read_random(out, length);
}

static int dsh_auth_pipe_cloexec(int fds[2]) {
  if (pipe(fds) != 0) return errno;
  if (fcntl(fds[0], F_SETFD, FD_CLOEXEC) != 0 ||
      fcntl(fds[1], F_SETFD, FD_CLOEXEC) != 0) {
    int saved = errno;
    close(fds[0]);
    close(fds[1]);
    return saved;
  }
  return 0;
}

int dsh_auth_open_url(const char *url) {
  if (!url || strlen(url) == 0 || strlen(url) > 8192 ||
      (strncmp(url, "https://", 8) != 0 && strncmp(url, "http://", 7) != 0)) {
    return EINVAL;
  }
#if defined(__APPLE__) || defined(__linux__)
  int fds[2];
  int status = dsh_auth_pipe_cloexec(fds);
  if (status != 0) return status;
  pid_t child = fork();
  if (child < 0) {
    status = errno;
    close(fds[0]);
    close(fds[1]);
    return status;
  }
  if (child == 0) {
    close(fds[0]);
    pid_t detached = fork();
    if (detached < 0) {
      int saved = errno;
      (void)write(fds[1], &saved, sizeof(saved));
      _exit(127);
    }
    if (detached > 0) _exit(0);
    (void)setsid();
#if defined(__APPLE__)
    execlp("open", "open", "--", url, (char *)NULL);
#else
    execlp("xdg-open", "xdg-open", url, (char *)NULL);
#endif
    int saved = errno;
    (void)write(fds[1], &saved, sizeof(saved));
    _exit(127);
  }
  close(fds[1]);
  while (waitpid(child, NULL, 0) < 0) {
    if (errno != EINTR) {
      status = errno;
      close(fds[0]);
      return status;
    }
  }
  int child_error = 0;
  ssize_t count;
  do {
    count = read(fds[0], &child_error, sizeof(child_error));
  } while (count < 0 && errno == EINTR);
  close(fds[0]);
  if (count < 0) return errno;
  return count == 0 ? 0 : child_error;
#else
  (void)url;
  return ENOTSUP;
#endif
}

int64_t dsh_auth_unix_time(void) {
  time_t now = time(NULL);
  if (now < 0) return -1;
  return (int64_t)now;
}
