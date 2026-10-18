/*
 * Windows replacements for the POSIX OAuth helpers in oauth_os.c:
 * CSPRNG bytes, browser launch, and the Unix clock.
 *
 * The moon.pkg native-stub list is shared by every platform, so the whole
 * translation unit is empty on POSIX builds.
 */

#if defined(_WIN32)

#define _WIN32_WINNT 0x0A00
#define WIN32_LEAN_AND_MEAN
#define _CRT_SECURE_NO_WARNINGS

#include <windows.h>
#include <bcrypt.h>
#include <shellapi.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#pragma comment(lib, "bcrypt.lib")
#pragma comment(lib, "shell32.lib")

enum { DSH_EINVAL = 22, DSH_EIO = 5 };

int dsh_auth_random(uint8_t *out, int length) {
  if (!out || length < 0 || length > 4096) return DSH_EINVAL;
  if (length == 0) return 0;
  NTSTATUS status = BCryptGenRandom(NULL, out, (ULONG)length,
                                    BCRYPT_USE_SYSTEM_PREFERRED_RNG);
  return status >= 0 ? 0 : DSH_EIO;
}

int dsh_auth_open_url(const char *url) {
  if (!url) return DSH_EINVAL;
  size_t length = strlen(url);
  if (length == 0 || length > 8192) return DSH_EINVAL;
  if (strncmp(url, "https://", 8) != 0 && strncmp(url, "http://", 7) != 0) {
    return DSH_EINVAL;
  }
  int needed = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, url, -1, NULL, 0);
  if (needed <= 0) return DSH_EINVAL;
  wchar_t *wide = (wchar_t *)calloc((size_t)needed, sizeof(wchar_t));
  if (!wide) return DSH_EIO;
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, url, -1, wide, needed) <=
      0) {
    free(wide);
    return DSH_EINVAL;
  }
  HINSTANCE result = ShellExecuteW(NULL, L"open", wide, NULL, NULL, SW_SHOWNORMAL);
  free(wide);
  /* ShellExecuteW returns a value greater than 32 on success. */
  return (INT_PTR)result > 32 ? 0 : DSH_EIO;
}

int64_t dsh_auth_unix_time(void) {
  time_t now = time(NULL);
  if (now < 0) return -1;
  return (int64_t)now;
}

#endif /* _WIN32 */

#if !defined(_WIN32)
/* Keep the shared native-stub build non-empty on POSIX without pulling in
 * Windows headers. */
typedef int dsh_oauth_os_win32_translation_unit_is_empty;
#endif
