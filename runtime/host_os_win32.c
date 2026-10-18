/*
 * Windows x64 native OS boundary for dsh.
 *
 * The POSIX boundary in host_os.c anchors every operation on an open dirfd so
 * a rename or symlink swap between check and use cannot redirect IO. Windows
 * has no portable openat(), so this file approximates the same contract:
 *
 *   - every component is opened with FILE_FLAG_OPEN_REPARSE_POINT and must
 *     carry no FILE_ATTRIBUTE_REPARSE_POINT (junction / symlink / mount point),
 *   - the configured root is a directory handle whose identity is re-checked
 *     before each operation,
 *   - the anchored walk and the fresh pathname walk are compared by volume
 *     serial + file index before and after a commit.
 *
 * The guarantee is path-based: a same-user attacker that swaps a directory
 * between the final check and the rename can still win the race. Windows is
 * not treated as a sandbox; see docs/native-runtime.md.
 *
 * Handles are exposed to MoonBit as small table indexes so a 64-bit HANDLE is
 * never truncated into an Int32.
 */

#define _WIN32_WINNT 0x0A00
#define WIN32_LEAN_AND_MEAN
#define _CRT_SECURE_NO_WARNINGS

#include <windows.h>
#include <aclapi.h>
#include <bcrypt.h>
#include <fcntl.h>
#include <io.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <wchar.h>

#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "bcrypt.lib")

/* POSIX-style codes exchanged with the MoonBit layer. Values are spelled out
 * because the CRT's errno.h does not match Linux. */
enum {
  DSH_ENOENT = 2,
  DSH_EIO = 5,
  DSH_EBADF = 9,
  DSH_EAGAIN = 11,
  DSH_ENOMEM = 12,
  DSH_EACCES = 13,
  DSH_EEXIST = 17,
  DSH_EXDEV = 18,
  DSH_ENOTDIR = 20,
  DSH_EINVAL = 22,
  DSH_ENOSPC = 28,
  DSH_ENAMETOOLONG = 36,
  DSH_ENOTSUP = 95,
  DSH_ENOBUFS = 105,
  DSH_ESTALE = 116
};

#define DSH_MAX_HANDLES 256
#define DSH_FD_BASE 3
#define DSH_MAX_WIDE_PATH 32767

static int dsh_map_win_error(DWORD error) {
  switch (error) {
    case ERROR_FILE_NOT_FOUND:
    case ERROR_PATH_NOT_FOUND:
    case ERROR_INVALID_DRIVE:
    case ERROR_BAD_NETPATH:
      return DSH_ENOENT;
    case ERROR_ACCESS_DENIED:
    case ERROR_PRIVILEGE_NOT_HELD:
    case ERROR_WRITE_PROTECT:
      return DSH_EACCES;
    case ERROR_INVALID_HANDLE:
      return DSH_EBADF;
    case ERROR_ALREADY_EXISTS:
    case ERROR_FILE_EXISTS:
      return DSH_EEXIST;
    case ERROR_INVALID_PARAMETER:
    case ERROR_INVALID_NAME:
    case ERROR_BAD_PATHNAME:
    case ERROR_INVALID_REPARSE_DATA:
      return DSH_EINVAL;
    case ERROR_DISK_FULL:
    case ERROR_HANDLE_DISK_FULL:
      return DSH_ENOSPC;
    case ERROR_NOT_SUPPORTED:
    case ERROR_INVALID_FUNCTION:
    case ERROR_CALL_NOT_IMPLEMENTED:
      return DSH_ENOTSUP;
    case ERROR_SHARING_VIOLATION:
    case ERROR_LOCK_VIOLATION:
    case ERROR_BUSY:
      return DSH_EAGAIN;
    case ERROR_DIRECTORY:
      return DSH_ENOTDIR;
    case ERROR_FILENAME_EXCED_RANGE:
      return DSH_ENAMETOOLONG;
    case ERROR_NOT_SAME_DEVICE:
      return DSH_EXDEV;
    case ERROR_OUTOFMEMORY:
    case ERROR_NOT_ENOUGH_MEMORY:
      return DSH_ENOMEM;
    default:
      return DSH_EIO;
  }
}

/* ------------------------------------------------------------------ */
/* Handle table                                                        */
/* ------------------------------------------------------------------ */

typedef struct {
  HANDLE handle;
  wchar_t *root_path;
  int used;
} dsh_handle_entry;

static SRWLOCK dsh_handle_lock = SRWLOCK_INIT;
static dsh_handle_entry dsh_handles[DSH_MAX_HANDLES];

static int dsh_table_alloc(HANDLE handle, const wchar_t *root_path, int *fd_out) {
  int index = -1;
  AcquireSRWLockExclusive(&dsh_handle_lock);
  for (int i = 0; i < DSH_MAX_HANDLES; ++i) {
    if (dsh_handles[i].used) continue;
    wchar_t *copy = NULL;
    if (root_path) {
      size_t length = wcslen(root_path);
      copy = (wchar_t *)malloc((length + 1) * sizeof(wchar_t));
      if (!copy) break;
      memcpy(copy, root_path, (length + 1) * sizeof(wchar_t));
    }
    dsh_handles[i].used = 1;
    dsh_handles[i].handle = handle;
    dsh_handles[i].root_path = copy;
    index = i;
    break;
  }
  ReleaseSRWLockExclusive(&dsh_handle_lock);
  if (index < 0) return DSH_ENOMEM;
  *fd_out = index + DSH_FD_BASE;
  return 0;
}

static int dsh_table_handle(int fd, HANDLE *handle_out) {
  if (fd < DSH_FD_BASE || fd >= DSH_FD_BASE + DSH_MAX_HANDLES) return DSH_EBADF;
  int status = 0;
  AcquireSRWLockShared(&dsh_handle_lock);
  dsh_handle_entry *entry = &dsh_handles[fd - DSH_FD_BASE];
  if (!entry->used) {
    status = DSH_EBADF;
  } else {
    *handle_out = entry->handle;
  }
  ReleaseSRWLockShared(&dsh_handle_lock);
  return status;
}

static int dsh_table_root_path(int fd, wchar_t *buffer, size_t capacity) {
  if (fd < DSH_FD_BASE || fd >= DSH_FD_BASE + DSH_MAX_HANDLES) return DSH_EBADF;
  int status = 0;
  AcquireSRWLockShared(&dsh_handle_lock);
  dsh_handle_entry *entry = &dsh_handles[fd - DSH_FD_BASE];
  if (!entry->used || !entry->root_path) {
    status = DSH_EBADF;
  } else {
    size_t length = wcslen(entry->root_path);
    if (length + 1 > capacity) {
      status = DSH_ENAMETOOLONG;
    } else {
      memcpy(buffer, entry->root_path, (length + 1) * sizeof(wchar_t));
    }
  }
  ReleaseSRWLockShared(&dsh_handle_lock);
  return status;
}

static int dsh_table_close(int fd) {
  if (fd < DSH_FD_BASE || fd >= DSH_FD_BASE + DSH_MAX_HANDLES) return DSH_EBADF;
  HANDLE handle = NULL;
  wchar_t *root_path = NULL;
  AcquireSRWLockExclusive(&dsh_handle_lock);
  dsh_handle_entry *entry = &dsh_handles[fd - DSH_FD_BASE];
  if (!entry->used) {
    ReleaseSRWLockExclusive(&dsh_handle_lock);
    return DSH_EBADF;
  }
  handle = entry->handle;
  root_path = entry->root_path;
  entry->used = 0;
  entry->handle = NULL;
  entry->root_path = NULL;
  ReleaseSRWLockExclusive(&dsh_handle_lock);
  free(root_path);
  if (handle && handle != INVALID_HANDLE_VALUE) CloseHandle(handle);
  return 0;
}

/* ------------------------------------------------------------------ */
/* Path conversion and validation                                      */
/* ------------------------------------------------------------------ */

static int dsh_utf8_to_wide(const char *text, wchar_t **out) {
  if (!text || !out) return DSH_EINVAL;
  int needed = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, NULL, 0);
  if (needed <= 0) return DSH_EINVAL;
  wchar_t *buffer = (wchar_t *)calloc((size_t)needed, sizeof(wchar_t));
  if (!buffer) return DSH_ENOMEM;
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, buffer,
                          needed) <= 0) {
    free(buffer);
    return DSH_EINVAL;
  }
  *out = buffer;
  return 0;
}

static int dsh_wide_to_utf8(const wchar_t *text, int length, char *out,
                            int capacity) {
  if (!text || !out || capacity <= 0) return DSH_EINVAL;
  int needed = WideCharToMultiByte(CP_UTF8, 0, text, length, NULL, 0, NULL, NULL);
  if (needed <= 0) return DSH_EINVAL;
  if (needed + 1 > capacity) return DSH_ENAMETOOLONG;
  if (WideCharToMultiByte(CP_UTF8, 0, text, length, out, capacity, NULL, NULL) <= 0) {
    return DSH_EINVAL;
  }
  out[needed] = '\0';
  return needed;
}

static int dsh_is_separator(wchar_t value) {
  return value == L'\\' || value == L'/';
}

static int dsh_drive_absolute(const wchar_t *path) {
  return ((path[0] >= L'A' && path[0] <= L'Z') ||
          (path[0] >= L'a' && path[0] <= L'z')) &&
         path[1] == L':' && dsh_is_separator(path[2]);
}

static int dsh_unc_absolute(const wchar_t *path) {
  if (!dsh_is_separator(path[0]) || !dsh_is_separator(path[1])) return 0;
  if (path[2] == L'\0' || dsh_is_separator(path[2])) return 0;
  const wchar_t *share = wcschr(path + 2, L'\\');
  return share != NULL && share[1] != L'\0' && !dsh_is_separator(share[1]);
}

/* Normalize an absolute Windows path into "C:\dir\file" (local) or
 * "\\server\share\dir" (UNC). "\\?\" and "\\.\" prefixes are not stored. */
static int dsh_normalize_root(const char *utf8, wchar_t **out) {
  wchar_t *wide = NULL;
  int status = dsh_utf8_to_wide(utf8, &wide);
  if (status != 0) return status;
  size_t length = wcslen(wide);
  if (length == 0) {
    free(wide);
    return DSH_EINVAL;
  }
  if (length >= DSH_MAX_WIDE_PATH) {
    free(wide);
    return DSH_ENAMETOOLONG;
  }
  for (size_t i = 0; i < length; ++i) {
    if (dsh_is_separator(wide[i])) wide[i] = L'\\';
  }
  const wchar_t *source = wide;
  if (wcsncmp(source, L"\\\\?\\", 4) == 0) {
    source += 4;
    if (wcsncmp(source, L"UNC\\", 4) == 0) {
      size_t rest = wcslen(source + 4);
      wchar_t *rebuilt = (wchar_t *)calloc(rest + 3, sizeof(wchar_t));
      if (!rebuilt) {
        free(wide);
        return DSH_ENOMEM;
      }
      rebuilt[0] = L'\\';
      rebuilt[1] = L'\\';
      memcpy(rebuilt + 2, source + 4, (rest + 1) * sizeof(wchar_t));
      free(wide);
      wide = rebuilt;
      source = rebuilt;
    }
  } else if (wcsncmp(source, L"\\\\.\\", 4) == 0) {
    free(wide);
    return DSH_EINVAL;
  }
  int drive = dsh_drive_absolute(source);
  if (!drive && !dsh_unc_absolute(source)) {
    free(wide);
    return DSH_EINVAL;
  }

  wchar_t *result = (wchar_t *)malloc((wcslen(source) + 2) * sizeof(wchar_t));
  if (!result) {
    free(wide);
    return DSH_ENOMEM;
  }
  size_t written = 0;
  if (drive) {
    wchar_t letter = source[0];
    if (letter >= L'a' && letter <= L'z') letter = (wchar_t)(letter - 32);
    result[written++] = letter;
    result[written++] = L':';
    source += 2; /* points at the separator after the drive */
  } else {
    size_t index = 2;
    while (source[index] && source[index] != L'\\') ++index;
    if (source[index] != L'\\') {
      free(result);
      free(wide);
      return DSH_EINVAL;
    }
    ++index;
    while (source[index] && source[index] != L'\\') ++index;
    memcpy(result, source, index * sizeof(wchar_t));
    written = index;
    source += index;
  }
  while (*source) {
    if (*source != L'\\') {
      free(result);
      free(wide);
      return DSH_EINVAL;
    }
    ++source;
    const wchar_t *component = source;
    while (*source && *source != L'\\') ++source;
    size_t component_length = (size_t)(source - component);
    if (component_length == 0) {
      free(result);
      free(wide);
      return DSH_EINVAL;
    }
    if (component_length == 1 && component[0] == L'.') continue;
    if (component_length == 2 && component[0] == L'.' &&
        component[1] == L'.') {
      free(result);
      free(wide);
      return DSH_EINVAL;
    }
    if (written > 0 && result[written - 1] != L'\\') result[written++] = L'\\';
    memcpy(result + written, component, component_length * sizeof(wchar_t));
    written += component_length;
  }
  if (drive && written == 2) result[written++] = L'\\';
  result[written] = L'\0';
  free(wide);
  *out = result;
  return 0;
}

static wchar_t *dsh_api_path(const wchar_t *normalized) {
  size_t length = wcslen(normalized);
  wchar_t *result;
  if (normalized[0] == L'\\' && normalized[1] == L'\\') {
    result = (wchar_t *)malloc((length + 8) * sizeof(wchar_t));
    if (!result) return NULL;
    memcpy(result, L"\\\\?\\UNC\\", 8 * sizeof(wchar_t));
    wcscpy(result + 8, normalized + 2);
  } else {
    result = (wchar_t *)malloc((length + 5) * sizeof(wchar_t));
    if (!result) return NULL;
    memcpy(result, L"\\\\?\\", 4 * sizeof(wchar_t));
    wcscpy(result + 4, normalized);
  }
  return result;
}

static int dsh_reserved_name(const wchar_t *name, size_t length) {
  static const wchar_t *reserved[] = {
      L"CON", L"PRN", L"AUX", L"NUL", L"COM1", L"COM2", L"COM3", L"COM4",
      L"COM5", L"COM6", L"COM7", L"COM8", L"COM9", L"LPT1", L"LPT2", L"LPT3",
      L"LPT4", L"LPT5", L"LPT6", L"LPT7", L"LPT8", L"LPT9"};
  size_t base = 0;
  while (base < length && name[base] != L'.') ++base;
  if (base == 0 || base > 4) return 0;
  for (size_t i = 0; i < sizeof(reserved) / sizeof(reserved[0]); ++i) {
    if (wcslen(reserved[i]) != base) continue;
    size_t j = 0;
    for (; j < base; ++j) {
      wchar_t value = name[j];
      if (value >= L'a' && value <= L'z') value = (wchar_t)(value - 32);
      if (value != reserved[i][j]) break;
    }
    if (j == base) return 1;
  }
  return 0;
}

/* Validate a workspace-relative path: no empty / "." / ".." component, no
 * ADS colon, no reserved character, no trailing space or dot, no DOS device
 * name. `relative` must use backslashes. */
static int dsh_validate_relative(const wchar_t *relative) {
  if (!relative) return DSH_EINVAL;
  size_t length = wcslen(relative);
  if (length == 0) return DSH_EINVAL;
  if (length >= DSH_MAX_WIDE_PATH) return DSH_ENAMETOOLONG;
  if (dsh_is_separator(relative[0]) || dsh_is_separator(relative[length - 1])) {
    return DSH_EINVAL;
  }
  const wchar_t *cursor = relative;
  while (*cursor) {
    const wchar_t *component = cursor;
    while (*cursor && !dsh_is_separator(*cursor)) ++cursor;
    size_t component_length = (size_t)(cursor - component);
    if (component_length == 0) return DSH_EINVAL;
    if (component_length == 1 && component[0] == L'.') return DSH_EINVAL;
    if (component_length == 2 && component[0] == L'.' &&
        component[1] == L'.') return DSH_EINVAL;
    if (component_length > 255) return DSH_ENAMETOOLONG;
    if (component[component_length - 1] == L' ' ||
        component[component_length - 1] == L'.') {
      return DSH_EINVAL;
    }
    for (size_t i = 0; i < component_length; ++i) {
      wchar_t value = component[i];
      if (value < 0x20) return DSH_EINVAL;
      if (value == L':' || value == L'*' || value == L'?' || value == L'"' ||
          value == L'<' || value == L'>' || value == L'|') {
        return DSH_EINVAL;
      }
    }
    if (dsh_reserved_name(component, component_length)) return DSH_EINVAL;
    if (*cursor) ++cursor;
  }
  return 0;
}

static wchar_t *dsh_join(const wchar_t *root, const wchar_t *relative) {
  size_t root_length = wcslen(root);
  size_t relative_length = relative ? wcslen(relative) : 0;
  int needs_separator = relative_length > 0 && root[root_length - 1] != L'\\';
  wchar_t *result = (wchar_t *)malloc(
      (root_length + relative_length + (needs_separator ? 2 : 1)) *
      sizeof(wchar_t));
  if (!result) return NULL;
  memcpy(result, root, root_length * sizeof(wchar_t));
  size_t offset = root_length;
  if (needs_separator) result[offset++] = L'\\';
  if (relative_length) {
    memcpy(result + offset, relative, relative_length * sizeof(wchar_t));
    offset += relative_length;
  }
  result[offset] = L'\0';
  return result;
}

static void dsh_filetime_to_unix(const FILETIME *value, int64_t *seconds,
                                 int64_t *nanoseconds) {
  ULARGE_INTEGER ticks;
  ticks.LowPart = value->dwLowDateTime;
  ticks.HighPart = value->dwHighDateTime;
  uint64_t hundred_ns = ticks.QuadPart;
  if (hundred_ns == 0) {
    *seconds = 0;
    *nanoseconds = 0;
    return;
  }
  *seconds = (int64_t)(hundred_ns / 10000000ULL) - 11644473600LL;
  *nanoseconds = (int64_t)((hundred_ns % 10000000ULL) * 100ULL);
}

/* ------------------------------------------------------------------ */
/* Opening helpers                                                     */
/* ------------------------------------------------------------------ */

static int dsh_handle_not_reparse(HANDLE handle, FILE_ATTRIBUTE_TAG_INFO *info) {
  if (!GetFileInformationByHandleEx(handle, FileAttributeTagInfo, info,
                                    sizeof(*info))) {
    return dsh_map_win_error(GetLastError());
  }
  if (info->FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) return DSH_EACCES;
  return 0;
}

static int dsh_open_directory_abs(const wchar_t *normalized, HANDLE *out) {
  wchar_t *api = dsh_api_path(normalized);
  if (!api) return DSH_ENOMEM;
  HANDLE handle = CreateFileW(
      api,
      FILE_LIST_DIRECTORY | FILE_READ_ATTRIBUTES | READ_CONTROL | SYNCHRONIZE,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
      OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
      NULL);
  DWORD error = GetLastError();
  free(api);
  if (handle == INVALID_HANDLE_VALUE) return dsh_map_win_error(error);
  FILE_ATTRIBUTE_TAG_INFO info;
  int status = dsh_handle_not_reparse(handle, &info);
  if (status == 0 && !(info.FileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
    status = DSH_ENOTDIR;
  }
  if (status != 0) {
    CloseHandle(handle);
    return status;
  }
  *out = handle;
  return 0;
}

static int dsh_open_regular_abs(const wchar_t *normalized, DWORD access,
                                HANDLE *out) {
  wchar_t *api = dsh_api_path(normalized);
  if (!api) return DSH_ENOMEM;
  HANDLE handle = CreateFileW(api, access,
                              FILE_SHARE_READ | FILE_SHARE_WRITE |
                                  FILE_SHARE_DELETE,
                              NULL, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT,
                              NULL);
  DWORD error = GetLastError();
  free(api);
  if (handle == INVALID_HANDLE_VALUE) return dsh_map_win_error(error);
  FILE_ATTRIBUTE_TAG_INFO info;
  int status = dsh_handle_not_reparse(handle, &info);
  if (status == 0 && (info.FileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
    status = DSH_EINVAL;
  }
  if (status != 0) {
    CloseHandle(handle);
    return status;
  }
  *out = handle;
  return 0;
}

/* Walk every component below `root` with OPEN_REPARSE_POINT so a junction or
 * symlink cannot redirect the final open. `relative` must be validated and
 * use backslashes. */
static int dsh_open_checked(const wchar_t *root, const wchar_t *relative,
                            int want_directory, HANDLE *out) {
  if (!relative || relative[0] == L'\0') {
    return dsh_open_directory_abs(root, out);
  }
  size_t root_length = wcslen(root);
  size_t relative_length = wcslen(relative);
  wchar_t *prefix = (wchar_t *)malloc(
      (root_length + relative_length + 2) * sizeof(wchar_t));
  if (!prefix) return DSH_ENOMEM;
  memcpy(prefix, root, root_length * sizeof(wchar_t));
  size_t offset = root_length;
  if (prefix[offset - 1] != L'\\') prefix[offset++] = L'\\';

  int status = 0;
  size_t component_start = 0;
  for (size_t i = 0; i <= relative_length; ++i) {
    if (relative[i] != L'\\' && relative[i] != L'\0') continue;
    size_t component_length = i - component_start;
    if (component_length == 0) {
      status = DSH_EINVAL;
      break;
    }
    memcpy(prefix + offset, relative + component_start,
           component_length * sizeof(wchar_t));
    size_t full_length = offset + component_length;
    prefix[full_length] = L'\0';
    if (relative[i] == L'\0') {
      if (want_directory) {
        status = dsh_open_directory_abs(prefix, out);
      } else {
        status = dsh_open_regular_abs(prefix, GENERIC_READ, out);
      }
      break;
    }
    HANDLE directory = INVALID_HANDLE_VALUE;
    status = dsh_open_directory_abs(prefix, &directory);
    if (status != 0) break;
    CloseHandle(directory);
    component_start = i + 1;
    offset = full_length + 1;
    prefix[full_length] = L'\\';
  }
  free(prefix);
  return status;
}

/* ------------------------------------------------------------------ */
/* Identity, SID and stat                                              */
/* ------------------------------------------------------------------ */

static int dsh_identity(HANDLE handle, int64_t *device, int64_t *index) {
  BY_HANDLE_FILE_INFORMATION info;
  if (!GetFileInformationByHandle(handle, &info)) {
    return dsh_map_win_error(GetLastError());
  }
  *device = (int64_t)info.dwVolumeSerialNumber;
  *index = ((int64_t)(uint32_t)info.nFileIndexHigh << 32) |
           (int64_t)(uint32_t)info.nFileIndexLow;
  return 0;
}

static SRWLOCK dsh_sid_lock = SRWLOCK_INIT;
static BYTE dsh_sid_buffer[SECURITY_MAX_SID_SIZE];
static int dsh_sid_state = 0; /* 0 = unknown, 1 = ready, -1 = failed */

static int dsh_current_sid(PSID *out) {
  int status = 0;
  AcquireSRWLockExclusive(&dsh_sid_lock);
  if (dsh_sid_state == 0) {
    HANDLE token = NULL;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
      dsh_sid_state = -1;
      status = dsh_map_win_error(GetLastError());
    } else {
      DWORD needed = 0;
      GetTokenInformation(token, TokenUser, NULL, 0, &needed);
      if (needed == 0 || needed > 4096) {
        dsh_sid_state = -1;
        status = DSH_EIO;
      } else {
        BYTE *buffer = (BYTE *)malloc(needed);
        if (!buffer) {
          dsh_sid_state = -1;
          status = DSH_ENOMEM;
        } else if (!GetTokenInformation(token, TokenUser, buffer, needed,
                                        &needed)) {
          dsh_sid_state = -1;
          status = dsh_map_win_error(GetLastError());
        } else {
          PSID sid = ((TOKEN_USER *)buffer)->User.Sid;
          DWORD length = GetLengthSid(sid);
          if (length == 0 || length > SECURITY_MAX_SID_SIZE) {
            dsh_sid_state = -1;
            status = DSH_EIO;
          } else {
            memcpy(dsh_sid_buffer, sid, length);
            dsh_sid_state = 1;
          }
        }
        free(buffer);
      }
      CloseHandle(token);
    }
  } else if (dsh_sid_state < 0) {
    status = DSH_EIO;
  }
  if (status == 0) *out = (PSID)dsh_sid_buffer;
  ReleaseSRWLockExclusive(&dsh_sid_lock);
  return status;
}

static int32_t dsh_sid_hash(PSID sid) {
  if (!sid) return 0;
  DWORD length = GetLengthSid(sid);
  const BYTE *bytes = (const BYTE *)sid;
  uint32_t hash = 2166136261u;
  for (DWORD i = 0; i < length; ++i) {
    hash ^= (uint32_t)bytes[i];
    hash *= 16777619u;
  }
  hash &= 0x7FFFFFFFu;
  return hash == 0 ? 1 : (int32_t)hash;
}

/* Build a security descriptor whose DACL grants GENERIC_ALL to the current
 * user only. Caller frees `sd` and `acl` with LocalFree. */
static int dsh_owner_only_security(int directory, SECURITY_ATTRIBUTES *attributes,
                                   PSECURITY_DESCRIPTOR *sd, PACL *acl) {
  PSID owner = NULL;
  int status = dsh_current_sid(&owner);
  if (status != 0) return status;
  EXPLICIT_ACCESS_W entry;
  memset(&entry, 0, sizeof(entry));
  entry.grfAccessPermissions = GENERIC_ALL;
  entry.grfAccessMode = SET_ACCESS;
  entry.grfInheritance =
      directory ? SUB_CONTAINERS_AND_OBJECTS_INHERIT : NO_INHERITANCE;
  entry.Trustee.TrusteeForm = TRUSTEE_IS_SID;
  entry.Trustee.TrusteeType = TRUSTEE_IS_USER;
  entry.Trustee.ptstrName = (LPWSTR)owner;
  PACL built = NULL;
  if (SetEntriesInAclW(1, &entry, NULL, &built) != ERROR_SUCCESS) {
    return DSH_EIO;
  }
  PSECURITY_DESCRIPTOR descriptor =
      (PSECURITY_DESCRIPTOR)LocalAlloc(LPTR, SECURITY_DESCRIPTOR_MIN_LENGTH);
  if (!descriptor) {
    LocalFree(built);
    return DSH_ENOMEM;
  }
  if (!InitializeSecurityDescriptor(descriptor, SECURITY_DESCRIPTOR_REVISION) ||
      !SetSecurityDescriptorDacl(descriptor, TRUE, built, FALSE)) {
    LocalFree(built);
    LocalFree(descriptor);
    return DSH_EIO;
  }
  attributes->nLength = sizeof(*attributes);
  attributes->lpSecurityDescriptor = descriptor;
  attributes->bInheritHandle = FALSE;
  *sd = descriptor;
  *acl = built;
  return 0;
}

static int dsh_dacl_owner_only(PACL dacl, PSID owner) {
  if (!dacl || !owner) return 0;
  ACL_SIZE_INFORMATION size;
  if (!GetAclInformation(dacl, &size, sizeof(size), AclSizeInformation)) return 0;
  int saw_owner = 0;
  for (DWORD i = 0; i < size.AceCount; ++i) {
    LPVOID raw = NULL;
    if (!GetAce(dacl, i, &raw)) return 0;
    ACE_HEADER *header = (ACE_HEADER *)raw;
    if (header->AceType != ACCESS_ALLOWED_ACE_TYPE) continue;
    ACCESS_ALLOWED_ACE *ace = (ACCESS_ALLOWED_ACE *)raw;
    PSID sid = (PSID)&ace->SidStart;
    if (EqualSid(sid, owner)) {
      saw_owner = 1;
    } else {
      return 0;
    }
  }
  return saw_owner;
}

static int dsh_stat_handle(HANDLE handle, int expect_directory, int64_t *out) {
  BY_HANDLE_FILE_INFORMATION info;
  if (!GetFileInformationByHandle(handle, &info)) {
    return dsh_map_win_error(GetLastError());
  }
  int is_directory = (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
  if (expect_directory && !is_directory) return DSH_ENOTDIR;
  if (!expect_directory && is_directory) return DSH_EINVAL;

  PSID owner = NULL;
  PACL dacl = NULL;
  PSECURITY_DESCRIPTOR descriptor = NULL;
  DWORD security = GetSecurityInfo(
      handle, SE_FILE_OBJECT,
      OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION, &owner, NULL, &dacl,
      NULL, &descriptor);
  if (security != ERROR_SUCCESS) return dsh_map_win_error(security);
  int32_t uid = dsh_sid_hash(owner == NULL ? (PSID)dsh_sid_buffer : owner);
  int owner_only = dsh_dacl_owner_only(dacl, owner);
  if (descriptor) LocalFree(descriptor);
  if (uid == 0) return DSH_EIO;

  int32_t permissions = owner_only ? 0700 : 0755;
  if (!is_directory && permissions == 0700) permissions = 0600;

  int64_t mtime_seconds = 0, mtime_nanos = 0;
  int64_t ctime_seconds = 0, ctime_nanos = 0;
  dsh_filetime_to_unix(&info.ftLastWriteTime, &mtime_seconds, &mtime_nanos);
  dsh_filetime_to_unix(&info.ftCreationTime, &ctime_seconds, &ctime_nanos);

  out[0] = (int64_t)info.dwVolumeSerialNumber;
  out[1] = ((int64_t)(uint32_t)info.nFileIndexHigh << 32) |
           (int64_t)(uint32_t)info.nFileIndexLow;
  out[2] = ((int64_t)(uint32_t)info.nFileSizeHigh << 32) |
           (int64_t)(uint32_t)info.nFileSizeLow;
  out[3] = mtime_seconds;
  out[4] = mtime_nanos;
  out[5] = ctime_seconds;
  out[6] = ctime_nanos;
  out[7] = (int64_t)((is_directory ? 0040000 : 0100000) | permissions);
  out[8] = (int64_t)uid;
  out[9] = (int64_t)uid;
  return 0;
}

/* ------------------------------------------------------------------ */
/* SafeRoot operations                                                 */
/* ------------------------------------------------------------------ */

int dsh_fs_open_root(const char *path) {
  wchar_t *normalized = NULL;
  int status = dsh_normalize_root(path, &normalized);
  if (status != 0) return -status;
  HANDLE handle = INVALID_HANDLE_VALUE;
  status = dsh_open_directory_abs(normalized, &handle);
  if (status != 0) {
    free(normalized);
    return -status;
  }
  int fd = 0;
  status = dsh_table_alloc(handle, normalized, &fd);
  free(normalized);
  if (status != 0) {
    CloseHandle(handle);
    return -status;
  }
  return fd;
}

int dsh_fs_root_matches(int root_fd, const char *path) {
  wchar_t *normalized = NULL;
  int status = dsh_normalize_root(path, &normalized);
  if (status != 0) return -status;
  HANDLE anchored = NULL;
  status = dsh_table_handle(root_fd, &anchored);
  if (status != 0) {
    free(normalized);
    return -status;
  }
  HANDLE named = INVALID_HANDLE_VALUE;
  status = dsh_open_directory_abs(normalized, &named);
  free(normalized);
  if (status != 0) return -status;
  int64_t anchored_device = 0, anchored_index = 0;
  int64_t named_device = 0, named_index = 0;
  int anchored_status = dsh_identity(anchored, &anchored_device, &anchored_index);
  int named_status = dsh_identity(named, &named_device, &named_index);
  CloseHandle(named);
  if (anchored_status != 0) return -anchored_status;
  if (named_status != 0) return -named_status;
  return anchored_device == named_device && anchored_index == named_index ? 1 : 0;
}

/* Compare the anchored walk with a fresh pathname walk. Returns 1 on a match,
 * 0 on a moved mapping, and a negative error code otherwise. */
int dsh_fs_mapping_matches(int root_fd, const char *root_path,
                           const char *relative_path, int is_directory) {
  if (!relative_path) return -DSH_EINVAL;
  int root_status = dsh_fs_root_matches(root_fd, root_path);
  if (root_status != 1) return root_status;

  wchar_t *relative = NULL;
  int status = dsh_utf8_to_wide(relative_path, &relative);
  if (status != 0) return -status;
  for (wchar_t *cursor = relative; *cursor; ++cursor) {
    if (dsh_is_separator(*cursor)) *cursor = L'\\';
  }
  if (wcslen(relative) == 0 || wcscmp(relative, L".") == 0) {
    relative[0] = L'\0';
  } else {
    status = dsh_validate_relative(relative);
    if (status != 0) {
      free(relative);
      return -status;
    }
  }
  if (!is_directory) {
    wchar_t *separator = wcsrchr(relative, L'\\');
    if (separator) {
      *separator = L'\0';
    } else {
      relative[0] = L'\0';
    }
  }

  wchar_t root_from_handle[DSH_MAX_WIDE_PATH];
  status = dsh_table_root_path(root_fd, root_from_handle, DSH_MAX_WIDE_PATH);
  if (status != 0) {
    free(relative);
    return -status;
  }
  wchar_t *root_named = NULL;
  status = dsh_normalize_root(root_path, &root_named);
  if (status != 0) {
    free(relative);
    return -status;
  }
  wchar_t *anchored_path = dsh_join(root_from_handle, relative);
  wchar_t *named_path = dsh_join(root_named, relative);
  free(relative);
  free(root_named);
  if (!anchored_path || !named_path) {
    free(anchored_path);
    free(named_path);
    return -DSH_ENOMEM;
  }
  HANDLE anchored = INVALID_HANDLE_VALUE;
  status = dsh_open_directory_abs(anchored_path, &anchored);
  free(anchored_path);
  if (status != 0) {
    free(named_path);
    return -status;
  }
  HANDLE named = INVALID_HANDLE_VALUE;
  status = dsh_open_directory_abs(named_path, &named);
  free(named_path);
  if (status != 0) {
    CloseHandle(anchored);
    return -status;
  }
  int64_t anchored_device = 0, anchored_index = 0;
  int64_t named_device = 0, named_index = 0;
  int anchored_status = dsh_identity(anchored, &anchored_device, &anchored_index);
  int named_status = dsh_identity(named, &named_device, &named_index);
  CloseHandle(anchored);
  CloseHandle(named);
  if (anchored_status != 0) return -anchored_status;
  if (named_status != 0) return -named_status;
  return anchored_device == named_device && anchored_index == named_index ? 1 : 0;
}

int dsh_fs_close(int fd) { return dsh_table_close(fd); }

int dsh_fs_set_root_mode(int fd, int mode) {
  if ((mode & 0777) != 0700) return DSH_ENOTSUP;
  /* The anchored handle is opened for listing; a DACL rewrite needs
   * WRITE_DAC, so reopen the stored root path with that access. */
  wchar_t root[DSH_MAX_WIDE_PATH];
  int status = dsh_table_root_path(fd, root, DSH_MAX_WIDE_PATH);
  if (status != 0) return status;
  wchar_t *api = dsh_api_path(root);
  if (!api) return DSH_ENOMEM;
  HANDLE handle = CreateFileW(
      api, READ_CONTROL | WRITE_DAC | FILE_READ_ATTRIBUTES | SYNCHRONIZE,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
      OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
      NULL);
  DWORD open_error = GetLastError();
  free(api);
  if (handle == INVALID_HANDLE_VALUE) return dsh_map_win_error(open_error);
  SECURITY_ATTRIBUTES attributes;
  PSECURITY_DESCRIPTOR descriptor = NULL;
  PACL acl = NULL;
  status = dsh_owner_only_security(1, &attributes, &descriptor, &acl);
  if (status != 0) {
    CloseHandle(handle);
    return status;
  }
  DWORD result = SetSecurityInfo(handle, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION,
                                 NULL, NULL, acl, NULL);
  LocalFree(acl);
  LocalFree(descriptor);
  if (result != ERROR_SUCCESS) {
    CloseHandle(handle);
    return dsh_map_win_error(result);
  }
  if (!FlushFileBuffers(handle)) {
    DWORD flush_error = GetLastError();
    if (flush_error != ERROR_INVALID_FUNCTION &&
        flush_error != ERROR_ACCESS_DENIED) {
      CloseHandle(handle);
      return dsh_map_win_error(flush_error);
    }
  }
  CloseHandle(handle);
  return 0;
}

int dsh_fs_open_file(int root_fd, const char *path) {
  if (!path || !*path) return -DSH_EINVAL;
  wchar_t *relative = NULL;
  int status = dsh_utf8_to_wide(path, &relative);
  if (status != 0) return -status;
  for (wchar_t *cursor = relative; *cursor; ++cursor) {
    if (dsh_is_separator(*cursor)) *cursor = L'\\';
  }
  status = dsh_validate_relative(relative);
  if (status != 0) {
    free(relative);
    return -status;
  }
  wchar_t root[DSH_MAX_WIDE_PATH];
  status = dsh_table_root_path(root_fd, root, DSH_MAX_WIDE_PATH);
  if (status == 0) {
    HANDLE handle = INVALID_HANDLE_VALUE;
    status = dsh_open_checked(root, relative, 0, &handle);
    if (status == 0) {
      int fd = 0;
      status = dsh_table_alloc(handle, NULL, &fd);
      if (status == 0) {
        free(relative);
        return fd;
      }
      CloseHandle(handle);
    }
  }
  free(relative);
  return -status;
}

int dsh_fs_stat_fd(int fd, int64_t *out) {
  HANDLE handle = NULL;
  int status = dsh_table_handle(fd, &handle);
  if (status != 0) return status;
  return dsh_stat_handle(handle, 0, out);
}

int dsh_fs_stat_root(int fd, int64_t *out) {
  HANDLE handle = NULL;
  int status = dsh_table_handle(fd, &handle);
  if (status != 0) return status;
  return dsh_stat_handle(handle, 1, out);
}

int dsh_fs_read_fd(int fd, uint8_t *buffer, int capacity) {
  if (capacity < 0 || !buffer) return -DSH_EINVAL;
  if (capacity == 0) return 0;
  HANDLE handle = NULL;
  int status = dsh_table_handle(fd, &handle);
  if (status != 0) return -status;
  LARGE_INTEGER origin;
  origin.QuadPart = 0;
  if (!SetFilePointerEx(handle, origin, NULL, FILE_BEGIN)) {
    return -dsh_map_win_error(GetLastError());
  }
  int offset = 0;
  while (offset < capacity) {
    DWORD chunk = (DWORD)(capacity - offset);
    if (chunk > (1u << 20)) chunk = 1u << 20;
    DWORD read = 0;
    if (!ReadFile(handle, buffer + offset, chunk, &read, NULL)) {
      DWORD error = GetLastError();
      if (error == ERROR_HANDLE_EOF) break;
      return -dsh_map_win_error(error);
    }
    offset += (int)read;
    if (read == 0) break;
  }
  return offset;
}

static int dsh_make_parents(const wchar_t *root, const wchar_t *relative) {
  size_t root_length = wcslen(root);
  size_t relative_length = wcslen(relative);
  wchar_t *prefix = (wchar_t *)malloc(
      (root_length + relative_length + 2) * sizeof(wchar_t));
  if (!prefix) return DSH_ENOMEM;
  memcpy(prefix, root, root_length * sizeof(wchar_t));
  size_t offset = root_length;
  if (prefix[offset - 1] != L'\\') prefix[offset++] = L'\\';
  int status = 0;
  size_t component_start = 0;
  for (size_t i = 0; i < relative_length; ++i) {
    if (relative[i] != L'\\') continue;
    size_t component_length = i - component_start;
    if (component_length == 0) {
      status = DSH_EINVAL;
      break;
    }
    memcpy(prefix + offset, relative + component_start,
           component_length * sizeof(wchar_t));
    size_t full_length = offset + component_length;
    prefix[full_length] = L'\0';
    wchar_t *api = dsh_api_path(prefix);
    if (!api) {
      status = DSH_ENOMEM;
      break;
    }
    if (!CreateDirectoryW(api, NULL)) {
      DWORD error = GetLastError();
      free(api);
      if (error != ERROR_ALREADY_EXISTS) {
        status = dsh_map_win_error(error);
        break;
      }
      HANDLE existing = INVALID_HANDLE_VALUE;
      status = dsh_open_directory_abs(prefix, &existing);
      if (status != 0) break;
      CloseHandle(existing);
    } else {
      free(api);
    }
    offset = full_length + 1;
    prefix[full_length] = L'\\';
    component_start = i + 1;
  }
  free(prefix);
  return status;
}

static int dsh_stat_path(const wchar_t *normalized, int directory, int64_t *out) {
  HANDLE handle = INVALID_HANDLE_VALUE;
  int status = directory
                   ? dsh_open_directory_abs(normalized, &handle)
                   : dsh_open_regular_abs(
                         normalized, FILE_READ_ATTRIBUTES | READ_CONTROL, &handle);
  if (status != 0) return status;
  status = dsh_stat_handle(handle, directory, out);
  CloseHandle(handle);
  return status;
}

static int dsh_same_version(const int64_t *actual, const int64_t *expected) {
  for (int i = 0; i < 10; ++i) {
    if (actual[i] != expected[i]) return 0;
  }
  return 1;
}

static int dsh_apply_owner_only(const wchar_t *target) {
  HANDLE handle = INVALID_HANDLE_VALUE;
  int status = dsh_open_regular_abs(
      target, READ_CONTROL | WRITE_DAC | FILE_READ_ATTRIBUTES, &handle);
  if (status != 0) return status;
  SECURITY_ATTRIBUTES attributes;
  PSECURITY_DESCRIPTOR descriptor = NULL;
  PACL acl = NULL;
  status = dsh_owner_only_security(0, &attributes, &descriptor, &acl);
  if (status == 0) {
    DWORD result = SetSecurityInfo(handle, SE_FILE_OBJECT,
                                   DACL_SECURITY_INFORMATION, NULL, NULL, acl,
                                   NULL);
    if (result != ERROR_SUCCESS) status = dsh_map_win_error(result);
  }
  if (acl) LocalFree(acl);
  if (descriptor) LocalFree(descriptor);
  CloseHandle(handle);
  return status;
}

int dsh_fs_atomic_write(int root_fd, const char *root_path, const char *path,
                        const uint8_t *data, int length, int requested_mode,
                        int create_parents, int has_expected, int force_mode,
                        const int64_t *expected) {
  if (length < 0 || !data || !path) return DSH_EINVAL;
  int status = dsh_fs_root_matches(root_fd, root_path);
  if (status != 1) return status < 0 ? -status : DSH_ESTALE;

  wchar_t *relative = NULL;
  status = dsh_utf8_to_wide(path, &relative);
  if (status != 0) return status;
  for (wchar_t *cursor = relative; *cursor; ++cursor) {
    if (dsh_is_separator(*cursor)) *cursor = L'\\';
  }
  status = dsh_validate_relative(relative);
  if (status != 0) {
    free(relative);
    return status;
  }
  wchar_t root[DSH_MAX_WIDE_PATH];
  status = dsh_table_root_path(root_fd, root, DSH_MAX_WIDE_PATH);
  if (status != 0) {
    free(relative);
    return status;
  }
  if (create_parents) {
    status = dsh_make_parents(root, relative);
    if (status != 0) {
      free(relative);
      return status;
    }
  }
  int mapping = dsh_fs_mapping_matches(root_fd, root_path, path, 0);
  if (mapping != 1) {
    free(relative);
    return mapping < 0 ? -mapping : DSH_ESTALE;
  }

  wchar_t *target = dsh_join(root, relative);
  if (!target) {
    free(relative);
    return DSH_ENOMEM;
  }
  int64_t before[10];
  int exists = 0;
  status = dsh_stat_path(target, 0, before);
  if (status == 0) {
    exists = 1;
  } else if (status == DSH_ENOENT) {
    status = 0;
  } else {
    free(target);
    free(relative);
    return status;
  }
  if (has_expected && (!exists || !dsh_same_version(before, expected))) {
    free(target);
    free(relative);
    return DSH_EAGAIN;
  }

  wchar_t *parent = _wcsdup(target);
  if (!parent) {
    free(target);
    free(relative);
    return DSH_ENOMEM;
  }
  wchar_t *separator = wcsrchr(parent, L'\\');
  if (separator && separator != parent + 2) {
    *separator = L'\0';
  } else if (separator) {
    parent[3] = L'\0';
  }

  int mode = exists && !force_mode ? (int)(before[7] & 0777)
                                   : (requested_mode & 0777);
  SECURITY_ATTRIBUTES attributes;
  PSECURITY_DESCRIPTOR descriptor = NULL;
  PACL acl = NULL;
  SECURITY_ATTRIBUTES *attributes_pointer = NULL;
  if (mode == 0600) {
    status = dsh_owner_only_security(0, &attributes, &descriptor, &acl);
    if (status != 0) {
      free(parent);
      free(target);
      free(relative);
      return status;
    }
    attributes_pointer = &attributes;
  }

  static volatile LONG dsh_temporary_serial = 0;
  HANDLE temporary_handle = INVALID_HANDLE_VALUE;
  wchar_t *temporary = NULL;
  for (int attempt = 0; attempt < 32; ++attempt) {
    wchar_t name[64];
    LONG serial = InterlockedIncrement(&dsh_temporary_serial);
    int written = _snwprintf(name, 64, L".dsh-%lu-%ld.tmp",
                             (unsigned long)GetCurrentProcessId(), (long)serial);
    if (written <= 0 || written >= 64) {
      status = DSH_ENAMETOOLONG;
      break;
    }
    temporary = dsh_join(parent, name);
    if (!temporary) {
      status = DSH_ENOMEM;
      break;
    }
    wchar_t *api = dsh_api_path(temporary);
    if (!api) {
      status = DSH_ENOMEM;
      break;
    }
    temporary_handle = CreateFileW(
        api, GENERIC_WRITE | FILE_READ_ATTRIBUTES | READ_CONTROL | SYNCHRONIZE,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        attributes_pointer, CREATE_NEW,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    DWORD error = GetLastError();
    free(api);
    if (temporary_handle != INVALID_HANDLE_VALUE) break;
    status = dsh_map_win_error(error);
    if (error != ERROR_ALREADY_EXISTS) break;
    free(temporary);
    temporary = NULL;
  }
  if (acl) LocalFree(acl);
  if (descriptor) LocalFree(descriptor);
  if (temporary_handle == INVALID_HANDLE_VALUE) {
    free(temporary);
    free(parent);
    free(target);
    free(relative);
    return status;
  }

  status = 0;
  int offset_bytes = 0;
  while (offset_bytes < length) {
    DWORD chunk = (DWORD)(length - offset_bytes);
    if (chunk > (1u << 20)) chunk = 1u << 20;
    DWORD written = 0;
    if (!WriteFile(temporary_handle, data + offset_bytes, chunk, &written, NULL)) {
      status = dsh_map_win_error(GetLastError());
      break;
    }
    offset_bytes += (int)written;
  }
  if (status == 0 && !FlushFileBuffers(temporary_handle)) {
    status = dsh_map_win_error(GetLastError());
  }
  int64_t temporary_device = 0, temporary_index = 0;
  if (status == 0 &&
      dsh_identity(temporary_handle, &temporary_device, &temporary_index) != 0) {
    status = DSH_EIO;
  }
  CloseHandle(temporary_handle);
  if (status == 0) {
    mapping = dsh_fs_mapping_matches(root_fd, root_path, path, 0);
    if (mapping != 1) status = mapping < 0 ? -mapping : DSH_ESTALE;
  }
  if (status == 0 && has_expected) {
    int64_t current[10];
    if (dsh_stat_path(target, 0, current) != 0 ||
        !dsh_same_version(current, expected)) {
      status = DSH_EAGAIN;
    }
  } else if (status == 0) {
    int64_t current[10];
    int current_status = dsh_stat_path(target, 0, current);
    if (current_status != 0 && current_status != DSH_ENOENT) status = current_status;
  }
  if (status == 0) {
    wchar_t *target_api = dsh_api_path(target);
    wchar_t *temporary_api = dsh_api_path(temporary);
    if (!target_api || !temporary_api) {
      status = DSH_ENOMEM;
    } else if (exists) {
      if (!ReplaceFileW(target_api, temporary_api, NULL, REPLACEFILE_WRITE_THROUGH,
                        NULL, NULL)) {
        status = dsh_map_win_error(GetLastError());
      }
    } else if (!MoveFileExW(temporary_api, target_api, MOVEFILE_WRITE_THROUGH)) {
      status = dsh_map_win_error(GetLastError());
    }
    free(target_api);
    free(temporary_api);
  }
  if (status == 0) {
    int64_t committed[10];
    if (dsh_stat_path(target, 0, committed) != 0 ||
        committed[0] != temporary_device || committed[1] != temporary_index) {
      status = DSH_ESTALE;
    }
  }
  if (status == 0 && mode == 0600) {
    status = dsh_apply_owner_only(target);
  }
  if (status == 0) {
    mapping = dsh_fs_mapping_matches(root_fd, root_path, path, 0);
    if (mapping != 1) status = mapping < 0 ? -mapping : DSH_ESTALE;
  }
  if (status != 0) {
    /* Remove a commit that failed verification so no partial or weakly
     * protected file is left behind. */
    int64_t committed[10];
    if (dsh_stat_path(target, 0, committed) == 0 &&
        committed[0] == temporary_device && committed[1] == temporary_index) {
      wchar_t *api = dsh_api_path(target);
      if (api) {
        DeleteFileW(api);
        free(api);
      }
    }
    if (temporary) {
      wchar_t *api = dsh_api_path(temporary);
      if (api) {
        DeleteFileW(api);
        free(api);
      }
    }
  }
  free(temporary);
  free(parent);
  free(target);
  free(relative);
  return status;
}

int dsh_fs_create_exclusive(int root_fd, const char *path, const uint8_t *data,
                            int length, int requested_mode) {
  if (length < 0 || !data || !path) return DSH_EINVAL;
  wchar_t *relative = NULL;
  int status = dsh_utf8_to_wide(path, &relative);
  if (status != 0) return status;
  for (wchar_t *cursor = relative; *cursor; ++cursor) {
    if (dsh_is_separator(*cursor)) *cursor = L'\\';
  }
  status = dsh_validate_relative(relative);
  if (status != 0) {
    free(relative);
    return status;
  }
  wchar_t root[DSH_MAX_WIDE_PATH];
  status = dsh_table_root_path(root_fd, root, DSH_MAX_WIDE_PATH);
  if (status != 0) {
    free(relative);
    return status;
  }
  wchar_t *target = dsh_join(root, relative);
  if (!target) {
    free(relative);
    return DSH_ENOMEM;
  }
  SECURITY_ATTRIBUTES attributes;
  PSECURITY_DESCRIPTOR descriptor = NULL;
  PACL acl = NULL;
  SECURITY_ATTRIBUTES *attributes_pointer = NULL;
  if ((requested_mode & 0777) == 0600) {
    status = dsh_owner_only_security(0, &attributes, &descriptor, &acl);
    if (status != 0) {
      free(target);
      free(relative);
      return status;
    }
    attributes_pointer = &attributes;
  }
  wchar_t *api = dsh_api_path(target);
  if (!api) {
    status = DSH_ENOMEM;
  } else {
    HANDLE handle = CreateFileW(
        api, GENERIC_WRITE | FILE_READ_ATTRIBUTES | READ_CONTROL | SYNCHRONIZE,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        attributes_pointer, CREATE_NEW,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    DWORD error = GetLastError();
    free(api);
    if (handle == INVALID_HANDLE_VALUE) {
      status = dsh_map_win_error(error);
    } else {
      status = 0;
      int offset = 0;
      while (offset < length) {
        DWORD chunk = (DWORD)(length - offset);
        if (chunk > (1u << 20)) chunk = 1u << 20;
        DWORD written = 0;
        if (!WriteFile(handle, data + offset, chunk, &written, NULL)) {
          status = dsh_map_win_error(GetLastError());
          break;
        }
        offset += (int)written;
      }
      if (status == 0 && !FlushFileBuffers(handle)) {
        status = dsh_map_win_error(GetLastError());
      }
      CloseHandle(handle);
      if (status != 0) {
        wchar_t *remove_api = dsh_api_path(target);
        if (remove_api) {
          DeleteFileW(remove_api);
          free(remove_api);
        }
      }
    }
  }
  if (acl) LocalFree(acl);
  if (descriptor) LocalFree(descriptor);
  free(target);
  free(relative);
  return status;
}

int dsh_fs_unlink(int root_fd, const char *path) {
  if (!path || !*path) return DSH_EINVAL;
  wchar_t *relative = NULL;
  int status = dsh_utf8_to_wide(path, &relative);
  if (status != 0) return status;
  for (wchar_t *cursor = relative; *cursor; ++cursor) {
    if (dsh_is_separator(*cursor)) *cursor = L'\\';
  }
  status = dsh_validate_relative(relative);
  if (status != 0) {
    free(relative);
    return status;
  }
  wchar_t root[DSH_MAX_WIDE_PATH];
  status = dsh_table_root_path(root_fd, root, DSH_MAX_WIDE_PATH);
  if (status != 0) {
    free(relative);
    return status;
  }
  wchar_t *target = dsh_join(root, relative);
  if (!target) {
    free(relative);
    return DSH_ENOMEM;
  }
  HANDLE handle = INVALID_HANDLE_VALUE;
  status = dsh_open_regular_abs(target, DELETE | FILE_READ_ATTRIBUTES | SYNCHRONIZE,
                                &handle);
  if (status == 0) {
    FILE_DISPOSITION_INFO_EX disposition;
    memset(&disposition, 0, sizeof(disposition));
    disposition.Flags =
        FILE_DISPOSITION_FLAG_DELETE | FILE_DISPOSITION_FLAG_POSIX_SEMANTICS;
    if (!SetFileInformationByHandle(handle, FileDispositionInfoEx, &disposition,
                                    sizeof(disposition))) {
      DWORD error = GetLastError();
      if (error == ERROR_INVALID_PARAMETER || error == ERROR_NOT_SUPPORTED) {
        wchar_t *api = dsh_api_path(target);
        if (api) {
          status = DeleteFileW(api) ? 0 : dsh_map_win_error(GetLastError());
          free(api);
        } else {
          status = DSH_ENOMEM;
        }
      } else {
        status = dsh_map_win_error(error);
      }
    }
    CloseHandle(handle);
  }
  free(target);
  free(relative);
  return status;
}

static int dsh_append_list_entry(uint8_t *buffer, int capacity, size_t *used,
                                 const wchar_t *name, char kind) {
  char utf8[1024];
  int written = dsh_wide_to_utf8(name, (int)wcslen(name), utf8,
                                 (int)sizeof(utf8));
  if (written < 0) return -written;
  size_t needed = (size_t)written + 2;
  if (*used + needed > (size_t)capacity) return DSH_ENOBUFS;
  memcpy(buffer + *used, utf8, (size_t)written);
  *used += (size_t)written;
  buffer[(*used)++] = 0;
  buffer[(*used)++] = (uint8_t)kind;
  return 0;
}

int dsh_fs_list_dir(int root_fd, const char *path, uint8_t *buffer,
                    int capacity) {
  if (capacity < 0 || !buffer) return -DSH_EINVAL;
  wchar_t *relative = NULL;
  int status = dsh_utf8_to_wide(path ? path : ".", &relative);
  if (status != 0) return -status;
  for (wchar_t *cursor = relative; *cursor; ++cursor) {
    if (dsh_is_separator(*cursor)) *cursor = L'\\';
  }
  if (wcslen(relative) == 0) wcscpy(relative, L".");
  if (wcscmp(relative, L".") != 0) {
    status = dsh_validate_relative(relative);
    if (status != 0) {
      free(relative);
      return -status;
    }
  }
  wchar_t root[DSH_MAX_WIDE_PATH];
  status = dsh_table_root_path(root_fd, root, DSH_MAX_WIDE_PATH);
  if (status != 0) {
    free(relative);
    return -status;
  }
  HANDLE directory = INVALID_HANDLE_VALUE;
  if (wcscmp(relative, L".") == 0) {
    status = dsh_open_directory_abs(root, &directory);
  } else {
    status = dsh_open_checked(root, relative, 1, &directory);
  }
  if (status != 0) {
    free(relative);
    return -status;
  }
  CloseHandle(directory);
  wchar_t *query = dsh_join(root, wcscmp(relative, L".") == 0 ? L"" : relative);
  free(relative);
  if (!query) return -DSH_ENOMEM;
  size_t query_length = wcslen(query);
  wchar_t *pattern = (wchar_t *)malloc((query_length + 3) * sizeof(wchar_t));
  if (!pattern) {
    free(query);
    return -DSH_ENOMEM;
  }
  memcpy(pattern, query, query_length * sizeof(wchar_t));
  size_t offset = query_length;
  if (pattern[offset - 1] != L'\\') pattern[offset++] = L'\\';
  pattern[offset++] = L'*';
  pattern[offset] = L'\0';
  free(query);
  wchar_t *api = dsh_api_path(pattern);
  free(pattern);
  if (!api) return -DSH_ENOMEM;

  WIN32_FIND_DATAW data;
  HANDLE find = FindFirstFileW(api, &data);
  DWORD error = GetLastError();
  free(api);
  if (find == INVALID_HANDLE_VALUE) {
    return -(error == ERROR_FILE_NOT_FOUND ? DSH_ENOENT
                                           : dsh_map_win_error(error));
  }
  size_t used = 0;
  int result = 0;
  do {
    if (wcscmp(data.cFileName, L".") == 0 ||
        wcscmp(data.cFileName, L"..") == 0) {
      continue;
    }
    if (data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) continue;
    char kind = 0;
    if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
      kind = 'D';
    } else if (!(data.dwFileAttributes & FILE_ATTRIBUTE_DEVICE)) {
      kind = 'F';
    } else {
      continue;
    }
    int append =
        dsh_append_list_entry(buffer, capacity, &used, data.cFileName, kind);
    if (append != 0) {
      result = -append;
      break;
    }
  } while (FindNextFileW(find, &data));
  if (result == 0) {
    DWORD next_error = GetLastError();
    if (next_error != ERROR_NO_MORE_FILES) {
      result = -dsh_map_win_error(next_error);
    }
  }
  FindClose(find);
  return result == 0 ? (int)used : result;
}

int dsh_fs_sync_directory(const char *path) {
  wchar_t *normalized = NULL;
  int status = dsh_normalize_root(path, &normalized);
  if (status != 0) return status;
  HANDLE handle = INVALID_HANDLE_VALUE;
  status = dsh_open_directory_abs(normalized, &handle);
  free(normalized);
  if (status != 0) return status;
  int result = 0;
  if (!FlushFileBuffers(handle)) {
    DWORD error = GetLastError();
    /* Directory flush is best effort on NTFS; some file systems reject it. */
    if (error != ERROR_INVALID_FUNCTION && error != ERROR_ACCESS_DENIED &&
        error != ERROR_NOT_SUPPORTED) {
      result = dsh_map_win_error(error);
    }
  }
  CloseHandle(handle);
  return result;
}

/* ------------------------------------------------------------------ */
/* OS services                                                         */
/* ------------------------------------------------------------------ */

int dsh_os_uid(void) {
  PSID owner = NULL;
  if (dsh_current_sid(&owner) != 0) return 0;
  return dsh_sid_hash(owner);
}

int dsh_os_pid(void) { return (int)GetCurrentProcessId(); }

int dsh_os_flush_stdout(void) { return fflush(stdout) == 0 ? 0 : DSH_EIO; }

int dsh_os_flush_stderr(void) { return fflush(stderr) == 0 ? 0 : DSH_EIO; }

int dsh_os_stdin_is_terminal(void) {
  return _isatty(_fileno(stdin)) ? 1 : 0;
}

int dsh_os_executable_path(uint8_t *buffer, int capacity) {
  if (!buffer || capacity < 2) return -DSH_EINVAL;
  DWORD size = 512;
  wchar_t *path = NULL;
  for (;;) {
    path = (wchar_t *)malloc((size_t)size * sizeof(wchar_t));
    if (!path) return -DSH_ENOMEM;
    DWORD copied = GetModuleFileNameW(NULL, path, size);
    if (copied == 0) {
      DWORD error = GetLastError();
      free(path);
      return -dsh_map_win_error(error);
    }
    if (copied < size - 1) break;
    free(path);
    path = NULL;
    if (size >= 32767) return -DSH_ENAMETOOLONG;
    size *= 2;
  }
  char utf8[DSH_MAX_WIDE_PATH * 3];
  int written = dsh_wide_to_utf8(path, (int)wcslen(path), utf8,
                                 (int)sizeof(utf8));
  free(path);
  if (written < 0) return -written;
  if (written + 1 > capacity) return -DSH_ENAMETOOLONG;
  memcpy(buffer, utf8, (size_t)written + 1);
  return written;
}

int dsh_os_hostname(uint8_t *buffer, int capacity) {
  if (!buffer || capacity <= 1) return -DSH_EINVAL;
  wchar_t name[256];
  DWORD length = 256;
  if (!GetComputerNameExW(ComputerNameDnsHostname, name, &length)) {
    return -dsh_map_win_error(GetLastError());
  }
  char utf8[1024];
  int written = dsh_wide_to_utf8(name, (int)length, utf8, (int)sizeof(utf8));
  if (written < 0) return -written;
  if (written + 1 > capacity) return -DSH_ENOBUFS;
  memcpy(buffer, utf8, (size_t)written + 1);
  return written;
}

int dsh_os_timestamp(uint8_t *buffer, int capacity) {
  if (!buffer || capacity < 21) return -DSH_EINVAL;
  SYSTEMTIME value;
  GetSystemTime(&value);
  char text[32];
  int count = snprintf(text, sizeof(text), "%04d-%02d-%02dT%02d:%02d:%02dZ",
                       (int)value.wYear, (int)value.wMonth, (int)value.wDay,
                       (int)value.wHour, (int)value.wMinute, (int)value.wSecond);
  if (count < 0 || count >= capacity) return -DSH_ENOBUFS;
  memcpy(buffer, text, (size_t)count + 1);
  return count;
}

int dsh_os_process_alive(int pid) {
  if (pid <= 0) return 1;
  HANDLE handle = OpenProcess(
      SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)pid);
  if (!handle) {
    DWORD error = GetLastError();
    if (error == ERROR_ACCESS_DENIED) return 1;
    return error == ERROR_INVALID_PARAMETER ? 0 : 1;
  }
  DWORD code = 0;
  int alive = 0;
  if (GetExitCodeProcess(handle, &code)) alive = code == STILL_ACTIVE ? 1 : 0;
  CloseHandle(handle);
  return alive;
}

int dsh_os_process_group_alive(int pgid) {
  /* Windows has no POSIX process groups; shell workers are gated off, so the
   * leader check is the conservative approximation. */
  return dsh_os_process_alive(pgid);
}

int dsh_os_child_exit_state(int pid) {
  (void)pid;
  return -DSH_ENOTSUP;
}

int dsh_os_hard_worker_memory_supported(void) { return 0; }

int dsh_kill_process(int pid, int signal_number) {
  if (pid <= 0 || signal_number <= 0) return DSH_EINVAL;
  HANDLE handle = OpenProcess(
      PROCESS_TERMINATE | SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
      (DWORD)pid);
  if (!handle) return dsh_map_win_error(GetLastError());
  int status =
      TerminateProcess(handle, 1) ? 0 : dsh_map_win_error(GetLastError());
  CloseHandle(handle);
  return status;
}

int dsh_kill_process_group(int pid, int signal_number) {
  (void)pid;
  (void)signal_number;
  return DSH_ENOTSUP;
}

int dsh_exec_worker(const uint8_t *payload, int length) {
  (void)payload;
  (void)length;
  return DSH_ENOTSUP;
}

/* ------------------------------------------------------------------ */
/* Crypto                                                              */
/* ------------------------------------------------------------------ */

int dsh_crypto_sha256(const uint8_t *data, int length, uint8_t *output) {
  if (!data || length < 0 || !output) return 0;
  BCRYPT_ALG_HANDLE algorithm = NULL;
  BCRYPT_HASH_HANDLE hash = NULL;
  int valid = 0;
  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, NULL, 0) <
      0) {
    return 0;
  }
  if (BCryptCreateHash(algorithm, &hash, NULL, 0, NULL, 0, 0) < 0) {
    BCryptCloseAlgorithmProvider(algorithm, 0);
    return 0;
  }
  if (BCryptHashData(hash, (PUCHAR)data, (ULONG)length, 0) >= 0 &&
      BCryptFinishHash(hash, output, 32, 0) >= 0) {
    valid = 1;
  }
  BCryptDestroyHash(hash);
  BCryptCloseAlgorithmProvider(algorithm, 0);
  return valid;
}

int dsh_crypto_verify_rs256(const uint8_t *modulus, int modulus_len,
                            const uint8_t *exponent, int exponent_len,
                            const uint8_t *message, int message_len,
                            const uint8_t *signature, int signature_len) {
  if (!modulus || !exponent || !message || !signature || modulus_len <= 0 ||
      exponent_len <= 0 || message_len < 0 || signature_len <= 0) {
    return 0;
  }
  if (modulus_len > 8192 || exponent_len > 32 || signature_len > 8192) return 0;

  size_t blob_size = sizeof(BCRYPT_RSAKEY_BLOB) + (size_t)exponent_len +
                     (size_t)modulus_len;
  PUCHAR blob = (PUCHAR)malloc(blob_size);
  if (!blob) return 0;
  BCRYPT_RSAKEY_BLOB *header = (BCRYPT_RSAKEY_BLOB *)blob;
  header->Magic = BCRYPT_RSAPUBLIC_MAGIC;
  header->BitLength = (ULONG)modulus_len * 8;
  header->cbPublicExp = (ULONG)exponent_len;
  header->cbModulus = (ULONG)modulus_len;
  header->cbPrime1 = 0;
  header->cbPrime2 = 0;
  memcpy(blob + sizeof(BCRYPT_RSAKEY_BLOB), exponent, (size_t)exponent_len);
  memcpy(blob + sizeof(BCRYPT_RSAKEY_BLOB) + exponent_len, modulus,
         (size_t)modulus_len);

  BCRYPT_ALG_HANDLE algorithm = NULL;
  BCRYPT_KEY_HANDLE key = NULL;
  uint8_t digest[32];
  int valid = 0;
  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_RSA_ALGORITHM, NULL, 0) <
      0) {
    free(blob);
    return 0;
  }
  if (BCryptImportKeyPair(algorithm, NULL, BCRYPT_RSAPUBLIC_BLOB, &key, blob,
                          (ULONG)blob_size, 0) >= 0 &&
      dsh_crypto_sha256(message, message_len, digest) == 1) {
    BCRYPT_PKCS1_PADDING_INFO padding;
    memset(&padding, 0, sizeof(padding));
    padding.pszAlgId = BCRYPT_SHA256_ALGORITHM;
    if (BCryptVerifySignature(key, &padding, digest, sizeof(digest),
                              (PUCHAR)signature, (ULONG)signature_len,
                              BCRYPT_PAD_PKCS1) >= 0) {
      valid = 1;
    }
  }
  if (key) BCryptDestroyKey(key);
  BCryptCloseAlgorithmProvider(algorithm, 0);
  free(blob);
  return valid;
}
