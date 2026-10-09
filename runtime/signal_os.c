#define _DARWIN_C_SOURCE 1
#define _GNU_SOURCE 1

#include <errno.h>
#include <signal.h>
#include <string.h>

#if defined(__APPLE__) || defined(__linux__)
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
