#include "dsh_moonbit_client.h"

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include "moonbit.h"
#include "moonbit_runtime.h"

extern void moonbit_init(void);
extern void moonbit_runtime_init(int, char **);
extern int32_t moonbit_utf16_len_from_utf8(
    moonbit_bytes_t, int32_t, int32_t);
extern int32_t moonbit_utf8_decode_into_utf16(
    moonbit_bytes_t, int32_t, int32_t, moonbit_string_t, int32_t);
extern int32_t moonbit_utf8_len_from_utf16(
    moonbit_string_t, int32_t, int32_t);
extern int32_t moonbit_utf8_encode_from_utf16(
    moonbit_string_t, int32_t, int32_t, moonbit_bytes_t, int32_t);

extern int32_t client_init(void);
extern int32_t client_dispose(int32_t);
extern moonbit_string_t client_state(int32_t);
extern moonbit_string_t client_begin_connect(int32_t);
extern moonbit_string_t client_connection_failed(int32_t);
extern moonbit_string_t client_connection_restored(int32_t);
extern moonbit_string_t client_accept_snapshot(int32_t, moonbit_string_t);
extern moonbit_string_t client_accept_session(int32_t, moonbit_string_t);
extern moonbit_string_t client_accept_event(
    int32_t, moonbit_string_t, moonbit_string_t);
extern moonbit_string_t client_set_draft(int32_t, moonbit_string_t);
extern moonbit_string_t client_set_selection(int32_t, moonbit_string_t);
extern moonbit_string_t client_set_scroll_anchor(int32_t, moonbit_string_t);
extern moonbit_string_t client_set_follow_latest(int32_t, moonbit_string_t);
extern moonbit_string_t client_set_text_view(int32_t, moonbit_string_t);
extern moonbit_string_t client_persisted_state(int32_t);
extern moonbit_string_t client_restore_preferences(int32_t, moonbit_string_t);
extern moonbit_string_t client_queue_command(
    int32_t, moonbit_string_t, moonbit_string_t, moonbit_string_t,
    moonbit_string_t, int32_t);
extern moonbit_string_t client_mark_command_sent(int32_t, moonbit_string_t);
extern moonbit_string_t client_mark_command_uncertain(int32_t, moonbit_string_t);
extern moonbit_string_t client_apply_receipt(int32_t, moonbit_string_t);
extern moonbit_string_t client_mark_receipt_missing(int32_t, moonbit_string_t);
extern moonbit_string_t client_pending_ids(int32_t);
extern moonbit_string_t client_new_command_id(moonbit_string_t, moonbit_string_t);

static pthread_once_t runtime_once = PTHREAD_ONCE_INIT;
static int32_t runtime_started = 0;

static void start_runtime_once(void) {
  moonbit_runtime_init(0, NULL);
  moonbit_init();
  runtime_started = 1;
}

int32_t dsh_moonbit_runtime_start(void) {
  if (pthread_once(&runtime_once, start_runtime_once) != 0) return -1;
  return runtime_started ? 0 : -1;
}

static moonbit_string_t string_from_utf8(const uint8_t *value, size_t length) {
  if (length > INT32_MAX || (length != 0 && value == NULL)) return NULL;

  moonbit_bytes_t input = moonbit_make_bytes_raw((int32_t)length);
  if (length != 0) memcpy(input, value, length);
  int32_t utf16_length = moonbit_utf16_len_from_utf8(input, 0, (int32_t)length);
  if (utf16_length < 0) {
    moonbit_decref(input);
    return NULL;
  }

  moonbit_string_t result = moonbit_make_string_raw(utf16_length);
  int32_t decoded = moonbit_utf8_decode_into_utf16(
      input, 0, (int32_t)length, result, 0);
  moonbit_decref(input);
  if (decoded != utf16_length) {
    moonbit_decref(result);
    return NULL;
  }
  return result;
}

static char *string_to_utf8(moonbit_string_t value) {
  if (value == NULL) return NULL;
  int32_t utf16_length = Moonbit_array_length(value);
  int32_t utf8_length = moonbit_utf8_len_from_utf16(value, 0, utf16_length);
  if (utf8_length < 0) {
    moonbit_decref(value);
    return NULL;
  }

  moonbit_bytes_t output = moonbit_make_bytes_raw(utf8_length);
  int32_t encoded = moonbit_utf8_encode_from_utf16(
      value, 0, utf16_length, output, 0);
  if (encoded != utf8_length) {
    moonbit_decref(output);
    moonbit_decref(value);
    return NULL;
  }

  char *result = (char *)malloc((size_t)utf8_length + 1);
  if (result != NULL) {
    if (utf8_length != 0) memcpy(result, output, (size_t)utf8_length);
    result[utf8_length] = '\0';
  }
  moonbit_decref(output);
  moonbit_decref(value);
  return result;
}

static char *return_string(moonbit_string_t value) {
  return string_to_utf8(value);
}

static void drop_input(moonbit_string_t value) {
  if (value != NULL) moonbit_decref(value);
}

static int32_t ready(void) {
  return runtime_started && dsh_moonbit_runtime_start() == 0;
}

DshMoonBitClientHandle dsh_moonbit_client_create(void) {
  if (!ready()) return -1;
  return client_init();
}

int32_t dsh_moonbit_client_dispose(DshMoonBitClientHandle handle) {
  if (!ready()) return 0;
  return client_dispose(handle);
}

char *dsh_moonbit_client_state_json(DshMoonBitClientHandle handle) {
  if (!ready()) return NULL;
  return return_string(client_state(handle));
}

char *dsh_moonbit_client_begin_connect(DshMoonBitClientHandle handle) {
  if (!ready()) return NULL;
  return return_string(client_begin_connect(handle));
}

char *dsh_moonbit_client_connection_failed(DshMoonBitClientHandle handle) {
  if (!ready()) return NULL;
  return return_string(client_connection_failed(handle));
}

char *dsh_moonbit_client_connection_restored(DshMoonBitClientHandle handle) {
  if (!ready()) return NULL;
  return return_string(client_connection_restored(handle));
}

char *dsh_moonbit_client_accept_snapshot(
    DshMoonBitClientHandle handle, const uint8_t *raw_utf8, size_t raw_length) {
  if (!ready()) return NULL;
  moonbit_string_t raw = string_from_utf8(raw_utf8, raw_length);
  if (raw == NULL) return NULL;
  moonbit_string_t result = client_accept_snapshot(handle, raw);
  drop_input(raw);
  return return_string(result);
}

char *dsh_moonbit_client_accept_session(
    DshMoonBitClientHandle handle, const uint8_t *raw_utf8, size_t raw_length) {
  if (!ready()) return NULL;
  moonbit_string_t raw = string_from_utf8(raw_utf8, raw_length);
  if (raw == NULL) return NULL;
  moonbit_string_t result = client_accept_session(handle, raw);
  drop_input(raw);
  return return_string(result);
}

char *dsh_moonbit_client_accept_event(
    DshMoonBitClientHandle handle, const uint8_t *raw_utf8, size_t raw_length,
    const uint8_t *event_id_utf8, size_t event_id_length) {
  if (!ready()) return NULL;
  moonbit_string_t raw = string_from_utf8(raw_utf8, raw_length);
  moonbit_string_t event_id = string_from_utf8(event_id_utf8, event_id_length);
  if (raw == NULL || event_id == NULL) {
    drop_input(raw);
    drop_input(event_id);
    return NULL;
  }
  moonbit_string_t result = client_accept_event(handle, raw, event_id);
  drop_input(raw);
  drop_input(event_id);
  return return_string(result);
}

char *dsh_moonbit_client_set_draft(
    DshMoonBitClientHandle handle, const uint8_t *value_utf8, size_t value_length) {
  if (!ready()) return NULL;
  moonbit_string_t value = string_from_utf8(value_utf8, value_length);
  if (value == NULL) return NULL;
  moonbit_string_t result = client_set_draft(handle, value);
  drop_input(value);
  return return_string(result);
}

char *dsh_moonbit_client_set_selection(
    DshMoonBitClientHandle handle, const uint8_t *value_utf8, size_t value_length) {
  if (!ready()) return NULL;
  moonbit_string_t value = string_from_utf8(value_utf8, value_length);
  if (value == NULL) return NULL;
  moonbit_string_t result = client_set_selection(handle, value);
  drop_input(value);
  return return_string(result);
}

char *dsh_moonbit_client_set_scroll_anchor(
    DshMoonBitClientHandle handle, const uint8_t *value_utf8, size_t value_length) {
  if (!ready()) return NULL;
  moonbit_string_t value = string_from_utf8(value_utf8, value_length);
  if (value == NULL) return NULL;
  moonbit_string_t result = client_set_scroll_anchor(handle, value);
  drop_input(value);
  return return_string(result);
}

char *dsh_moonbit_client_set_follow_latest(
    DshMoonBitClientHandle handle, int32_t enabled) {
  if (!ready()) return NULL;
  const char *value = enabled ? "true" : "false";
  moonbit_string_t argument = string_from_utf8((const uint8_t *)value, strlen(value));
  if (argument == NULL) return NULL;
  moonbit_string_t result = client_set_follow_latest(handle, argument);
  drop_input(argument);
  return return_string(result);
}

char *dsh_moonbit_client_set_text_view(
    DshMoonBitClientHandle handle, int32_t enabled) {
  if (!ready()) return NULL;
  const char *value = enabled ? "true" : "false";
  moonbit_string_t argument = string_from_utf8((const uint8_t *)value, strlen(value));
  if (argument == NULL) return NULL;
  moonbit_string_t result = client_set_text_view(handle, argument);
  drop_input(argument);
  return return_string(result);
}

char *dsh_moonbit_client_persisted_state_json(DshMoonBitClientHandle handle) {
  if (!ready()) return NULL;
  return return_string(client_persisted_state(handle));
}

char *dsh_moonbit_client_restore_preferences(
    DshMoonBitClientHandle handle, const uint8_t *raw_utf8, size_t raw_length) {
  if (!ready()) return NULL;
  moonbit_string_t raw = string_from_utf8(raw_utf8, raw_length);
  if (raw == NULL) return NULL;
  moonbit_string_t result = client_restore_preferences(handle, raw);
  drop_input(raw);
  return return_string(result);
}

char *dsh_moonbit_client_queue_command(
    DshMoonBitClientHandle handle,
    const uint8_t *command_id_utf8, size_t command_id_length,
    const uint8_t *operation_utf8, size_t operation_length,
    const uint8_t *session_id_utf8, size_t session_id_length,
    const uint8_t *input_utf8, size_t input_length,
    int32_t approval_revision) {
  if (!ready()) return NULL;
  moonbit_string_t command_id = string_from_utf8(command_id_utf8, command_id_length);
  moonbit_string_t operation = string_from_utf8(operation_utf8, operation_length);
  moonbit_string_t session_id = string_from_utf8(session_id_utf8, session_id_length);
  moonbit_string_t input = string_from_utf8(input_utf8, input_length);
  if (command_id == NULL || operation == NULL || session_id == NULL || input == NULL) {
    drop_input(command_id);
    drop_input(operation);
    drop_input(session_id);
    drop_input(input);
    return NULL;
  }
  moonbit_string_t result = client_queue_command(
      handle, command_id, operation, session_id, input, approval_revision);
  drop_input(command_id);
  drop_input(operation);
  drop_input(session_id);
  drop_input(input);
  return return_string(result);
}

char *dsh_moonbit_client_mark_command_sent(
    DshMoonBitClientHandle handle, const uint8_t *command_id_utf8,
    size_t command_id_length) {
  if (!ready()) return NULL;
  moonbit_string_t command_id = string_from_utf8(command_id_utf8, command_id_length);
  if (command_id == NULL) return NULL;
  moonbit_string_t result = client_mark_command_sent(handle, command_id);
  drop_input(command_id);
  return return_string(result);
}

char *dsh_moonbit_client_mark_command_uncertain(
    DshMoonBitClientHandle handle, const uint8_t *command_id_utf8,
    size_t command_id_length) {
  if (!ready()) return NULL;
  moonbit_string_t command_id = string_from_utf8(command_id_utf8, command_id_length);
  if (command_id == NULL) return NULL;
  moonbit_string_t result = client_mark_command_uncertain(handle, command_id);
  drop_input(command_id);
  return return_string(result);
}

char *dsh_moonbit_client_apply_receipt(
    DshMoonBitClientHandle handle, const uint8_t *raw_utf8, size_t raw_length) {
  if (!ready()) return NULL;
  moonbit_string_t raw = string_from_utf8(raw_utf8, raw_length);
  if (raw == NULL) return NULL;
  moonbit_string_t result = client_apply_receipt(handle, raw);
  drop_input(raw);
  return return_string(result);
}

char *dsh_moonbit_client_mark_receipt_missing(
    DshMoonBitClientHandle handle, const uint8_t *command_id_utf8,
    size_t command_id_length) {
  if (!ready()) return NULL;
  moonbit_string_t command_id = string_from_utf8(command_id_utf8, command_id_length);
  if (command_id == NULL) return NULL;
  moonbit_string_t result = client_mark_receipt_missing(handle, command_id);
  drop_input(command_id);
  return return_string(result);
}

char *dsh_moonbit_client_pending_ids_json(DshMoonBitClientHandle handle) {
  if (!ready()) return NULL;
  return return_string(client_pending_ids(handle));
}

char *dsh_moonbit_new_command_id(
    const uint8_t *now_ms_utf8, size_t now_ms_length,
    const uint8_t *entropy_hex_utf8, size_t entropy_hex_length) {
  if (!ready()) return NULL;
  moonbit_string_t now_ms = string_from_utf8(now_ms_utf8, now_ms_length);
  moonbit_string_t entropy_hex = string_from_utf8(entropy_hex_utf8, entropy_hex_length);
  if (now_ms == NULL || entropy_hex == NULL) {
    drop_input(now_ms);
    drop_input(entropy_hex);
    return NULL;
  }
  moonbit_string_t result = client_new_command_id(now_ms, entropy_hex);
  drop_input(now_ms);
  drop_input(entropy_hex);
  return return_string(result);
}

void dsh_moonbit_free_string(char *value) {
  free(value);
}
