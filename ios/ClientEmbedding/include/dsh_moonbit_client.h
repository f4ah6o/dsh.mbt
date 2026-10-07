#ifndef DSH_MOONBIT_CLIENT_H
#define DSH_MOONBIT_CLIENT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t DshMoonBitClientHandle;

/// Initialize the MoonBit runtime once for this process. Returns 0 on success.
/// The runtime has no teardown API; dispose every client handle before app exit.
int32_t dsh_moonbit_runtime_start(void);

/// Create an independent shared-client state lifetime. Requires runtime start.
DshMoonBitClientHandle dsh_moonbit_client_create(void);
int32_t dsh_moonbit_client_dispose(DshMoonBitClientHandle handle);

/// Returned JSON and IDs are UTF-8, null terminated, and owned by the caller.
/// Release them with dsh_moonbit_free_string.
char *dsh_moonbit_client_state_json(DshMoonBitClientHandle handle);
char *dsh_moonbit_client_begin_connect(DshMoonBitClientHandle handle);
char *dsh_moonbit_client_connection_failed(DshMoonBitClientHandle handle);
char *dsh_moonbit_client_connection_restored(DshMoonBitClientHandle handle);
char *dsh_moonbit_client_accept_snapshot(
    DshMoonBitClientHandle handle, const uint8_t *raw_utf8, size_t raw_length);
char *dsh_moonbit_client_accept_session(
    DshMoonBitClientHandle handle, const uint8_t *raw_utf8, size_t raw_length);
char *dsh_moonbit_client_accept_event(
    DshMoonBitClientHandle handle, const uint8_t *raw_utf8, size_t raw_length,
    const uint8_t *event_id_utf8, size_t event_id_length);
char *dsh_moonbit_client_set_draft(
    DshMoonBitClientHandle handle, const uint8_t *value_utf8, size_t value_length);
char *dsh_moonbit_client_set_selection(
    DshMoonBitClientHandle handle, const uint8_t *value_utf8, size_t value_length);
char *dsh_moonbit_client_set_scroll_anchor(
    DshMoonBitClientHandle handle, const uint8_t *value_utf8, size_t value_length);
char *dsh_moonbit_client_set_follow_latest(
    DshMoonBitClientHandle handle, int32_t enabled);
char *dsh_moonbit_client_set_text_view(
    DshMoonBitClientHandle handle, int32_t enabled);
char *dsh_moonbit_client_persisted_state_json(DshMoonBitClientHandle handle);
char *dsh_moonbit_client_restore_preferences(
    DshMoonBitClientHandle handle, const uint8_t *raw_utf8, size_t raw_length);
char *dsh_moonbit_client_queue_command(
    DshMoonBitClientHandle handle,
    const uint8_t *command_id_utf8, size_t command_id_length,
    const uint8_t *operation_utf8, size_t operation_length,
    const uint8_t *session_id_utf8, size_t session_id_length,
    const uint8_t *input_utf8, size_t input_length,
    int32_t approval_revision);
char *dsh_moonbit_client_mark_command_sent(
    DshMoonBitClientHandle handle,
    const uint8_t *command_id_utf8, size_t command_id_length);
char *dsh_moonbit_client_mark_command_uncertain(
    DshMoonBitClientHandle handle,
    const uint8_t *command_id_utf8, size_t command_id_length);
char *dsh_moonbit_client_apply_receipt(
    DshMoonBitClientHandle handle, const uint8_t *raw_utf8, size_t raw_length);
char *dsh_moonbit_client_mark_receipt_missing(
    DshMoonBitClientHandle handle,
    const uint8_t *command_id_utf8, size_t command_id_length);
char *dsh_moonbit_client_pending_ids_json(DshMoonBitClientHandle handle);
char *dsh_moonbit_new_command_id(
    const uint8_t *now_ms_utf8, size_t now_ms_length,
    const uint8_t *entropy_hex_utf8, size_t entropy_hex_length);

void dsh_moonbit_free_string(char *value);

#ifdef __cplusplus
}
#endif

#endif
