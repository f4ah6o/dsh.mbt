#define _DARWIN_C_SOURCE 1
#define _GNU_SOURCE 1

#include <errno.h>
#include <string.h>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

/* Console control events replace POSIX signals. CTRL_C / CTRL_BREAK map to
 * SIGINT (2); close / logoff / shutdown map to SIGTERM (15). The handler only
 * records the request; the service loop performs the bounded shutdown. */
static volatile LONG dsh_shutdown_requested = 0;
static volatile LONG dsh_signal_handlers_installed = 0;

static BOOL WINAPI dsh_console_control_handler(DWORD control) {
  switch (control) {
    case CTRL_C_EVENT:
    case CTRL_BREAK_EVENT:
      InterlockedCompareExchange(&dsh_shutdown_requested, 2, 0);
      return TRUE;
    case CTRL_CLOSE_EVENT:
    case CTRL_LOGOFF_EVENT:
    case CTRL_SHUTDOWN_EVENT:
      InterlockedCompareExchange(&dsh_shutdown_requested, 15, 0);
      return TRUE;
    default:
      return FALSE;
  }
}

int dsh_service_signals_install(void) {
  if (InterlockedCompareExchange(&dsh_signal_handlers_installed, 1, 0) != 0) {
    return -EBUSY;
  }
  InterlockedExchange(&dsh_shutdown_requested, 0);
  if (!SetConsoleCtrlHandler(dsh_console_control_handler, TRUE)) {
    InterlockedExchange(&dsh_signal_handlers_installed, 0);
    return -EIO;
  }
  return 0;
}

int dsh_service_signals_requested(void) {
  return (int)InterlockedCompareExchange(&dsh_shutdown_requested, 0, 0);
}

int dsh_service_signals_restore(void) {
  if (InterlockedCompareExchange(&dsh_signal_handlers_installed, 0, 1) != 1) {
    return 0;
  }
  InterlockedExchange(&dsh_shutdown_requested, 0);
  if (!SetConsoleCtrlHandler(dsh_console_control_handler, FALSE)) return -EIO;
  return 0;
}
#elif defined(__APPLE__) || defined(__linux__)
#include <signal.h>

static volatile sig_atomic_t dsh_shutdown_requested = 0;
static struct sigaction dsh_previous_sigint;
static struct sigaction dsh_previous_sigterm;
static int dsh_signal_handlers_installed = 0;

static void dsh_service_signal_handler(int signal_number) {
  if (dsh_shutdown_requested == 0) {
    dsh_shutdown_requested = (sig_atomic_t)signal_number;
  }
}

int dsh_service_signals_install(void) {
  if (dsh_signal_handlers_installed) return -EBUSY;

  struct sigaction action;
  memset(&action, 0, sizeof(action));
  sigemptyset(&action.sa_mask);
  action.sa_handler = dsh_service_signal_handler;
  action.sa_flags = 0;
  dsh_shutdown_requested = 0;

  if (sigaction(SIGINT, &action, &dsh_previous_sigint) < 0) return -errno;
  if (sigaction(SIGTERM, &action, &dsh_previous_sigterm) < 0) {
    int saved_errno = errno;
    (void)sigaction(SIGINT, &dsh_previous_sigint, NULL);
    return -saved_errno;
  }
  dsh_signal_handlers_installed = 1;
  return 0;
}

int dsh_service_signals_requested(void) {
  return (int)dsh_shutdown_requested;
}

int dsh_service_signals_restore(void) {
  if (!dsh_signal_handlers_installed) return 0;
  int result = 0;
  if (sigaction(SIGINT, &dsh_previous_sigint, NULL) < 0) result = -errno;
  if (sigaction(SIGTERM, &dsh_previous_sigterm, NULL) < 0 && result == 0) {
    result = -errno;
  }
  dsh_shutdown_requested = 0;
  dsh_signal_handlers_installed = 0;
  return result;
}
#else
int dsh_service_signals_install(void) { return -ENOTSUP; }
int dsh_service_signals_requested(void) { return 0; }
int dsh_service_signals_restore(void) { return 0; }
#endif

int dsh_service_address_in_use(int error) {
#if defined(_WIN32)
  return error == 10048; /* WSAEADDRINUSE */
#else
  return error == EADDRINUSE;
#endif
}
