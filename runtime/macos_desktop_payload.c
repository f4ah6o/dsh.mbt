/* Copyright 2026 dsh.mbt contributors. SPDX-License-Identifier: MIT
 * macOS-only packaging/extraction primitive; provider/application logic stays in MoonBit.
 */
#ifdef __APPLE__
#include <CommonCrypto/CommonDigest.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/xattr.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
extern char **environ;
#define DSH_ZIP_LIMIT (512u * 1024u * 1024u)
#define DSH_EXPANDED_LIMIT (1024ull * 1024ull * 1024ull)
#define DSH_ENTRY_LIMIT 4096u
#define DSH_ENVELOPE_SIZE 72u
#define DSH_MANIFEST_LIMIT (8u * 1024u * 1024u)
static const unsigned char dsh_magic[16] = "DSH-MACOS-APP\0\0\0";
static uint16_t dsh_u16(const unsigned char *p) { return p[0] | (uint16_t)p[1] << 8; }
static uint32_t dsh_u32(const unsigned char *p) { return dsh_u16(p) | (uint32_t)dsh_u16(p + 2) << 16; }
static uint64_t dsh_u64(const unsigned char *p) { return dsh_u32(p) | (uint64_t)dsh_u32(p + 4) << 32; }
static int dsh_extra(const unsigned char *p, size_t n) {
  while (n) {
    if (n < 4) return 0;
    unsigned id = dsh_u16(p), len = dsh_u16(p + 2);
    /* The producer uses Unix timestamps. Reject ZIP64, alternate Unicode paths,
       and platform extras which can override the validated names/types. */
    if ((id != 0x5855 && id != 0x5455 && id != 0x7875) || len > n - 4) return 0;
    p += len + 4; n -= len + 4;
  }
  return 1;
}
static int dsh_zip_path(const unsigned char *p, size_t n) {
  const char *root = "Dsh-macos-arm64";
  if (!n || n > 1023 || p[0] == '/') return 0;
  size_t component = 0;
  for (size_t i = 0; i < n; ++i) {
    /* Current release resources use portable ASCII names. This also avoids
       case/Unicode normalization aliases on the destination filesystem. */
    if (p[i] < 32 || p[i] > 126 || p[i] == '\\' || p[i] == ':') return 0;
    if (p[i] == '/') {
      size_t len = i - component;
      if (!len || len > 255 || (len == 1 && p[component] == '.') ||
          (len == 2 && p[component] == '.' && p[component + 1] == '.')) return 0;
      component = i + 1;
    }
  }
  size_t len = n - component;
  if (len > 255 || (len == 1 && p[component] == '.') ||
      (len == 2 && p[component] == '.' && p[component + 1] == '.')) return 0;
  size_t r = strlen(root);
  if (n >= r && !memcmp(p, root, r) && (n == r || p[r] == '/')) return 1;
  const char *meta = "__MACOSX/";
  if (n == 9 && !memcmp(p, meta, 9)) return 1;
  if (n > 9 && !memcmp(p, meta, 9)) {
    p += 9; n -= 9;
    if (n >= r && !memcmp(p, root, r) && (n == r || p[r] == '/')) return 1;
    if (n == r + 2 && !memcmp(p, "._", 2) && !memcmp(p + 2, root, r)) return 1;
  }
  return 0;
}
static int dsh_name_equal(const char *a, const char *b) {
  /* ASCII case-insensitive, with trailing directory slashes ignored. */
  size_t na = strlen(a), nb = strlen(b);
  if (na && a[na - 1] == '/') --na;
  if (nb && b[nb - 1] == '/') --nb;
  if (na != nb) return 0;
  for (size_t i = 0; i < na; ++i) {
    unsigned ca = (unsigned char)a[i], cb = (unsigned char)b[i];
    if (ca >= 'A' && ca <= 'Z') ca += 32;
    if (cb >= 'A' && cb <= 'Z') cb += 32;
    if (ca != cb) return 0;
  }
  return 1;
}
/* Validate both ZIP directories and local headers before handing the private
   verified archive to Apple's ditto, which preserves bundle resources/xattrs. */
static int dsh_validate_zip(const unsigned char *z, size_t n) {
  if (n < 22 || n > DSH_ZIP_LIMIT) return 0;
  const unsigned char *e = z + n - 22;
  unsigned count = dsh_u16(e + 10);
  size_t cd = dsh_u32(e + 16), cds = dsh_u32(e + 12);
  if (dsh_u32(e) != 0x06054b50 || dsh_u16(e + 4) || dsh_u16(e + 6) ||
      dsh_u16(e + 8) != count || !count || count > DSH_ENTRY_LIMIT ||
      dsh_u16(e + 20) || cd > n - 22 || cds != n - 22 - cd) return 0;
  char **names = calloc(count, sizeof(*names));
  if (!names) return 0;
  int ok = 0; size_t pos = cd, previous_end = 0; uint64_t total = 0;
  for (unsigned i = 0; i < count; ++i) {
    if (pos > n - 22 || n - 22 - pos < 46) goto done;
    const unsigned char *c = z + pos;
    unsigned flags = dsh_u16(c + 8), method = dsh_u16(c + 10);
    size_t comp = dsh_u32(c + 20), size = dsh_u32(c + 24);
    size_t name = dsh_u16(c + 28), extra = dsh_u16(c + 30), comment = dsh_u16(c + 32);
    size_t off = dsh_u32(c + 42), length = 46 + name + extra + comment;
    unsigned mode = dsh_u32(c + 38) >> 16, type = mode & S_IFMT;
    if (dsh_u32(c) != 0x02014b50 || length > n - 22 - pos ||
        flags & ~0x0808u || (method != 0 && method != 8) ||
        dsh_u16(c + 34) || comment || !dsh_zip_path(c + 46, name) ||
        !dsh_extra(c + 46 + name, extra) ||
        (type != S_IFREG && type != S_IFDIR) || mode & (S_ISUID | S_ISGID | 0002) || (type == S_IFREG && mode & 0020) ||
        (type == S_IFDIR) != (c[46 + name - 1] == '/') ||
        size > 256u * 1024u * 1024u || (total += size) > DSH_EXPANDED_LIMIT ||
        off != previous_end || off > cd || cd - off < 30) goto done;
    names[i] = malloc(name + 1);
    if (!names[i]) goto done;
    memcpy(names[i], c + 46, name); names[i][name] = 0;
    for (unsigned j = 0; j < i; ++j) if (dsh_name_equal(names[i], names[j])) goto done;
    const unsigned char *l = z + off;
    size_t ln = dsh_u16(l + 26), le = dsh_u16(l + 28), head = 30 + ln + le;
    if (dsh_u32(l) != 0x04034b50 || dsh_u16(l + 6) != flags ||
        dsh_u16(l + 8) != method || ln != name || head > cd - off ||
        memcmp(l + 30, c + 46, name) || !dsh_extra(l + 30 + ln, le) ||
        comp > cd - off - head) goto done;
    previous_end = off + head + comp;
    if (flags & 8) {
      if (cd - previous_end < 12) goto done;
      const unsigned char *d = z + previous_end;
      if (dsh_u32(d) == 0x08074b50) { d += 4; previous_end += 4; }
      if (cd - previous_end < 12 || dsh_u32(d) != dsh_u32(c + 16) ||
          dsh_u32(d + 4) != comp || dsh_u32(d + 8) != size) goto done;
      previous_end += 12;
    } else if (dsh_u32(l + 14) != dsh_u32(c + 16) || dsh_u32(l + 18) != comp ||
               dsh_u32(l + 22) != size) goto done;
    pos += length;
  }
  ok = pos == n - 22 && previous_end == cd;
done:
  for (unsigned i = 0; i < count; ++i) free(names[i]);
  free(names); return ok;
}
static int dsh_command(char *const argv[]) {
  pid_t pid; int status;
  if (posix_spawn(&pid, argv[0], NULL, NULL, argv, environ)) return 0;
  while (waitpid(pid, &status, 0) < 0) if (errno != EINTR) return 0;
  return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}
static int dsh_private_dir(const char *path) {
  if (mkdir(path, 0700) && errno != EEXIST) return 0;
  struct stat st;
  return !lstat(path, &st) && S_ISDIR(st.st_mode) && st.st_uid == getuid() && !(st.st_mode & 0077);
}
static int dsh_remove_tree(const char *path) {
  struct stat st;
  if (lstat(path, &st)) return errno == ENOENT;
  if (!S_ISDIR(st.st_mode)) return unlink(path) == 0;
  DIR *dir = opendir(path); if (!dir) return 0;
  struct dirent *entry; int ok = 1;
  while ((entry = readdir(dir))) {
    if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
    char child[PATH_MAX];
    if (snprintf(child, sizeof(child), "%s/%s", path, entry->d_name) >= (int)sizeof(child) ||
        !dsh_remove_tree(child)) { ok = 0; break; }
  }
  closedir(dir); return ok && rmdir(path) == 0;
}
static int dsh_tree_safe(const char *path, unsigned *entries, uint64_t *bytes) {
  struct stat st;
  if (++*entries > DSH_ENTRY_LIMIT * 2 || lstat(path, &st) || st.st_uid != getuid() ||
      st.st_mode & (S_ISUID | S_ISGID | 0022)) return 0;
  if (S_ISREG(st.st_mode)) {
    *bytes += (uint64_t)st.st_size;
    return st.st_nlink == 1 && *bytes <= DSH_EXPANDED_LIMIT;
  }
  if (!S_ISDIR(st.st_mode)) return 0;
  DIR *dir = opendir(path); if (!dir) return 0;
  struct dirent *entry; int ok = 1;
  while ((entry = readdir(dir))) {
    if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
    char child[PATH_MAX];
    if (snprintf(child, sizeof(child), "%s/%s", path, entry->d_name) >= (int)sizeof(child) ||
        !dsh_tree_safe(child, entries, bytes)) { ok = 0; break; }
  }
  closedir(dir); return ok;
}
/* Bind every cached byte to the immutable manifest carried by this CLI.
   A new ad-hoc signature on a modified cache is not sufficient. */
static int dsh_manifest_matches(const char *root, const unsigned char *m, size_t length) {
  if (length < 4 || length > DSH_MANIFEST_LIMIT) return 0;
  unsigned count = dsh_u32(m); size_t pos = 4;
  if (!count || count > DSH_ENTRY_LIMIT) return 0;
  char previous[1024] = "";
  for (unsigned i = 0; i < count; ++i) {
    if (length - pos < 48) return 0;
    unsigned n = dsh_u32(m + pos), mode = dsh_u32(m + pos + 4);
    uint64_t size = dsh_u64(m + pos + 8);
    const unsigned char *expected = m + pos + 16;
    pos += 48;
    if (!n || n >= sizeof(previous) || n > length - pos ||
        !dsh_zip_path(m + pos, n) || m[pos + n - 1] == '/' ||
        n < 15 || memcmp(m + pos, "Dsh-macos-arm64", 15) ||
        ((mode & S_IFMT) != S_IFREG && (mode & S_IFMT) != S_IFDIR)) return 0;
    char name[1024]; memcpy(name, m + pos, n); name[n] = 0; pos += n;
    if (i && strcmp(previous, name) >= 0) return 0;
    strcpy(previous, name);
    char path[PATH_MAX]; struct stat st;
    if (snprintf(path, sizeof(path), "%s/%s", root, name) >= (int)sizeof(path) ||
        lstat(path, &st) || (st.st_mode & (S_IFMT | 07777)) != mode || st.st_uid != getuid()) return 0;
    if (S_ISDIR(st.st_mode)) { if (size) return 0; continue; }
    if (st.st_nlink != 1 || size != (uint64_t)st.st_size || size > 256u * 1024u * 1024u) return 0;
    int fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) return 0;
    CC_SHA256_CTX context; CC_SHA256_Init(&context);
    unsigned char buffer[65536], digest[CC_SHA256_DIGEST_LENGTH]; uint64_t read_size = 0;
    int ok = 1;
    for (;;) {
      ssize_t nread = read(fd, buffer, sizeof(buffer));
      if (nread < 0 && errno == EINTR) continue;
      if (nread < 0) { ok = 0; break; }
      if (!nread) break;
      read_size += (uint64_t)nread;
      if (read_size > size) { ok = 0; break; }
      CC_SHA256_Update(&context, buffer, (CC_LONG)nread);
    }
    close(fd); CC_SHA256_Final(digest, &context);
    if (!ok || read_size != size || memcmp(expected, digest, sizeof(digest))) return 0;
  }
  unsigned entries = 0; uint64_t bytes = 0;
  return pos == length && dsh_tree_safe(root, &entries, &bytes) && entries == count + 1;
}
static int dsh_bundle_ok(const char *app) {
  const char *required[] = { "/Contents/Info.plist", "/Contents/MacOS/dsh-desktop",
    "/Contents/Helpers/dsh", "/Contents/Frameworks/libgpui_macos.dylib" };
  for (unsigned i = 0; i < sizeof(required) / sizeof(required[0]); ++i) {
    char file[PATH_MAX]; struct stat st;
    if (snprintf(file, sizeof(file), "%s%s", app, required[i]) >= (int)sizeof(file) ||
        lstat(file, &st) || !S_ISREG(st.st_mode) || (i && !(st.st_mode & 0111))) return 0;
  }
  char *args[] = { "/usr/bin/codesign", "--verify", "--deep", "--strict", (char *)app, NULL };
  return dsh_command(args);
}
static int dsh_quarantine(int executable_fd, const char *app) {
  char value[4096];
  ssize_t n = fgetxattr(executable_fd, "com.apple.quarantine", value, sizeof(value), 0, 0);
  if (n < 0) return errno == ENOATTR;
  /* Preserve normal Gatekeeper assessment for a quarantined downloaded CLI. */
  return !setxattr(app, "com.apple.quarantine", value, (size_t)n, 0, XATTR_NOFOLLOW);
}
/* Returns 1 with a verified app path, or a negative bounded diagnostic code. */
static int dsh_extract_bundle(const unsigned char *payload, size_t length,
                              const char *cache, int executable_fd,
                              unsigned char *out, size_t capacity) {
  if (length < DSH_ENVELOPE_SIZE || memcmp(payload, dsh_magic, 16) ||
      dsh_u32(payload + 16) != 2) return -2;
  size_t version_len = dsh_u32(payload + 20), manifest_len = dsh_u32(payload + 64);
  uint64_t zip_size = dsh_u64(payload + 24);
  if (!version_len || version_len > 32 || zip_size > DSH_ZIP_LIMIT ||
      manifest_len < 4 || manifest_len > DSH_MANIFEST_LIMIT || dsh_u32(payload + 68) ||
      length != DSH_ENVELOPE_SIZE + version_len + manifest_len + zip_size) return -2;
  char version[33]; memcpy(version, payload + DSH_ENVELOPE_SIZE, version_len); version[version_len] = 0;
  for (size_t i = 0; i < version_len; ++i) {
    char c = version[i]; if (!((c >= '0' && c <= '9') || c == '.' || c == '-')) return -2;
  }
  const unsigned char *manifest = payload + DSH_ENVELOPE_SIZE + version_len;
  const unsigned char *zip = manifest + manifest_len;
  unsigned char digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(zip, (CC_LONG)zip_size, digest);
  if (memcmp(digest, payload + 32, sizeof(digest)) || !dsh_validate_zip(zip, (size_t)zip_size)) return -2;
  if (!dsh_private_dir(cache)) return -3;
  char hex[65];
  for (unsigned i = 0; i < sizeof(digest); ++i) snprintf(hex + 2 * i, 3, "%02x", digest[i]);
  char destination[PATH_MAX], app[PATH_MAX], lock_path[PATH_MAX], stage[PATH_MAX] = "";
  if (snprintf(destination, sizeof(destination), "%s/%s-%s", cache, version, hex) >= (int)sizeof(destination) ||
      snprintf(app, sizeof(app), "%s/Dsh-macos-arm64/Dsh.app", destination) >= (int)sizeof(app) ||
      snprintf(lock_path, sizeof(lock_path), "%s/.lock-%s", cache, hex) >= (int)sizeof(lock_path)) return -3;
  int lock = open(lock_path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600);
  struct stat st; int result = -3;
  if (lock < 0) return -3;
  if (fstat(lock, &st) || !S_ISREG(st.st_mode) || st.st_uid != getuid() ||
      st.st_nlink != 1 || st.st_mode & 0077 || flock(lock, LOCK_EX)) goto done;
  if (!lstat(destination, &st)) {
    unsigned entries = 0; uint64_t bytes = 0;
    /* Never delete or replace an existing cache entry. Tampering fails closed. */
    if (!S_ISDIR(st.st_mode) || st.st_uid != getuid() || st.st_mode & 0077 ||
        !dsh_tree_safe(destination, &entries, &bytes) ||
        !dsh_manifest_matches(destination, manifest, manifest_len) || !dsh_bundle_ok(app)) { result = -4; goto done; }
  } else {
    if (errno != ENOENT || snprintf(stage, sizeof(stage), "%s/.stage-XXXXXX", cache) >= (int)sizeof(stage) ||
        !mkdtemp(stage)) goto done;
    char archive[PATH_MAX], extracted[PATH_MAX];
    if (snprintf(archive, sizeof(archive), "%s/payload.zip", stage) >= (int)sizeof(archive) ||
        snprintf(extracted, sizeof(extracted), "%s/Dsh-macos-arm64/Dsh.app", stage) >= (int)sizeof(extracted)) goto done;
    int fd = open(archive, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) goto done;
    size_t written = 0;
    while (written < zip_size) {
      ssize_t n = write(fd, zip + written, (size_t)zip_size - written);
      if (n < 0 && errno == EINTR) continue;
      if (n <= 0) { close(fd); goto done; }
      written += (size_t)n;
    }
    int saved = fsync(fd); if (close(fd) || saved) goto done;
    char *args[] = { "/usr/bin/ditto", "-x", "-k", "--sequesterRsrc", archive, stage, NULL };
    unsigned entries = 0; uint64_t bytes = 0;
    if (!dsh_command(args) || unlink(archive) || !dsh_tree_safe(stage, &entries, &bytes) ||
        !dsh_manifest_matches(stage, manifest, manifest_len) || !dsh_bundle_ok(extracted)) { result = -4; goto done; }
    if (!dsh_quarantine(executable_fd, extracted)) { result = -4; goto done; }
    /* A private per-content lock serializes concurrent launches. */
    if (renamex_np(stage, destination, RENAME_EXCL)) goto done;
    stage[0] = 0;
  }
  if (!dsh_quarantine(executable_fd, app)) { result = -4; goto done; }
  if (strlen(app) + 1 > capacity) goto done;
  memcpy(out, app, strlen(app) + 1); result = 1;
done:
  if (stage[0]) dsh_remove_tree(stage);
  close(lock); return result;
}
/* Locate a real Mach-O resource section, rather than appending data after a
   code signature. Normal/source-built helpers have no such section. */
static int dsh_payload_section(const unsigned char *file, size_t size,
                               const unsigned char **payload, size_t *length) {
  if (size < sizeof(struct mach_header_64)) return -2;
  const struct mach_header_64 *h = (const void *)file;
  if (h->magic != MH_MAGIC_64 || h->ncmds > 512 || h->sizeofcmds > 1024 * 1024 ||
      h->sizeofcmds > size - sizeof(*h)) return -2;
  size_t pos = sizeof(*h), end = pos + h->sizeofcmds; int found = 0;
  for (uint32_t i = 0; i < h->ncmds; ++i) {
    if (end - pos < sizeof(struct load_command)) return -2;
    const struct load_command *cmd = (const void *)(file + pos);
    if (cmd->cmdsize < sizeof(*cmd) || cmd->cmdsize % 8 || cmd->cmdsize > end - pos) return -2;
    if (cmd->cmd == LC_SEGMENT_64) {
      if (cmd->cmdsize < sizeof(struct segment_command_64)) return -2;
      const struct segment_command_64 *seg = (const void *)cmd;
      if (seg->nsects > 4096 || seg->nsects > (cmd->cmdsize - sizeof(*seg)) / sizeof(struct section_64)) return -2;
      const struct section_64 *sections = (const void *)(seg + 1);
      for (uint32_t j = 0; j < seg->nsects; ++j) {
        const struct section_64 *s = &sections[j];
        if (!strncmp(s->segname, "__DSH", 16) && !strncmp(s->sectname, "__app_zip", 16)) {
          if (found || s->offset < end || s->size > DSH_ZIP_LIMIT + DSH_MANIFEST_LIMIT + 104ull ||
              s->offset > size || s->size > size - s->offset) return -2;
          *payload = file + s->offset; *length = (size_t)s->size; found = 1;
        }
      }
    }
    pos += cmd->cmdsize;
  }
  return pos == end ? found : -2;
}
int32_t dsh_macos_desktop_bundle(const unsigned char *home, unsigned char *out, int32_t capacity) {
  char executable[PATH_MAX]; uint32_t n = sizeof(executable);
  if (!home || home[0] != '/' || capacity <= 0 || _NSGetExecutablePath(executable, &n)) return -3;
  char resolved[PATH_MAX]; if (!realpath(executable, resolved)) return -3;
  int fd = open(resolved, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
  struct stat st;
  if (fd < 0) return -3;
  if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_size <= 0 || st.st_size > 1024ll * 1024 * 1024) { close(fd); return -2; }
  size_t size = (size_t)st.st_size;
  void *file = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
  if (file == MAP_FAILED) { close(fd); return -3; }
  const unsigned char *payload = NULL; size_t length = 0;
  int result = dsh_payload_section(file, size, &payload, &length);
  if (result == 1) {
    char cache[PATH_MAX], parent[PATH_MAX]; struct stat parent_st;
    if (!realpath((const char *)home, parent) || lstat(parent, &parent_st) ||
        parent_st.st_uid != getuid() || !S_ISDIR(parent_st.st_mode) || parent_st.st_mode & 0022) result = -3;
    const char *parts[] = { "Library", "Caches", "org.fu2hito.dsh", "bundled-desktop" };
    for (unsigned i = 0; result == 1 && i < 4; ++i) {
      if (snprintf(cache, sizeof(cache), "%s/%s", parent, parts[i]) >= (int)sizeof(cache)) { result = -3; break; }
      if (i < 2) {
        if ((mkdir(cache, 0700) && errno != EEXIST) || lstat(cache, &parent_st) ||
            !S_ISDIR(parent_st.st_mode) || parent_st.st_uid != getuid() || parent_st.st_mode & 0022) { result = -3; break; }
      } else if (!dsh_private_dir(cache)) { result = -3; break; }
      strcpy(parent, cache);
    }
    if (result == 1) result = dsh_extract_bundle(payload, length, cache, fd, out, (size_t)capacity);
  }
  munmap(file, size); close(fd); return result;
}
#else
#include <stdint.h>
int32_t dsh_macos_desktop_bundle(const unsigned char *home, unsigned char *out, int32_t capacity) {
  (void)home; (void)out; (void)capacity; return 0;
}
#endif
