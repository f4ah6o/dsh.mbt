#include "dsh_moonbit_client.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static char *state(DshMoonBitClientHandle handle) {
  char *value = dsh_moonbit_client_state_json(handle);
  assert(value != NULL);
  return value;
}

int main(void) {
  assert(dsh_moonbit_runtime_start() == 0);
  assert(dsh_moonbit_runtime_start() == 0);

  DshMoonBitClientHandle first = dsh_moonbit_client_create();
  DshMoonBitClientHandle second = dsh_moonbit_client_create();
  assert(first > 0 && second > 0 && first != second);

  char *first_state = state(first);
  char *second_state = state(second);
  assert(strstr(first_state, "\"connection\":\"offline\"") != NULL);
  assert(strstr(second_state, "\"draft\":\"\"") != NULL);
  dsh_moonbit_free_string(first_state);
  dsh_moonbit_free_string(second_state);

  first_state = dsh_moonbit_client_begin_connect(first);
  assert(first_state != NULL && strstr(first_state, "\"connection\":\"connecting\"") != NULL);
  dsh_moonbit_free_string(first_state);

  const char snapshot[] =
      "{\"protocol_version\":1,\"server_id\":\"server-a\","
      "\"identity_key\":\"user-a\",\"workspace_id\":\"work-a\","
      "\"auth_revision\":1,\"epoch\":\"epoch-a\",\"revision\":1,"
      "\"cursor\":\"epoch-a:1\",\"auth\":{\"state\":\"signed_out\","
      "\"account\":null,\"plan_usage\":\"disabled\",\"scopes\":[],"
      "\"models\":[]},\"projection\":{\"sessions\":[{\"id\":\"s1\"}]}}";
  char *accepted = dsh_moonbit_client_accept_snapshot(
      first, (const uint8_t *)snapshot, sizeof(snapshot) - 1);
  assert(accepted != NULL && strstr(accepted, "\"status\":\"accepted\"") != NULL);
  dsh_moonbit_free_string(accepted);

  const uint8_t draft[] = "日本語 🌱\0embedded";
  char *preferences = dsh_moonbit_client_set_draft(first, draft, sizeof(draft) - 1);
  assert(preferences != NULL && strstr(preferences, "\"draft\":\"日本語 🌱\\u0000embedded\"") != NULL);
  dsh_moonbit_free_string(preferences);

  first_state = state(first);
  assert(strstr(first_state, "日本語 🌱\\u0000embedded") != NULL);
  assert(strstr(first_state, "\"identity_key\":\"user-a\"") != NULL);
  dsh_moonbit_free_string(first_state);

  char *command_id = dsh_moonbit_new_command_id(
      (const uint8_t *)"1700000000000", 13,
      (const uint8_t *)"00000000000000000000000000000000", 32);
  assert(command_id != NULL);
  assert(strcmp(command_id, "018bcfe5-6800-7000-8000-000000000000") == 0);
  dsh_moonbit_free_string(command_id);

  const uint8_t invalid_utf8[] = { 0xff };
  assert(dsh_moonbit_client_set_draft(first, invalid_utf8, sizeof(invalid_utf8)) == NULL);

  assert(dsh_moonbit_client_dispose(first) == 1);
  first_state = state(first);
  assert(strstr(first_state, "\"status\":\"disposed\"") != NULL);
  dsh_moonbit_free_string(first_state);
  assert(dsh_moonbit_client_dispose(second) == 1);
  assert(dsh_moonbit_client_dispose(second) == 0);

  puts("MoonBit C ABI lifecycle and UTF-8 smoke passed");
  return 0;
}
