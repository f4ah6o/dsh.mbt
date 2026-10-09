///|
priv enum NativeHookAction {
  Continue
  Deny(String)
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
) -> Result[NativeHookAction, String] {
  if capture.truncated {
    return Err("hook output exceeded the 16 KiB per-stream limit")
  }
  if capture.exit_code == 2 {
    let reason = capture.stderr.trim().to_owned()
    return Ok(
      NativeHookAction::Deny(
        if reason.is_empty() {
          "hook exited with blocking status 2"
        } else {
          reason
        },
      ),
    )
  }
  if capture.exit_code != 0 {
    // Claude Code treats every non-zero exit other than 2 as a hook error that
    // does not block the tool. Keep that behavior for the supported points.
    return Ok(NativeHookAction::Continue)
  }
  let stdout = capture.stdout.trim().to_owned()
  if stdout.is_empty() || !stdout.has_prefix("{") {
    return Ok(NativeHookAction::Continue)
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
      match
        native_hook_exact_fields(
          specific,
          ["hookEventName", "permissionDecision", "permissionDecisionReason"],
          "hookSpecificOutput",
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
  Ok(action)
}
