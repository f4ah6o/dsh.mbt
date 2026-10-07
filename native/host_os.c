#define _DARWIN_C_SOURCE 1
#define _GNU_SOURCE 1

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#if defined(__APPLE__) || defined(__linux__)
#include <dirent.h>
#include <signal.h>
#include <dlfcn.h>
#endif

int dsh_fs_open_root(const char *path);
int dsh_fs_root_matches(int root_fd, const char *path);

#if defined(__APPLE__) || defined(__linux__)
static int dsh_dup_cloexec(int fd) {
#ifdef F_DUPFD_CLOEXEC
  return fcntl(fd, F_DUPFD_CLOEXEC, 0);
#else
  int copy = dup(fd);
  if (copy >= 0) fcntl(copy, F_SETFD, FD_CLOEXEC);
  return copy;
#endif
}

static int dsh_component_valid(const char *part, size_t length) {
  if (length == 0 || (length == 1 && part[0] == '.') ||
      (length == 2 && part[0] == '.' && part[1] == '.')) {
    errno = EINVAL;
    return 0;
  }
  return 1;
}

static int dsh_open_parent(int root_fd, const char *path, char *name,
                           size_t name_size) {
  if (!path || !*path || path[0] == '/') {
    errno = EINVAL;
    return -1;
  }
  int current = dsh_dup_cloexec(root_fd);
  if (current < 0) return -1;
  const char *part = path;
  for (;;) {
    const char *slash = strchr(part, '/');
    size_t length = slash ? (size_t)(slash - part) : strlen(part);
    if (!dsh_component_valid(part, length)) {
      close(current);
      return -1;
    }
    if (!slash) {
      if (length + 1 > name_size) {
        close(current);
        errno = ENAMETOOLONG;
        return -1;
      }
      memcpy(name, part, length);
      name[length] = '\0';
      return current;
    }
    char component[NAME_MAX + 1];
    if (length > NAME_MAX) {
      close(current);
      errno = ENAMETOOLONG;
      return -1;
    }
    memcpy(component, part, length);
    component[length] = '\0';
    int next = openat(current, component,
                      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    int saved = errno;
    close(current);
    if (next < 0) {
      errno = saved;
      return -1;
    }
    current = next;
    part = slash + 1;
  }
}

static int dsh_open_directory_beneath(int root_fd, const char *path) {
  if (!path || !*path || strcmp(path, ".") == 0) return dsh_dup_cloexec(root_fd);
  char name[NAME_MAX + 1];
  int parent = dsh_open_parent(root_fd, path, name, sizeof(name));
  if (parent < 0) return -1;
  int fd = openat(parent, name,
                  O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  int saved = errno;
  close(parent);
  errno = saved;
  return fd;
}

/*
 * Dirfd-relative IO prevents symlink traversal, but a directory can still be
 * renamed after it is opened. Compare the directory (or file's parent) held
 * by the anchored walk with a fresh walk from the configured root pathname.
 * Callers check both before and after IO so nested ancestor swaps fail closed.
 */
int dsh_fs_mapping_matches(int root_fd, const char *root_path,
                           const char *relative_path, int is_directory) {
  if (!root_path || !*root_path || !relative_path) return -EINVAL;
  int rooted_status = dsh_fs_root_matches(root_fd, root_path);
  if (rooted_status != 1) return rooted_status;
  int anchored = -1;
  int named = -1;
  if (is_directory) {
    anchored = dsh_open_directory_beneath(root_fd, relative_path);
  } else {
    char name[NAME_MAX + 1];
    anchored = dsh_open_parent(root_fd, relative_path, name, sizeof(name));
  }
  if (anchored < 0) return -errno;
  int named_root = dsh_fs_open_root(root_path);
  if (named_root < 0) {
    int saved = -named_root;
    close(anchored);
    return -saved;
  }
  if (is_directory) {
    named = dsh_open_directory_beneath(named_root, relative_path);
  } else {
    char name[NAME_MAX + 1];
    named = dsh_open_parent(named_root, relative_path, name, sizeof(name));
  }
  int saved = errno;
  close(named_root);
  if (named < 0) {
    close(anchored);
    errno = saved;
    return -saved;
  }
  struct stat anchored_stat, named_stat;
  int status = 0;
  if (fstat(anchored, &anchored_stat) != 0 || fstat(named, &named_stat) != 0) {
    status = -errno;
  } else if (anchored_stat.st_dev != named_stat.st_dev ||
             anchored_stat.st_ino != named_stat.st_ino) {
    status = 0;
  } else {
    status = 1;
  }
  close(anchored);
  close(named);
  return status;
}

static void dsh_copy_stat(const struct stat *st, int64_t *out) {
  out[0] = (int64_t)st->st_dev;
  out[1] = (int64_t)st->st_ino;
  out[2] = (int64_t)st->st_size;
#if defined(__APPLE__)
  out[3] = (int64_t)st->st_mtimespec.tv_sec;
  out[4] = (int64_t)st->st_mtimespec.tv_nsec;
  out[5] = (int64_t)st->st_ctimespec.tv_sec;
  out[6] = (int64_t)st->st_ctimespec.tv_nsec;
#else
  out[3] = (int64_t)st->st_mtim.tv_sec;
  out[4] = (int64_t)st->st_mtim.tv_nsec;
  out[5] = (int64_t)st->st_ctim.tv_sec;
  out[6] = (int64_t)st->st_ctim.tv_nsec;
#endif
  out[7] = (int64_t)st->st_mode;
  out[8] = (int64_t)st->st_uid;
  out[9] = (int64_t)st->st_gid;
}

static int dsh_same_stat(const struct stat *st, const int64_t *expected) {
  int64_t actual[10];
  dsh_copy_stat(st, actual);
  for (int i = 0; i < 10; ++i) {
    if (actual[i] != expected[i]) return 0;
  }
  return 1;
}

int dsh_fs_open_root(const char *path) {
  int fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  return fd < 0 ? -errno : fd;
}

int dsh_fs_root_matches(int root_fd, const char *path) {
  struct stat anchored, current;
  if (fstat(root_fd, &anchored) != 0) return -errno;
  int fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0) return -errno;
  int status = fstat(fd, &current) == 0 ? 0 : -errno;
  close(fd);
  if (status != 0) return status;
  return anchored.st_dev == current.st_dev && anchored.st_ino == current.st_ino ? 1 : 0;
}

int dsh_fs_close(int fd) {
  if (close(fd) == 0) return 0;
  return errno;
}

int dsh_os_flush_stdout(void) {
  return fflush(stdout) == 0 ? 0 : errno;
}

int dsh_fs_set_root_mode(int fd, int mode) {
  if (fchmod(fd, (mode_t)(mode & 0777)) != 0) return errno;
  if (fsync(fd) != 0) return errno;
  return 0;
}

int dsh_fs_open_file(int root_fd, const char *path) {
  char name[NAME_MAX + 1];
  int parent = dsh_open_parent(root_fd, path, name, sizeof(name));
  if (parent < 0) return -errno;
  int fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
  int saved = errno;
  close(parent);
  if (fd < 0) return -saved;
  struct stat st;
  if (fstat(fd, &st) != 0) {
    saved = errno;
    close(fd);
    return -saved;
  }
  if (!S_ISREG(st.st_mode)) {
    close(fd);
    return -EINVAL;
  }
  return fd;
}

int dsh_fs_stat_fd(int fd, int64_t *out) {
  struct stat st;
  if (fstat(fd, &st) != 0) return errno;
  if (!S_ISREG(st.st_mode)) return EINVAL;
  dsh_copy_stat(&st, out);
  return 0;
}

int dsh_fs_stat_root(int fd, int64_t *out) {
  struct stat st;
  if (fstat(fd, &st) != 0) return errno;
  if (!S_ISDIR(st.st_mode)) return ENOTDIR;
  dsh_copy_stat(&st, out);
  return 0;
}

int dsh_fs_read_fd(int fd, uint8_t *buffer, int capacity) {
  if (capacity < 0) return -EINVAL;
  size_t offset = 0;
  while (offset < (size_t)capacity) {
    ssize_t count = pread(fd, buffer + offset, (size_t)capacity - offset,
                          (off_t)offset);
    if (count == 0) break;
    if (count < 0) {
      if (errno == EINTR) continue;
      return -errno;
    }
    offset += (size_t)count;
  }
  return (int)offset;
}

static int dsh_mkdirs_for_file(int root_fd, const char *path, char *name,
                               size_t name_size) {
  if (!path || !*path || path[0] == '/') {
    errno = EINVAL;
    return -1;
  }
  int current = dsh_dup_cloexec(root_fd);
  if (current < 0) return -1;
  const char *part = path;
  for (;;) {
    const char *slash = strchr(part, '/');
    size_t length = slash ? (size_t)(slash - part) : strlen(part);
    if (!dsh_component_valid(part, length)) {
      close(current);
      return -1;
    }
    if (!slash) {
      if (length + 1 > name_size) {
        close(current);
        errno = ENAMETOOLONG;
        return -1;
      }
      memcpy(name, part, length);
      name[length] = '\0';
      return current;
    }
    if (length > NAME_MAX) {
      close(current);
      errno = ENAMETOOLONG;
      return -1;
    }
    char component[NAME_MAX + 1];
    memcpy(component, part, length);
    component[length] = '\0';
    if (mkdirat(current, component, 0755) != 0 && errno != EEXIST) {
      int saved = errno;
      close(current);
      errno = saved;
      return -1;
    }
    int next = openat(current, component,
                      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    int saved = errno;
    close(current);
    if (next < 0) {
      errno = saved;
      return -1;
    }
    current = next;
    part = slash + 1;
  }
}

int dsh_fs_atomic_write(int root_fd, const char *root_path, const char *path,
                        const uint8_t *data,
                        int length, int requested_mode, int create_parents,
                        int has_expected, int force_mode,
                        const int64_t *expected) {
  if (length < 0 || !data) return EINVAL;
  if (!create_parents) {
    int mapping = dsh_fs_mapping_matches(root_fd, root_path, path, 0);
    if (mapping != 1) return mapping < 0 ? -mapping : EAGAIN;
  }
  char name[NAME_MAX + 1];
  int parent = create_parents ? dsh_mkdirs_for_file(root_fd, path, name, sizeof(name))
                              : dsh_open_parent(root_fd, path, name, sizeof(name));
  if (parent < 0) return errno;
  int initial_mapping = dsh_fs_mapping_matches(root_fd, root_path, path, 0);
  if (initial_mapping != 1) {
    int saved = initial_mapping < 0 ? -initial_mapping : EAGAIN;
    close(parent);
    return saved;
  }
  struct stat before;
  int stat_status = fstatat(parent, name, &before, AT_SYMLINK_NOFOLLOW);
  int exists = stat_status == 0;
  if (!exists && errno != ENOENT) {
    int saved = errno;
    close(parent);
    return saved;
  }
  if (exists && !S_ISREG(before.st_mode)) {
    close(parent);
    return EINVAL;
  }
  if (has_expected && (!exists || !dsh_same_stat(&before, expected))) {
    close(parent);
    return EAGAIN;
  }
  mode_t mode = force_mode ? (mode_t)(requested_mode & 0777) :
                exists ? (before.st_mode & 0777) : (mode_t)(requested_mode & 0777);
  static volatile unsigned long serial = 0;
  char temporary[NAME_MAX + 1];
  int fd = -1;
  for (int attempt = 0; attempt < 32; ++attempt) {
    unsigned long next = __sync_add_and_fetch(&serial, 1);
    int n = snprintf(temporary, sizeof(temporary), ".dsh-%ld-%lu.tmp",
                     (long)getpid(), next);
    if (n < 0 || (size_t)n >= sizeof(temporary)) {
      close(parent);
      return ENAMETOOLONG;
    }
    fd = openat(parent, temporary,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode);
    if (fd >= 0 || errno != EEXIST) break;
  }
  if (fd < 0) {
    int saved = errno;
    close(parent);
    return saved;
  }
  int status = 0;
  size_t offset = 0;
  while (offset < (size_t)length) {
    ssize_t count = write(fd, data + offset, (size_t)length - offset);
    if (count < 0) {
      if (errno == EINTR) continue;
      status = errno;
      break;
    }
    offset += (size_t)count;
  }
  if (!status && fchmod(fd, mode) != 0) status = errno;
  if (!status && fsync(fd) != 0) status = errno;
  struct stat temporary_identity;
  int have_temporary_identity = !status && fstat(fd, &temporary_identity) == 0;
  if (!status && !have_temporary_identity) status = errno ? errno : EIO;
  if (close(fd) != 0 && !status) status = errno;
  if (!status && has_expected) {
    struct stat current;
    if (fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) != 0 ||
        !S_ISREG(current.st_mode) || !dsh_same_stat(&current, expected)) {
      status = EAGAIN;
    }
  } else if (!status) {
    struct stat current;
    int current_status = fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW);
    if (current_status == 0 && !S_ISREG(current.st_mode)) status = EINVAL;
    else if (current_status != 0 && errno != ENOENT) status = errno;
  }
  if (!status) {
    int mapping = dsh_fs_mapping_matches(root_fd, root_path, path, 0);
    if (mapping != 1) status = mapping < 0 ? -mapping : EAGAIN;
  }
  if (!status && renameat(parent, temporary, parent, name) != 0) status = errno;
  if (!status) {
    int mapping = dsh_fs_mapping_matches(root_fd, root_path, path, 0);
    if (mapping != 1) {
      struct stat committed;
      if (have_temporary_identity &&
          fstatat(parent, name, &committed, AT_SYMLINK_NOFOLLOW) == 0 &&
          committed.st_dev == temporary_identity.st_dev &&
          committed.st_ino == temporary_identity.st_ino) {
        unlinkat(parent, name, 0);
      }
      status = mapping < 0 ? -mapping : EAGAIN;
    }
  }
  if (!status && fsync(parent) != 0) status = errno;
  if (!status) {
    int mapping = dsh_fs_mapping_matches(root_fd, root_path, path, 0);
    if (mapping != 1) {
      struct stat committed;
      if (have_temporary_identity &&
          fstatat(parent, name, &committed, AT_SYMLINK_NOFOLLOW) == 0 &&
          committed.st_dev == temporary_identity.st_dev &&
          committed.st_ino == temporary_identity.st_ino) {
        unlinkat(parent, name, 0);
        fsync(parent);
      }
      status = mapping < 0 ? -mapping : EAGAIN;
    }
  }
  if (status) unlinkat(parent, temporary, 0);
  close(parent);
  return status;
}

int dsh_fs_create_exclusive(int root_fd, const char *path, const uint8_t *data,
                            int length, int requested_mode) {
  if (length < 0 || !data) return EINVAL;
  char name[NAME_MAX + 1];
  int parent = dsh_open_parent(root_fd, path, name, sizeof(name));
  if (parent < 0) return errno;
  int fd = openat(parent, name,
                  O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                  (mode_t)(requested_mode & 0777));
  if (fd < 0) {
    int saved = errno;
    close(parent);
    return saved;
  }
  int status = 0;
  size_t offset = 0;
  while (offset < (size_t)length) {
    ssize_t count = write(fd, data + offset, (size_t)length - offset);
    if (count < 0) {
      if (errno == EINTR) continue;
      status = errno;
      break;
    }
    offset += (size_t)count;
  }
  if (!status && fsync(fd) != 0) status = errno;
  if (close(fd) != 0 && !status) status = errno;
  if (!status && fsync(parent) != 0) status = errno;
  if (status) unlinkat(parent, name, 0);
  close(parent);
  return status;
}

int dsh_fs_unlink(int root_fd, const char *path) {
  char name[NAME_MAX + 1];
  int parent = dsh_open_parent(root_fd, path, name, sizeof(name));
  if (parent < 0) return errno;
  int status = unlinkat(parent, name, 0) == 0 ? 0 : errno;
  if (!status && fsync(parent) != 0) status = errno;
  close(parent);
  return status;
}

int dsh_fs_list_dir(int root_fd, const char *path, uint8_t *buffer,
                    int capacity) {
  if (capacity < 0) return -EINVAL;
  int fd = dsh_open_directory_beneath(root_fd, path);
  if (fd < 0) return -errno;
  /* A dup shares the directory-stream offset with the anchored root FD.
   * Open "." to give fdopendir an independent open-file description. */
  int scan_fd = openat(fd, ".",
                       O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  int saved = errno;
  close(fd);
  if (scan_fd < 0) {
    errno = saved;
    return -saved;
  }
  DIR *dir = fdopendir(scan_fd);
  if (!dir) {
    int saved = errno;
    close(scan_fd);
    return -saved;
  }
  size_t used = 0;
  struct dirent *entry;
  for (;;) {
    errno = 0;
    entry = readdir(dir);
    if (!entry) {
      int saved = errno;
      if (saved) {
        closedir(dir);
        return -saved;
      }
      break;
    }
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
    struct stat st;
    if (fstatat(dirfd(dir), entry->d_name, &st, AT_SYMLINK_NOFOLLOW) != 0) {
      if (errno == ENOENT || errno == ENOTDIR) continue;
      int saved = errno;
      closedir(dir);
      return -saved;
    }
    char kind = S_ISDIR(st.st_mode) ? 'D' : S_ISREG(st.st_mode) ? 'F' : 'X';
    if (kind == 'X') continue;
    size_t name_len = strlen(entry->d_name);
    if (used + name_len + 2 > (size_t)capacity) {
      closedir(dir);
      return -ENOBUFS;
    }
    memcpy(buffer + used, entry->d_name, name_len);
    used += name_len;
    buffer[used++] = 0;
    buffer[used++] = (uint8_t)kind;
  }
  closedir(dir);
  return (int)used;
}

int dsh_fs_sync_directory(const char *path) {
  int fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0) return errno;
  int status = fsync(fd) == 0 ? 0 : errno;
  close(fd);
  return status;
}

int dsh_os_uid(void) { return (int)getuid(); }
int dsh_os_pid(void) { return (int)getpid(); }
int dsh_os_hostname(uint8_t *buffer, int capacity) {
  if (!buffer || capacity <= 1) return -EINVAL;
  char hostname[256];
  if (gethostname(hostname, sizeof(hostname)) != 0) return -errno;
  hostname[sizeof(hostname) - 1] = '\0';
  size_t length = strlen(hostname);
  if (length + 1 > (size_t)capacity) return -ENOBUFS;
  memcpy(buffer, hostname, length + 1);
  return (int)length;
}
int dsh_os_timestamp(uint8_t *buffer, int capacity) {
  if (!buffer || capacity < 25) return -EINVAL;
  time_t now = time(NULL);
  struct tm value;
  if (gmtime_r(&now, &value) == NULL) return -errno;
  int count = snprintf((char *)buffer, (size_t)capacity,
                       "%04d-%02d-%02dT%02d:%02d:%02dZ",
                       value.tm_year + 1900, value.tm_mon + 1, value.tm_mday,
                       value.tm_hour, value.tm_min, value.tm_sec);
  if (count < 0 || count >= capacity) return -ENOBUFS;
  return count;
}
int dsh_os_process_alive(int pid) {
  if (pid <= 0) return 1;
  if (kill(pid, 0) == 0 || errno == EPERM) return 1;
  return errno != ESRCH;
}

int dsh_os_hard_worker_memory_supported(void) {
#if defined(__linux__) && defined(RLIMIT_AS)
  return 1;
#else
  return 0;
#endif
}

int dsh_kill_process_group(int pid, int signal_number) {
  if (pid <= 0 || signal_number <= 0) return EINVAL;
  if (kill(-pid, signal_number) == 0) return 0;
  return errno;
}

int dsh_kill_process(int pid, int signal_number) {
  if (pid <= 0 || signal_number <= 0) return EINVAL;
  if (kill((pid_t)pid, signal_number) == 0) return 0;
  return errno;
}

static int dsh_parse_number_field(char **cursor, char *limit,
                                  long long *value) {
  if (!cursor || !*cursor || *cursor >= limit || !value) return 0;
  char *end = NULL;
  errno = 0;
  long long parsed = strtoll(*cursor, &end, 10);
  if (errno || end == *cursor || end >= limit || *end != '\0') return 0;
  *cursor = end + 1;
  *value = parsed;
  return 1;
}

/*
 * The official async process API does not expose posix_spawn attributes.
 * This child trampoline applies hard resource caps and creates a new session
 * before executing a workspace tool. Its PID is therefore the process-group
 * and session ID used to terminate descendants after the leader exits.
 */
int dsh_exec_worker(const uint8_t *payload, int length) {
  if (!payload || length < 8 || payload[length - 1] != 0) return EINVAL;
  char *storage = (char *)malloc((size_t)length + 1);
  if (!storage) return ENOMEM;
  memcpy(storage, payload, (size_t)length);
  storage[length] = '\0';

  char *limit = storage + length;
  char *cursor = storage;
  long long memory_mb = 0;
  long long cpu_seconds = 0;
  long long expected_device = 0;
  long long expected_inode = 0;
  if (!dsh_parse_number_field(&cursor, limit, &memory_mb) ||
      !dsh_parse_number_field(&cursor, limit, &cpu_seconds) ||
      !dsh_parse_number_field(&cursor, limit, &expected_device) ||
      !dsh_parse_number_field(&cursor, limit, &expected_inode) ||
      memory_mb < 64 || memory_mb > 16384 || cpu_seconds < 1 ||
      cpu_seconds > 3600 || expected_device < 0 || expected_inode < 0) {
    free(storage);
    return EINVAL;
  }
  char *workspace_path = cursor;
  char *workspace_end = (char *)memchr(
      workspace_path, '\0', (size_t)(limit - workspace_path));
  if (!workspace_end || workspace_end == workspace_path ||
      workspace_path[0] != '/') {
    free(storage);
    return EINVAL;
  }
  int workspace_fd = open(workspace_path,
                          O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (workspace_fd < 0) {
    int saved = errno;
    free(storage);
    return saved;
  }
  struct stat workspace_stat;
  if (fstat(workspace_fd, &workspace_stat) != 0) {
    int saved = errno;
    close(workspace_fd);
    free(storage);
    return saved;
  }
  if ((long long)workspace_stat.st_dev != expected_device ||
      (long long)workspace_stat.st_ino != expected_inode) {
    close(workspace_fd);
    free(storage);
    return ESTALE;
  }
  if (fchdir(workspace_fd) != 0) {
    int saved = errno;
    close(workspace_fd);
    free(storage);
    return saved;
  }
  if (dsh_fs_root_matches(workspace_fd, workspace_path) != 1) {
    close(workspace_fd);
    free(storage);
    return ESTALE;
  }
  cursor = workspace_end + 1;
  long long argc_long = 0;
  if (!dsh_parse_number_field(&cursor, limit, &argc_long) || argc_long < 1 ||
      argc_long > 4096) {
    free(storage);
    return EINVAL;
  }
  int argc = (int)argc_long;
  size_t remaining = (size_t)(limit - cursor);
  char **argv = (char **)calloc((size_t)argc + 1, sizeof(char *));
  if (!argv) {
    free(storage);
    return ENOMEM;
  }
  size_t offset = 0;
  for (int i = 0; i < argc; ++i) {
    if (offset >= remaining) {
      free(argv);
      free(storage);
      return EINVAL;
    }
    char *length_end = NULL;
    errno = 0;
    long argument_length = strtol(cursor + offset, &length_end, 10);
    if (errno || length_end == cursor + offset || length_end >= limit ||
        *length_end != ':' || argument_length < 0 ||
        (size_t)argument_length > remaining - offset) {
      free(argv);
      free(storage);
      return EINVAL;
    }
    char *argument = length_end + 1;
    size_t header_length = (size_t)(argument - (cursor + offset));
    if (header_length + (size_t)argument_length >= remaining - offset ||
        argument[argument_length] != '\0') {
      free(argv);
      free(storage);
      return EINVAL;
    }
    argv[i] = argument;
    offset += header_length + (size_t)argument_length + 1;
  }
  if (offset != remaining) {
    free(argv);
    free(storage);
    return EINVAL;
  }
  argv[argc] = NULL;

  struct rlimit memory_limit;
  memory_limit.rlim_cur = (rlim_t)memory_mb * 1024 * 1024;
  memory_limit.rlim_max = memory_limit.rlim_cur;
#if defined(__linux__) && defined(RLIMIT_AS)
  /* Linux enforces an address-space cap for the isolated worker session. */
  if (setrlimit(RLIMIT_AS, &memory_limit) != 0) {
    int saved = errno;
    free(argv);
    free(storage);
    return saved;
  }
#elif defined(__linux__) && defined(RLIMIT_RSS)
  if (setrlimit(RLIMIT_RSS, &memory_limit) != 0) {
    int saved = errno;
    free(argv);
    free(storage);
    return saved;
  }
#else
  /* Darwin exposes RLIMIT_AS/RLIMIT_RSS constants but rejects setting them.
   * Regex grep is disabled on that platform rather than run without a hard
   * memory boundary. The explicitly approved bash tool remains time/output
   * bounded and is documented as a trusted-host capability.
   */
  (void)memory_limit;
#endif
  struct rlimit cpu_limit;
  cpu_limit.rlim_cur = (rlim_t)cpu_seconds;
  cpu_limit.rlim_max = (rlim_t)cpu_seconds + 1;
  if (setrlimit(RLIMIT_CPU, &cpu_limit) != 0) {
    int saved = errno;
    free(argv);
    free(storage);
    return saved;
  }
  if (setsid() < 0) {
    int saved = errno;
    free(argv);
    free(storage);
    return saved;
  }
  if (dsh_fs_root_matches(workspace_fd, workspace_path) != 1) {
    close(workspace_fd);
    free(argv);
    free(storage);
    return ESTALE;
  }
  close(workspace_fd);
  execvp(argv[0], argv);
  int saved = errno;
  free(argv);
  free(storage);
  return saved;
}

#else
int dsh_fs_open_root(const char *path) { (void)path; return -ENOTSUP; }
int dsh_fs_root_matches(int root_fd, const char *path) { (void)root_fd; (void)path; return -ENOTSUP; }
int dsh_fs_mapping_matches(int root_fd, const char *root_path, const char *relative_path, int is_directory) { (void)root_fd; (void)root_path; (void)relative_path; (void)is_directory; return -ENOTSUP; }
int dsh_fs_close(int fd) { (void)fd; return ENOTSUP; }
int dsh_os_flush_stdout(void) { return fflush(stdout) == 0 ? 0 : errno; }
int dsh_fs_set_root_mode(int fd, int mode) { (void)fd; (void)mode; return ENOTSUP; }
int dsh_fs_open_file(int root_fd, const char *path) { (void)root_fd; (void)path; return -ENOTSUP; }
int dsh_fs_stat_fd(int fd, int64_t *out) { (void)fd; (void)out; return ENOTSUP; }
int dsh_fs_stat_root(int fd, int64_t *out) { (void)fd; (void)out; return ENOTSUP; }
int dsh_fs_read_fd(int fd, uint8_t *buffer, int capacity) { (void)fd; (void)buffer; (void)capacity; return -ENOTSUP; }
int dsh_fs_atomic_write(int root_fd, const char *root_path, const char *path, const uint8_t *data, int length, int mode, int create_parents, int has_expected, int force_mode, const int64_t *expected) { (void)root_fd; (void)root_path; (void)path; (void)data; (void)length; (void)mode; (void)create_parents; (void)has_expected; (void)force_mode; (void)expected; return ENOTSUP; }
int dsh_fs_list_dir(int root_fd, const char *path, uint8_t *buffer, int capacity) { (void)root_fd; (void)path; (void)buffer; (void)capacity; return -ENOTSUP; }
int dsh_fs_sync_directory(const char *path) { (void)path; return ENOTSUP; }
int dsh_os_uid(void) { return -1; }
int dsh_os_pid(void) { return -1; }
int dsh_os_hostname(uint8_t *buffer, int capacity) { (void)buffer; (void)capacity; return -ENOTSUP; }
int dsh_os_timestamp(uint8_t *buffer, int capacity) { (void)buffer; (void)capacity; return -ENOTSUP; }
int dsh_os_process_alive(int pid) { (void)pid; return 1; }
int dsh_os_hard_worker_memory_supported(void) { return 0; }
int dsh_kill_process_group(int pid, int signal_number) { (void)pid; (void)signal_number; return ENOTSUP; }
int dsh_kill_process(int pid, int signal_number) { (void)pid; (void)signal_number; return ENOTSUP; }
int dsh_exec_worker(const uint8_t *payload, int length) { (void)payload; (void)length; return ENOTSUP; }
#endif

#if defined(__APPLE__) || defined(__linux__)
typedef struct bignum_st BIGNUM;
typedef struct rsa_st RSA;
typedef struct evp_pkey_st EVP_PKEY;
typedef struct evp_md_st EVP_MD;
typedef struct evp_md_ctx_st EVP_MD_CTX;
typedef struct evp_pkey_ctx_st EVP_PKEY_CTX;
typedef struct engine_st ENGINE;

static void *dsh_crypto_handle(void) {
  static void *handle = NULL;
  static int attempted = 0;
  if (attempted) return handle;
  attempted = 1;
#ifdef __APPLE__
  handle = dlopen("/usr/lib/libcrypto.48.dylib", RTLD_LAZY | RTLD_LOCAL);
  if (!handle) handle = dlopen("/usr/lib/libcrypto.46.dylib", RTLD_LAZY | RTLD_LOCAL);
  if (!handle) handle = dlopen("/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib", RTLD_LAZY | RTLD_LOCAL);
  if (!handle) handle = dlopen("/usr/local/opt/openssl@3/lib/libcrypto.3.dylib", RTLD_LAZY | RTLD_LOCAL);
#else
  handle = dlopen("libcrypto.so.3", RTLD_LAZY | RTLD_LOCAL);
  if (!handle) handle = dlopen("libcrypto.so.1.1", RTLD_LAZY | RTLD_LOCAL);
  if (!handle) handle = dlopen("libcrypto.so", RTLD_LAZY | RTLD_LOCAL);
#endif
  return handle;
}

int dsh_crypto_sha256(const uint8_t *data, int length, uint8_t *output) {
  if (!data || length < 0 || !output) return 0;
  void *handle = dsh_crypto_handle();
  if (!handle) return 0;
  unsigned char *(*sha256)(const unsigned char *, size_t, unsigned char *) =
      (unsigned char *(*)(const unsigned char *, size_t, unsigned char *))dlsym(handle, "SHA256");
  if (!sha256) return 0;
  return sha256(data, (size_t)length, output) == output;
}

int dsh_crypto_verify_rs256(const uint8_t *modulus, int modulus_len,
                            const uint8_t *exponent, int exponent_len,
                            const uint8_t *message, int message_len,
                            const uint8_t *signature, int signature_len) {
  if (!modulus || !exponent || !message || !signature || modulus_len <= 0 ||
      exponent_len <= 0 || message_len < 0 || signature_len <= 0) return 0;
  void *handle = dsh_crypto_handle();
  if (!handle) return 0;
  BIGNUM *(*bn_bin2bn)(const unsigned char *, int, BIGNUM *) =
      (BIGNUM *(*)(const unsigned char *, int, BIGNUM *))dlsym(handle, "BN_bin2bn");
  RSA *(*rsa_new)(void) = (RSA *(*)(void))dlsym(handle, "RSA_new");
  int (*rsa_set0_key)(RSA *, BIGNUM *, BIGNUM *, BIGNUM *) =
      (int (*)(RSA *, BIGNUM *, BIGNUM *, BIGNUM *))dlsym(handle, "RSA_set0_key");
  void (*rsa_free)(RSA *) = (void (*)(RSA *))dlsym(handle, "RSA_free");
  void (*bn_free)(BIGNUM *) = (void (*)(BIGNUM *))dlsym(handle, "BN_free");
  EVP_PKEY *(*pkey_new)(void) = (EVP_PKEY *(*)(void))dlsym(handle, "EVP_PKEY_new");
  int (*pkey_assign_rsa)(EVP_PKEY *, int, void *) =
      (int (*)(EVP_PKEY *, int, void *))dlsym(handle, "EVP_PKEY_assign_RSA");
  if (pkey_assign_rsa == NULL) {
    // OpenSSL 3 exports the generic function; the RSA-specific public name is
    // a macro wrapper and is not necessarily present in libcrypto's symbols.
    pkey_assign_rsa =
        (int (*)(EVP_PKEY *, int, void *))dlsym(handle, "EVP_PKEY_assign");
  }
  void (*pkey_free)(EVP_PKEY *) = (void (*)(EVP_PKEY *))dlsym(handle, "EVP_PKEY_free");
  const EVP_MD *(*sha256_md)(void) = (const EVP_MD *(*)(void))dlsym(handle, "EVP_sha256");
  EVP_MD_CTX *(*md_ctx_new)(void) = (EVP_MD_CTX *(*)(void))dlsym(handle, "EVP_MD_CTX_new");
  void (*md_ctx_free)(EVP_MD_CTX *) = (void (*)(EVP_MD_CTX *))dlsym(handle, "EVP_MD_CTX_free");
  int (*verify_init)(EVP_MD_CTX *, EVP_PKEY_CTX **, const EVP_MD *, ENGINE *, EVP_PKEY *) =
      (int (*)(EVP_MD_CTX *, EVP_PKEY_CTX **, const EVP_MD *, ENGINE *, EVP_PKEY *))dlsym(handle, "EVP_DigestVerifyInit");
  int (*verify_update)(EVP_MD_CTX *, const void *, size_t) =
      (int (*)(EVP_MD_CTX *, const void *, size_t))dlsym(handle, "EVP_DigestVerifyUpdate");
  if (!verify_update) {
    // LibreSSL exposes the verification update step through the shared
    // EVP_DigestUpdate entry point instead of OpenSSL's verify-specific name.
    verify_update =
        (int (*)(EVP_MD_CTX *, const void *, size_t))dlsym(handle, "EVP_DigestUpdate");
  }
  int (*verify_final)(EVP_MD_CTX *, const unsigned char *, size_t) =
      (int (*)(EVP_MD_CTX *, const unsigned char *, size_t))dlsym(handle, "EVP_DigestVerifyFinal");
  if (!bn_bin2bn || !bn_free || !rsa_new || !rsa_set0_key || !rsa_free || !pkey_new ||
      !pkey_assign_rsa || !pkey_free || !sha256_md || !md_ctx_new ||
      !md_ctx_free || !verify_init || !verify_update || !verify_final) return 0;

  BIGNUM *n = bn_bin2bn(modulus, modulus_len, NULL);
  BIGNUM *e = bn_bin2bn(exponent, exponent_len, NULL);
  RSA *rsa = rsa_new();
  EVP_PKEY *pkey = pkey_new();
  EVP_MD_CTX *ctx = md_ctx_new();
  if (!n || !e || !rsa || !pkey || !ctx) {
    if (n) bn_free(n);
    if (e) bn_free(e);
    if (rsa) rsa_free(rsa);
    if (pkey) pkey_free(pkey);
    if (ctx) md_ctx_free(ctx);
    return 0;
  }
  if (rsa_set0_key(rsa, n, e, NULL) != 1) {
    bn_free(n);
    bn_free(e);
    rsa_free(rsa);
    pkey_free(pkey);
    md_ctx_free(ctx);
    return 0;
  }
  // NID_rsaEncryption is 6 in the OpenSSL ABI; EVP_PKEY_assign_RSA takes
  // ownership of `rsa` on success.
  if (pkey_assign_rsa(pkey, 6, rsa) != 1) {
    rsa_free(rsa);
    pkey_free(pkey);
    md_ctx_free(ctx);
    return 0;
  }
  int valid = verify_init(ctx, NULL, sha256_md(), NULL, pkey) == 1 &&
              verify_update(ctx, message, (size_t)message_len) == 1 &&
              verify_final(ctx, signature, (size_t)signature_len) == 1;
  md_ctx_free(ctx);
  pkey_free(pkey);
  return valid;
}
#else
int dsh_crypto_sha256(const uint8_t *data, int length, uint8_t *output) { (void)data; (void)length; (void)output; return 0; }
int dsh_crypto_verify_rs256(const uint8_t *modulus, int modulus_len, const uint8_t *exponent, int exponent_len, const uint8_t *message, int message_len, const uint8_t *signature, int signature_len) { (void)modulus; (void)modulus_len; (void)exponent; (void)exponent_len; (void)message; (void)message_len; (void)signature; (void)signature_len; return 0; }
#endif
