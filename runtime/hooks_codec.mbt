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
  if value.length() > NATIVE_HOOK_CONTEXT_ITEM_LIMIT {
    return Err("hook additionalContext exceeds the 4096-character limit")
  }
  if contexts.length() >= NATIVE_HOOK_CONTEXT_COUNT_LIMIT {
    return Err("hook additionalContext exceeds the 32-item limit")
  }
  let mut total_length = value.length()
  for context in contexts {
    total_length += context.length()
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
