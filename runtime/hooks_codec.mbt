///|
priv enum NativeHookAction {
  Continue
  Deny(String)
}

///|
priv struct NativeHookOutcome {
  action : NativeHookAction
  additional_contexts : Array[String]
}

///|
priv struct NativeStopHookResult {
  rank : Int
  reason : String?
}

///|
const NATIVE_HOOK_CONTEXT_ITEM_LIMIT : Int = 4096

///|
const NATIVE_HOOK_CONTEXT_COUNT_LIMIT : Int = 32

///|
const NATIVE_HOOK_CONTEXT_TOTAL_LENGTH_LIMIT : Int = 16384

///|
fn native_hook_add_context(
  contexts : Array[String],
  value : String,
) -> Result[Unit, String] {
  if value.is_empty() {
    return Ok(())
  }
  let value_units = native_provider_utf16_units(value)
  if value_units > NATIVE_HOOK_CONTEXT_ITEM_LIMIT {
    return Err("hook additionalContext exceeds the 4096-UTF-16-code-unit limit")
  }
  if contexts.length() >= NATIVE_HOOK_CONTEXT_COUNT_LIMIT {
    return Err("hook additionalContext exceeds the 32-item limit")
  }
  let mut total_length = value_units
  for context in contexts {
    total_length += native_provider_utf16_units(context)
  }
  if total_length > NATIVE_HOOK_CONTEXT_TOTAL_LENGTH_LIMIT {
    return Err(
      "hook additionalContext exceeds the 16384-code-unit aggregate limit",
    )
  }
  contexts.push(value)
  Ok(())
}

///|
fn native_hook_result_with_contexts(
  result : Json,
  contexts : Array[String],
  source_kind? : String = "hooks-claude-code",
) -> Json {
  if contexts.is_empty() {
    return result
  }
  let fields = match native_hook_object(result) {
    Some(value) => value.copy()
    None => return result
  }
  fields["additional_contexts"] = Json::array(
    contexts.map(context => Json::string(context)),
  )
  fields["additional_contexts_source_kind"] = Json::string(source_kind)
  Json::object(fields)
}

///|
fn native_hook_limit_reason(value : String) -> String {
  let output = StringBuilder()
  let mut count = 0
  for character in value {
    if count >= 4096 {
      break
    }
    output.write_char(character)
    count += 1
  }
  output.to_string()
}

///|
fn native_hook_prefix_utf16(value : String, maximum : Int) -> String {
  let output = StringBuilder()
  let mut units = 0
  for character in value {
    let width = if character.to_int() > 0xFFFF { 2 } else { 1 }
    if units + width > maximum {
      break
    }
    output.write_char(character)
    units += width
  }
  output.to_string()
}

///|
/// JavaScript's String.trim whitespace set used by the pinned hook bridge.
fn native_hook_js_trim_space(character : Char) -> Bool {
  let value = character.to_int()
  value == 0x0009 ||
  value == 0x000A ||
  value == 0x000B ||
  value == 0x000C ||
  value == 0x000D ||
  value == 0x0020 ||
  value == 0x00A0 ||
  value == 0x1680 ||
  (value >= 0x2000 && value <= 0x200A) ||
  value == 0x2028 ||
  value == 0x2029 ||
  value == 0x202F ||
  value == 0x205F ||
  value == 0x3000 ||
  value == 0xFEFF
}

///|
fn native_hook_js_trim(value : String) -> String {
  let characters : Array[Char] = []
  for character in value {
    characters.push(character)
  }
  let mut start = 0
  let mut end = characters.length()
  while start < end && native_hook_js_trim_space(characters[start]) {
    start += 1
  }
  while end > start && native_hook_js_trim_space(characters[end - 1]) {
    end -= 1
  }
  let output = StringBuilder()
  for index in start..<end {
    output.write_char(characters[index])
  }
  output.to_string()
}

///|
/// The JS bridge slices stderr by UTF-16 units and adds an ellipsis after an
/// over-limit prefix. MoonBit strings cannot contain an isolated surrogate,
/// so a boundary that would split a supplementary scalar keeps its safe prefix.
fn native_hook_stderr_summary(value : String) -> String? {
  let trimmed = native_hook_js_trim(value)
  if trimmed.is_empty() {
    return None
  }
  let units = native_provider_utf16_units(trimmed)
  if units <= 500 {
    Some(trimmed)
  } else {
    Some(native_hook_prefix_utf16(trimmed, 500) + "…")
  }
}

///|
/// Preserve the upstream audit decision independently of the native adapter's
/// merged allow/block behavior and stricter output validation.
fn native_hook_diagnostic_decision(
  capture : NativeHookCapture,
  event : String,
) -> String {
  if capture.exit_code == 2 {
    return "block"
  }
  if capture.exit_code != 0 {
    return "pass"
  }
  let stdout = native_hook_js_trim(capture.stdout)
  if stdout.is_empty() || !stdout.has_prefix("{") {
    return "pass"
  }
  let document = @json.parse(stdout) catch { _ => return "pass" }
  let fields = match native_hook_object(document) {
    Some(value) => value
    None => return "pass"
  }
  let mut decision = match fields.get("decision") {
    Some(Json::String("approve")) => Some("approve")
    Some(Json::String("block")) => Some("block")
    _ => None
  }
  match fields.get("hookSpecificOutput") {
    Some(Json::Object(specific)) if specific.get("hookEventName") ==
      Some(Json::string(event)) =>
      match specific.get("permissionDecision") {
        Some(Json::String(value)) if ["allow", "deny", "ask"].contains(value) =>
          decision = Some(value)
        _ => ()
      }
    _ => ()
  }
  match decision {
    Some(value) => value
    None if fields.get("continue") == Some(Json::boolean(false)) => "stop"
    None => "pass"
  }
}

///|
fn native_hook_json_string(
  value : Json?,
  field : String,
) -> Result[String?, String] {
  match value {
    None => Ok(None)
    Some(Json::String(text)) if text.length() <= 4096 => Ok(Some(text))
    _ =>
      Err(
        "hook result field must be a string of at most 4096 characters: " +
        field,
      )
  }
}

///|
fn native_hook_result_decision(
  capture : NativeHookCapture,
  event : String,
) -> Result[NativeHookOutcome, String] {
  if capture.truncated {
    return Err("hook output exceeded the 16 KiB per-stream limit")
  }
  if capture.exit_code == 2 {
    let reason = capture.stderr.trim().to_owned()
    return Ok({
      action: NativeHookAction::Deny(
        if reason.is_empty() {
          "hook exited with blocking status 2"
        } else {
          reason
        },
      ),
      additional_contexts: [],
    })
  }
  if capture.exit_code != 0 {
    // Claude Code treats every non-zero exit other than 2 as a hook error that
    // does not block the tool. Keep that behavior for the supported points.
    return Ok({ action: NativeHookAction::Continue, additional_contexts: [], })
  }
  let stdout = capture.stdout.trim().to_owned()
  if stdout.is_empty() || !stdout.has_prefix("{") {
    return Ok({ action: NativeHookAction::Continue, additional_contexts: [], })
  }
  let document = @json.parse(stdout) catch {
    _ => return Err("hook returned malformed JSON")
  }
  let fields = match native_hook_object(document) {
    Some(value) => value
    None => return Err("hook JSON result must be an object")
  }
  match
    native_hook_exact_fields(
      fields,
      ["decision", "reason", "hookSpecificOutput"],
      "hook result",
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let mut action = NativeHookAction::Continue
  let additional_contexts : Array[String] = []
  let decision = match
    native_hook_json_string(fields.get("decision"), "decision") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let reason = match native_hook_json_string(fields.get("reason"), "reason") {
    Ok(value) => value.unwrap_or("")
    Err(error) => return Err(error)
  }
  match decision {
    Some("block") =>
      action = NativeHookAction::Deny(
        if reason.is_empty() {
          "blocked by hook"
        } else {
          reason
        },
      )
    Some("approve") | None => ()
    Some(_) => return Err("hook decision must be approve or block")
  }
  match fields.get("hookSpecificOutput") {
    None => ()
    Some(raw_specific) => {
      let specific = match native_hook_object(raw_specific) {
        Some(value) => value
        None => return Err("hookSpecificOutput must be an object")
      }
      let allowed_specific_fields = if event == "PostToolUse" {
        [
          "hookEventName", "permissionDecision", "permissionDecisionReason", "additionalContext",
        ]
      } else {
        ["hookEventName", "permissionDecision", "permissionDecisionReason"]
      }
      match
        native_hook_exact_fields(
          specific, allowed_specific_fields, "hookSpecificOutput",
        ) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      let event_name = match
        native_hook_json_string(specific.get("hookEventName"), "hookEventName") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      // Match Claude's event discriminator guard: a missing or different event
      // name discards the event-specific permission decision.
      if event_name == Some(event) {
        let permission = match
          native_hook_json_string(
            specific.get("permissionDecision"),
            "permissionDecision",
          ) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        let permission_reason = match
          native_hook_json_string(
            specific.get("permissionDecisionReason"),
            "permissionDecisionReason",
          ) {
          Ok(value) => value.unwrap_or("")
          Err(error) => return Err(error)
        }
        if event == "PostToolUse" {
          let additional_context = match
            native_hook_json_string(
              specific.get("additionalContext"),
              "additionalContext",
            ) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
          match additional_context {
            Some(value) =>
              match native_hook_add_context(additional_contexts, value) {
                Ok(_) => ()
                Err(error) => return Err(error)
              }
            None => ()
          }
        }
        match permission {
          Some("deny") =>
            action = NativeHookAction::Deny(
              if permission_reason.is_empty() {
                "denied by hook"
              } else {
                permission_reason
              },
            )
          Some("ask") =>
            return Err(
              "hook requested a new approval prompt; this runtime cannot reopen approval after dispatch",
            )
          // Event-specific permission decisions override the legacy top-level
          // decision for this hook. `allow` only clears this hook's block; it
          // never grants permission past the engine's approval gate.
          Some("allow") => action = NativeHookAction::Continue
          None => ()
          Some(_) =>
            return Err("permissionDecision must be allow, deny, or ask")
        }
      }
    }
  }
  Ok({ action, additional_contexts, })
}

///|
/// Decode only the Codex bridge's blocking decisions and supported context.
/// Unknown fields, malformed JSON, ask/allow decisions, and continue controls
/// remain neutral. Event-specific permission decisions override that hook's
/// top-level approve/block decision when the discriminator matches.
fn native_hook_codex_result_decision(
  capture : NativeHookCapture,
  event : String,
) -> NativeHookOutcome {
  if capture.truncated || (capture.exit_code != 0 && capture.exit_code != 2) {
    return { action: NativeHookAction::Continue, additional_contexts: [], }
  }
  if capture.exit_code == 2 {
    let reason = native_hook_js_trim(capture.stderr)
    return { action: NativeHookAction::Deny(reason), additional_contexts: [], }
  }
  let stdout = native_hook_js_trim(capture.stdout)
  if stdout.is_empty() {
    return { action: NativeHookAction::Continue, additional_contexts: [], }
  }
  if !stdout.has_prefix("{") {
    if event == "SessionStart" || event == "UserPromptSubmit" {
      return {
        action: NativeHookAction::Continue,
        additional_contexts: [stdout],
      }
    }
    return { action: NativeHookAction::Continue, additional_contexts: [], }
  }
  let document = @json.parse(stdout) catch {
    _ => return { action: NativeHookAction::Continue, additional_contexts: [], }
  }
  let fields = match native_hook_object(document) {
    Some(value) => value
    None =>
      return { action: NativeHookAction::Continue, additional_contexts: [], }
  }
  let top_decision = match fields.get("decision") {
    Some(Json::String("block")) => "block"
    _ => ""
  }
  let top_reason = match fields.get("reason") {
    Some(Json::String(value)) => native_hook_limit_reason(value)
    _ => ""
  }
  let mut blocked = top_decision == "block"
  let mut reason = top_reason
  let additional_contexts : Array[String] = []
  match fields.get("hookSpecificOutput") {
    Some(Json::Object(specific)) if specific.get("hookEventName") ==
      Some(Json::string(event)) => {
      match specific.get("permissionDecision") {
        Some(Json::String("deny")) => blocked = true
        Some(Json::String("allow" | "ask")) => blocked = false
        _ => ()
      }
      match specific.get("permissionDecisionReason") {
        Some(Json::String(value)) => reason = native_hook_limit_reason(value)
        _ => ()
      }
      if event == "SessionStart" ||
        event == "PostToolUse" ||
        event == "UserPromptSubmit" {
        match specific.get("additionalContext") {
          Some(Json::String(value)) =>
            ignore(native_hook_add_context(additional_contexts, value))
          _ => ()
        }
      }
    }
    _ => ()
  }
  {
    action: if blocked {
      NativeHookAction::Deny(reason)
    } else {
      NativeHookAction::Continue
    },
    additional_contexts,
  }
}

///|
/// Persist the Codex bridge's decoded decision for the hook/result audit row.
fn native_hook_codex_diagnostic_decision(
  capture : NativeHookCapture,
  event : String,
) -> String {
  if capture.exit_code == 2 {
    return "block"
  }
  if capture.truncated || capture.exit_code != 0 {
    return "pass"
  }
  let stdout = native_hook_js_trim(capture.stdout)
  if stdout.is_empty() || !stdout.has_prefix("{") {
    return "pass"
  }
  let document = @json.parse(stdout) catch { _ => return "pass" }
  let fields = match native_hook_object(document) {
    Some(value) => value
    None => return "pass"
  }
  let mut decision = match fields.get("decision") {
    Some(Json::String("approve")) => Some("approve")
    Some(Json::String("block")) => Some("block")
    _ => None
  }
  match fields.get("hookSpecificOutput") {
    Some(Json::Object(specific)) if specific.get("hookEventName") ==
      Some(Json::string(event)) =>
      match specific.get("permissionDecision") {
        Some(Json::String(value)) if ["allow", "deny", "ask"].contains(value) =>
          decision = Some(value)
        _ => ()
      }
    _ => ()
  }
  match decision {
    Some(value) => value
    None if fields.get("continue") == Some(Json::boolean(false)) => "stop"
    None => "pass"
  }
}

///|
/// SessionStart is context-only in the pinned Claude bridge. Its upstream
/// codec is lenient: plain output and malformed or mismatched event payloads
/// add no context, while decision/control fields are ignored by the bridge.
fn native_hook_session_start_context(
  capture : NativeHookCapture,
  dialect : String,
) -> String? {
  if capture.truncated || capture.exit_code != 0 {
    return None
  }
  if dialect == "codex" {
    let outcome = native_hook_codex_result_decision(capture, "SessionStart")
    return outcome.additional_contexts.get(0)
  }
  let stdout = capture.stdout.trim().to_owned()
  if !stdout.has_prefix("{") {
    return None
  }
  let document = @json.parse(stdout) catch { _ => return None }
  let fields = match native_hook_object(document) {
    Some(value) => value
    None => return None
  }
  let specific = match fields.get("hookSpecificOutput") {
    Some(value) => native_hook_object(value)
    None => None
  }
  let specific = match specific {
    Some(value) => value
    None => return None
  }
  if specific.get("hookEventName") != Some(Json::string("SessionStart")) {
    return None
  }
  match specific.get("additionalContext") {
    Some(Json::String(value)) => Some(value)
    _ => None
  }
}

///|
/// Decode only the Stop bridge's control fields. This intentionally treats
/// malformed JSON, unknown fields, wrong field types, and non-blocking process
/// failures as neutral outcomes, matching the pinned hook-protocol codec.
fn native_hook_stop_result_decision(
  capture : NativeHookCapture,
) -> NativeStopHookResult {
  if capture.exit_code == 2 {
    let reason = capture.stderr.trim().to_owned()
    return {
      rank: 3,
      reason: if reason.is_empty() {
        None
      } else {
        Some(reason)
      },
    }
  }
  if capture.truncated {
    return { rank: 0, reason: None, }
  }
  if capture.exit_code != 0 {
    return { rank: 0, reason: None, }
  }
  let stdout = capture.stdout.trim().to_owned()
  if stdout.is_empty() || !stdout.has_prefix("{") {
    return { rank: 0, reason: None, }
  }
  let document = @json.parse(stdout) catch {
    _ => return { rank: 0, reason: None, }
  }
  let fields = match native_hook_object(document) {
    Some(value) => value
    None => return { rank: 0, reason: None, }
  }
  let mut rank = match fields.get("decision") {
    Some(Json::String("approve")) => 1
    Some(Json::String("block")) => 3
    _ => 0
  }
  let mut reason = match fields.get("reason") {
    Some(Json::String(value)) => Some(value)
    _ => None
  }
  match fields.get("hookSpecificOutput") {
    Some(Json::Object(specific)) if specific.get("hookEventName") ==
      Some(Json::string("Stop")) => {
      match specific.get("permissionDecision") {
        Some(Json::String("allow")) => rank = 1
        Some(Json::String("ask")) => rank = 2
        Some(Json::String("deny")) => rank = 3
        _ => ()
      }
      match specific.get("permissionDecisionReason") {
        Some(Json::String(value)) => reason = Some(value)
        _ => ()
      }
    }
    _ => ()
  }
  { rank, reason, }
}

///|
/// The pinned SubagentStart bridge only consumes matching-event additionalContext.
/// Decisions and all other output fields are observationally ignored by the
/// lifecycle listener, so malformed output remains a neutral empty result.
fn native_hook_subagent_start_context(
  capture : NativeHookCapture,
) -> Array[String] {
  if capture.truncated || capture.exit_code != 0 {
    return []
  }
  let stdout = capture.stdout.trim().to_owned()
  if !stdout.has_prefix("{") {
    return []
  }
  let document = @json.parse(stdout) catch { _ => return [] }
  let fields = match native_hook_object(document) {
    Some(value) => value
    None => return []
  }
  let specific = match fields.get("hookSpecificOutput") {
    Some(Json::Object(value)) => value
    _ => return []
  }
  if specific.get("hookEventName") != Some(Json::string("SubagentStart")) {
    return []
  }
  match specific.get("additionalContext") {
    Some(Json::String(value)) if !value.is_empty() &&
      native_provider_utf16_units(value) <= NATIVE_HOOK_CONTEXT_ITEM_LIMIT =>
      [value]
    _ => []
  }
}

///|
fn native_hook_prompt_result_decision(
  capture : NativeHookCapture,
) -> Result[NativeHookOutcome, String] {
  if capture.truncated {
    return Err("hook output exceeded the 16 KiB per-stream limit")
  }
  if capture.exit_code == 2 {
    let reason = native_hook_limit_reason(capture.stderr.trim().to_owned())
    return Ok({
      action: NativeHookAction::Deny(
        if reason.is_empty() {
          "hook exited with blocking status 2"
        } else {
          reason
        },
      ),
      additional_contexts: [],
    })
  }
  if capture.exit_code != 0 {
    return Ok({ action: NativeHookAction::Continue, additional_contexts: [], })
  }
  let stdout = capture.stdout.trim().to_owned()
  if !stdout.has_prefix("{") {
    return Ok({ action: NativeHookAction::Continue, additional_contexts: [], })
  }
  let document = @json.parse(stdout) catch {
    // The pinned hook protocol treats malformed JSON as plain stdout. The
    // Claude Code prompt bridge only consumes structured additionalContext.
    _ =>
      return Ok({ action: NativeHookAction::Continue, additional_contexts: [], })
  }
  let fields = match native_hook_object(document) {
    Some(value) => value
    None =>
      return Ok({ action: NativeHookAction::Continue, additional_contexts: [], })
  }
  let mut action = NativeHookAction::Continue
  let reason = match fields.get("reason") {
    Some(Json::String(value)) => native_hook_limit_reason(value)
    _ => ""
  }
  match fields.get("decision") {
    Some(Json::String("block")) =>
      action = NativeHookAction::Deny(
        if reason.is_empty() {
          "blocked by hook"
        } else {
          reason
        },
      )
    // Only the legacy approve/block values are recognized at top level.
    Some(Json::String("approve")) => ()
    _ => ()
  }
  let additional_contexts : Array[String] = []
  match fields.get("hookSpecificOutput") {
    Some(Json::Object(specific)) if specific.get("hookEventName") ==
      Some(Json::string("UserPromptSubmit")) => {
      let permission = match specific.get("permissionDecision") {
        Some(Json::String(value)) => value
        _ => ""
      }
      let permission_reason = match specific.get("permissionDecisionReason") {
        Some(Json::String(value)) => Some(native_hook_limit_reason(value))
        _ => None
      }
      match (permission_reason, action) {
        (Some(value), NativeHookAction::Deny(_)) =>
          action = NativeHookAction::Deny(
            if value.is_empty() {
              "blocked by hook"
            } else {
              value
            },
          )
        _ => ()
      }
      match permission {
        "deny" => {
          let deny_reason = match permission_reason {
            Some(value) if !value.is_empty() => value
            Some(_) => "denied by hook"
            None => if reason.is_empty() { "denied by hook" } else { reason }
          }
          action = NativeHookAction::Deny(deny_reason)
        }
        // UserPromptSubmit maps only a deny to rejection. Claude Code's
        // ask/allow values do not create a new approval gate here.
        "allow" | "ask" => action = NativeHookAction::Continue
        _ => ()
      }
      match specific.get("additionalContext") {
        Some(Json::String(value)) =>
          match native_hook_add_context(additional_contexts, value) {
            Ok(_) => ()
            Err(error) => return Err(error)
          }
        _ => ()
      }
    }
    _ => ()
  }
  Ok({ action, additional_contexts, })
}
