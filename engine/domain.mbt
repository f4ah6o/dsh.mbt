// Copyright 2026 dsh.mbt contributors. SPDX-License-Identifier: MIT
// Typed application boundary values. JSON and operation strings remain only
// in compatibility codecs and persistence/carrier adapters.

///|
pub struct SessionId {
  priv value : String
} derive(Eq)

///|
pub extend SessionId with Eq::{not_equal, equal}

///|
pub fn SessionId::new(value : String) -> Result[SessionId, String] {
  match validate_domain_id(value, "session id") {
    Ok(value) => Ok({ value, })
    Err(error) => Err(error)
  }
}

///|
pub fn SessionId::as_string(self : SessionId) -> String {
  self.value
}

///|
pub struct EffectId {
  priv value : String
} derive(Eq)

///|
pub extend EffectId with Eq::{not_equal, equal}

///|
pub fn EffectId::new(value : String) -> Result[EffectId, String] {
  if !value.has_prefix("effect-") || value.length() <= 7 || value.length() > 16 {
    return Err("effect id is malformed")
  }
  for character in value[7:] {
    if character < '0' || character > '9' {
      return Err("effect id is malformed")
    }
  }
  Ok({ value, })
}

///|
pub fn EffectId::as_string(self : EffectId) -> String {
  self.value
}

///|
fn EffectId::from_validated(value : String) -> EffectId {
  { value, }
}

///|
pub struct ToolCallId {
  priv value : String
} derive(Eq)

///|
pub extend ToolCallId with Eq::{not_equal, equal}

///|
pub fn ToolCallId::new(value : String) -> Result[ToolCallId, String] {
  match validate_domain_id(value, "tool call id") {
    Ok(value) => Ok({ value, })
    Err(error) => Err(error)
  }
}

///|
pub fn ToolCallId::as_string(self : ToolCallId) -> String {
  self.value
}

///|
fn validate_domain_id(value : String, name : String) -> Result[String, String] {
  if value.is_empty() || value.length() > 128 {
    return Err(name + " must contain 1 to 128 characters")
  }
  for character in value {
    if !((character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z') ||
      (character >= '0' && character <= '9') ||
      character == '_' ||
      character == '-' ||
      character == '.' ||
      character == ':') {
      return Err(name + " contains unsupported characters")
    }
  }
  Ok(value)
}

///|
/// Semantic engine operations accepted by the legacy JSON operation adapter.
pub(all) enum EngineCommand {
  CreateSession(String?, String, String, Int32?)
  ForkSession(SessionId, String?, String?)
  ListSessions
  ImportSession(String)
  GetSession(SessionId)
  SendPrompt(SessionId, String)
  SendPromptWithContexts(SessionId, String, Array[String])
  /// Start a prompt after applying the existing default tool-result pruning
  /// policy inside the same engine transaction.
  SendPromptWithAutoPruning(SessionId, String, Array[String])
  /// Apply a user-selected UTF-8 byte ceiling to every provider request in the
  /// turn. The boolean opts into the existing pre-send pruning policy.
  SendPromptWithRequestByteCeiling(
    SessionId,
    String,
    Array[String],
    Bool,
    Int32
  )
  CancelSession(SessionId)
  PruneToolResults(SessionId, ToolResultPruneConfig)
  RecordCompactionSummary(SessionId, Json, String, Int32, Int32, Int32, Int32)
  ApproveTool(SessionId, ToolCallId, Bool)
}

///|
/// Parse one legacy operation/input pair once into a validated typed command.
pub fn EngineCommand::from_json(
  operation : String,
  input : Json,
) -> Result[EngineCommand, String] {
  try {
    let input = checked_copy(input)
    ignore(fields(input))
    let command = match operation {
      "session_create" => {
        let title = optional_string(input, "title", "New session", max=512)
        let system_prompt = optional_string(
          input,
          "system_prompt",
          "You are a helpful coding assistant.",
          max=16384,
        )
        let max_steps = match fields(input).get("max_steps") {
          None => None
          Some(value) => Some(int_value(value, "max_steps", 1, 64))
        }
        let id = match fields(input).get("id") {
          None => None
          Some(value) =>
            Some(identifier(string_value(value, "id", max=128), "id"))
        }
        CreateSession(id, title, system_prompt, max_steps)
      }
      "session_fork" => {
        let session_id = decode_session_id(input)
        let id = match fields(input).get("id") {
          None => None
          Some(value) =>
            Some(identifier(string_value(value, "id", max=128), "id"))
        }
        let title = match fields(input).get("title") {
          None => None
          Some(value) => Some(string_value(value, "title", max=512))
        }
        ForkSession(session_id, id, title)
      }
      "session_list" => ListSessions
      "session_import" =>
        ImportSession(required_string(input, "jsonl", max=262144))
      "session_get" => GetSession(decode_session_id(input))
      "session_send" => {
        let session_id = decode_session_id(input)
        let prompt = required_string(input, "prompt", max=16384)
        if prompt.is_empty() {
          raise Invalid("prompt must not be empty")
        }
        let additional_contexts : Array[String] = []
        match fields(input).get("additional_contexts") {
          None => ()
          Some(Json::Array(values)) if values.length() <= 32 =>
            for value in values {
              match value {
                Json::String(text) if text.length() > 0 && text.length() <= 4096 =>
                  additional_contexts.push(text)
                _ =>
                  raise Invalid("additional_contexts contains an invalid item")
              }
            }
          Some(_) =>
            raise Invalid(
              "additional_contexts must be an array of at most 32 strings",
            )
        }
        let mut total_context_length = 0
        for context in additional_contexts {
          total_context_length += context.length()
        }
        if total_context_length > 16384 {
          raise Invalid(
            "additional_contexts exceeds the aggregate length limit",
          )
        }
        let auto_prune_tool_results = match
          fields(input).get("auto_prune_tool_results") {
          None | Some(Json::False) => false
          Some(Json::True) => true
          Some(_) => raise Invalid("auto_prune_tool_results must be a boolean")
        }
        let max_request_utf8_bytes = match
          fields(input).get("max_provider_request_utf8_bytes") {
          None => None
          Some(value) =>
            Some(
              int_value(
                value,
                "max_provider_request_utf8_bytes",
                1,
                PROVIDER_CONTEXT_MEASUREMENT_MAX_UTF8_BYTES,
              ),
            )
        }
        match max_request_utf8_bytes {
          Some(maximum) =>
            SendPromptWithRequestByteCeiling(
              session_id, prompt, additional_contexts, auto_prune_tool_results, maximum,
            )
          None if auto_prune_tool_results =>
            SendPromptWithAutoPruning(session_id, prompt, additional_contexts)
          None if additional_contexts.is_empty() =>
            SendPrompt(session_id, prompt)
          None =>
            SendPromptWithContexts(session_id, prompt, additional_contexts)
        }
      }
      "session_cancel" => CancelSession(decode_session_id(input))
      "session_prune_tool_results" =>
        PruneToolResults(
          decode_session_id(input),
          prune_config_from_input(input),
        )
      "session_compact_summary" =>
        RecordCompactionSummary(
          decode_session_id(input),
          required_field(input, "plan"),
          required_string(input, "summary", max=1048576),
          int_value(
            required_field(input, "retain_recent_turns"),
            "retain_recent_turns",
            1,
            1000000,
          ),
          int_value(
            required_field(input, "max_source_event_json_utf8_bytes"),
            "max_source_event_json_utf8_bytes",
            1,
            1048576,
          ),
          int_value(
            required_field(input, "max_source_messages_json_utf8_bytes"),
            "max_source_messages_json_utf8_bytes",
            1,
            1048576,
          ),
          int_value(
            required_field(input, "max_summary_json_utf8_bytes"),
            "max_summary_json_utf8_bytes",
            1,
            1048576,
          ),
        )
      "tool_approve" => {
        let session_id = decode_session_id(input)
        let call_id = ToolCallId::from_validated(
          identifier(required_string(input, "call_id", max=128), "call_id"),
        )
        let approved = bool_value(required_field(input, "approved"), "approved")
        ApproveTool(session_id, call_id, approved)
      }
      _ => raise Invalid("Unknown operation: {operation}")
    }
    Ok(command)
  } catch {
    Invalid(message) => Err(message)
  }
}

///|
/// Return the validated prompt payload for a session-send command. The final
/// flag reports whether the command opted into pre-send tool-result pruning.
pub fn EngineCommand::session_send_details(
  self : EngineCommand,
) -> (SessionId, String, Array[String], Bool)? {
  match self {
    SendPrompt(session_id, prompt) => Some((session_id, prompt, [], false))
    SendPromptWithContexts(session_id, prompt, contexts) =>
      Some((session_id, prompt, contexts, false))
    SendPromptWithAutoPruning(session_id, prompt, contexts) =>
      Some((session_id, prompt, contexts, true))
    SendPromptWithRequestByteCeiling(
      session_id,
      prompt,
      contexts,
      auto_prune_tool_results,
      _
    ) => Some((session_id, prompt, contexts, auto_prune_tool_results))
    _ => None
  }
}

///|
/// Return the opt-in byte ceiling carried by a session-send command.
pub fn EngineCommand::session_send_request_byte_ceiling(
  self : EngineCommand,
) -> Int32? {
  match self {
    SendPromptWithRequestByteCeiling(_, _, _, _, maximum) => Some(maximum)
    _ => None
  }
}

///|
fn ToolCallId::from_validated(value : String) -> ToolCallId {
  { value, }
}

///|
/// Revalidate public enum payloads at the application boundary. The JSON
/// adapter constructs only validated values, but the public typed variants
/// can also be instantiated directly by host code.
fn EngineCommand::validate(self : EngineCommand) -> Result[Unit, String] {
  match self {
    CreateSession(id, title, system_prompt, max_steps) => {
      match id {
        Some(value) =>
          match SessionId::new(value) {
            Ok(_) => ()
            Err(error) => return Err(error)
          }
        None => ()
      }
      if title.length() > 512 {
        return Err("title exceeds the length limit")
      }
      if system_prompt.length() > 16384 {
        return Err("system_prompt exceeds the length limit")
      }
      match max_steps {
        Some(value) if value < 1 || value > 64 =>
          return Err("max_steps is outside the supported range")
        _ => ()
      }
      Ok(())
    }
    ForkSession(_, id, title) => {
      match id {
        Some(value) =>
          match SessionId::new(value) {
            Ok(_) => ()
            Err(error) => return Err(error)
          }
        None => ()
      }
      match title {
        Some(value) if value.length() > 512 =>
          Err("title exceeds the length limit")
        _ => Ok(())
      }
    }
    ImportSession(jsonl) if jsonl.length() > 262144 =>
      Err("jsonl exceeds the length limit")
    SendPrompt(_, prompt) if prompt.is_empty() =>
      Err("prompt must not be empty")
    SendPrompt(_, prompt) if prompt.length() > 16384 =>
      Err("prompt exceeds the length limit")
    SendPromptWithContexts(_, prompt, _) if prompt.is_empty() =>
      Err("prompt must not be empty")
    SendPromptWithContexts(_, prompt, _) if prompt.length() > 16384 =>
      Err("prompt exceeds the length limit")
    SendPromptWithAutoPruning(_, prompt, _) if prompt.is_empty() =>
      Err("prompt must not be empty")
    SendPromptWithAutoPruning(_, prompt, _) if prompt.length() > 16384 =>
      Err("prompt exceeds the length limit")
    SendPromptWithRequestByteCeiling(_, prompt, _, _, _) if prompt.is_empty() =>
      Err("prompt must not be empty")
    SendPromptWithRequestByteCeiling(_, prompt, _, _, _) if prompt.length() >
      16384 => Err("prompt exceeds the length limit")
    SendPromptWithContexts(_, _, additional_contexts) if additional_contexts.length() >
      32 => Err("additional_contexts must contain at most 32 items")
    SendPromptWithAutoPruning(_, _, additional_contexts) if additional_contexts.length() >
      32 => Err("additional_contexts must contain at most 32 items")
    SendPromptWithRequestByteCeiling(_, _, additional_contexts, _, _) if additional_contexts.length() >
      32 => Err("additional_contexts must contain at most 32 items")
    SendPromptWithRequestByteCeiling(_, _, _, _, maximum) if maximum < 1 ||
      maximum > PROVIDER_CONTEXT_MEASUREMENT_MAX_UTF8_BYTES =>
      Err("max_provider_request_utf8_bytes must be between 1 and 16777216")
    SendPromptWithContexts(_, _, additional_contexts) => {
      let mut total_length = 0
      for context in additional_contexts {
        if context.is_empty() || context.length() > 4096 {
          return Err("additional_contexts contains an invalid item")
        }
        total_length += context.length()
      }
      if total_length > 16384 {
        Err("additional_contexts exceeds the aggregate length limit")
      } else {
        Ok(())
      }
    }
    SendPromptWithAutoPruning(_, _, additional_contexts) => {
      let mut total_length = 0
      for context in additional_contexts {
        if context.is_empty() || context.length() > 4096 {
          return Err("additional_contexts contains an invalid item")
        }
        total_length += context.length()
      }
      if total_length > 16384 {
        Err("additional_contexts exceeds the aggregate length limit")
      } else {
        Ok(())
      }
    }
    SendPromptWithRequestByteCeiling(_, _, additional_contexts, _, _) => {
      let mut total_length = 0
      for context in additional_contexts {
        if context.is_empty() || context.length() > 4096 {
          return Err("additional_contexts contains an invalid item")
        }
        total_length += context.length()
      }
      if total_length > 16384 {
        Err("additional_contexts exceeds the aggregate length limit")
      } else {
        Ok(())
      }
    }
    PruneToolResults(_, config) =>
      match
        ToolResultPruneConfig::new(
          config.threshold_chars,
          config.head_chars,
          config.tail_chars,
        ) {
        Ok(_) => Ok(())
        Err(error) => Err(error)
      }
    RecordCompactionSummary(
      _,
      plan,
      summary,
      retain_recent_turns,
      max_event_bytes,
      max_message_bytes,
      max_summary_bytes
    ) => {
      if summary.is_empty() || summary.length() > 1048576 {
        return Err("summary must contain 1 to 1048576 characters")
      }
      if retain_recent_turns < 1 || retain_recent_turns > 1000000 {
        return Err("retain_recent_turns must be between 1 and 1000000")
      }
      if max_event_bytes < 1 ||
        max_event_bytes > 1048576 ||
        max_message_bytes < 1 ||
        max_message_bytes > 1048576 {
        return Err("source byte budgets must be between 1 and 1048576")
      }
      if max_summary_bytes < 1 || max_summary_bytes > 1048576 {
        return Err("max_summary_json_utf8_bytes must be between 1 and 1048576")
      }
      try {
        ignore(checked_copy(plan))
        Ok(())
      } catch {
        Invalid(error) => Err(error)
      }
    }
    _ => Ok(())
  }
}

///|
fn decode_session_id(input : Json) -> SessionId raise EngineError {
  SessionId::from_validated(
    identifier(required_string(input, "session_id", max=128), "session_id"),
  )
}

///|
fn SessionId::from_validated(value : String) -> SessionId {
  { value, }
}

///|
pub(all) enum EngineEventKind {
  SessionCreated
  SessionForked
  SessionCancelled
  SessionInterrupted
  TurnStarted
  TurnEnded
  UserMessage
  AssistantMessage
  AssistantAttempt
  AssistantStreamDelta
  StepStarted
  StepEnded
  LlmRequest
  LlmRetry
  LlmRetryStarted
  ToolApprovalRequested
  ToolApprovalResolved
  ToolCall
  ToolRequest
  ToolCompleted
  ToolResult
  ToolResultPruned
  CompactionSummary
  TodoWrite
  HookInvoked
  HookResult
  SubagentStartContext
  StopHookSettled
  UpstreamHeader
  UpstreamEvent
  Other(String)
} derive(Eq)

///|
pub extend EngineEventKind with Eq::{not_equal, equal}

///|
pub fn EngineEventKind::from_wire(value : String) -> EngineEventKind {
  match value {
    "session/created" => SessionCreated
    "session/forked" => SessionForked
    "session/cancelled" => SessionCancelled
    "session/interrupted" => SessionInterrupted
    "turn/start" => TurnStarted
    "turn/end" => TurnEnded
    "user/message" => UserMessage
    "assistant/message" => AssistantMessage
    "assistant/attempt" => AssistantAttempt
    "assistant/stream_delta" => AssistantStreamDelta
    "step/start" => StepStarted
    "step/end" => StepEnded
    "llm/request" => LlmRequest
    "llm/retry" => LlmRetry
    "llm/retry-started" => LlmRetryStarted
    "tool/approval/requested" => ToolApprovalRequested
    "tool/approval/resolved" => ToolApprovalResolved
    "tool/call" => ToolCall
    "tool/request" => ToolRequest
    "tool/completed" => ToolCompleted
    "tool/result" => ToolResult
    "tool/result/pruned" => ToolResultPruned
    "compaction/summary" => CompactionSummary
    "todo/write" => TodoWrite
    "hook/invoked" => HookInvoked
    "hook/result" => HookResult
    "hook/subagent-start-context" => SubagentStartContext
    "hook/stop-settled" => StopHookSettled
    "upstream/header" => UpstreamHeader
    "upstream/event" => UpstreamEvent
    other => Other(other)
  }
}

///|
pub fn EngineEventKind::wire(self : EngineEventKind) -> String {
  match self {
    SessionCreated => "session/created"
    SessionForked => "session/forked"
    SessionCancelled => "session/cancelled"
    SessionInterrupted => "session/interrupted"
    TurnStarted => "turn/start"
    TurnEnded => "turn/end"
    UserMessage => "user/message"
    AssistantMessage => "assistant/message"
    AssistantAttempt => "assistant/attempt"
    AssistantStreamDelta => "assistant/stream_delta"
    StepStarted => "step/start"
    StepEnded => "step/end"
    LlmRequest => "llm/request"
    LlmRetry => "llm/retry"
    LlmRetryStarted => "llm/retry-started"
    ToolApprovalRequested => "tool/approval/requested"
    ToolApprovalResolved => "tool/approval/resolved"
    ToolCall => "tool/call"
    ToolRequest => "tool/request"
    ToolCompleted => "tool/completed"
    ToolResult => "tool/result"
    ToolResultPruned => "tool/result/pruned"
    CompactionSummary => "compaction/summary"
    TodoWrite => "todo/write"
    HookInvoked => "hook/invoked"
    HookResult => "hook/result"
    SubagentStartContext => "hook/subagent-start-context"
    StopHookSettled => "hook/stop-settled"
    UpstreamHeader => "upstream/header"
    UpstreamEvent => "upstream/event"
    Other(value) => value
  }
}

///|
pub struct EngineEvent {
  priv seq : Int32
  priv kind : EngineEventKind
  priv turn_id : Int32
  priv step : Int32
  priv data : Json
}

///|
pub fn EngineEvent::sequence(self : EngineEvent) -> Int32 {
  self.seq
}

///|
pub fn EngineEvent::kind(self : EngineEvent) -> EngineEventKind {
  self.kind
}

///|
pub fn EngineEvent::turn(self : EngineEvent) -> Int32 {
  self.turn_id
}

///|
pub fn EngineEvent::step(self : EngineEvent) -> Int32 {
  self.step
}

///|
pub fn EngineEvent::data(self : EngineEvent) -> Json {
  detached(self.data)
}

///|
pub fn EngineEvent::json(self : EngineEvent) -> Json {
  object([
    ("seq", integer(self.seq)),
    ("type", Json::string(self.kind.wire())),
    ("turn_id", integer(self.turn_id)),
    ("step", integer(self.step)),
    ("data", detached(self.data)),
  ])
}

///|
pub(all) enum EffectType {
  Provider
  Tool
} derive(Eq)

///|
pub extend EffectType with Eq::{not_equal, equal}

///|
pub struct EngineEffect {
  priv id : EffectId
  priv session_id : SessionId
  priv kind : EffectType
  priv request : Json
}

///|
pub fn EngineEffect::id(self : EngineEffect) -> EffectId {
  self.id
}

///|
pub fn EngineEffect::session_id(self : EngineEffect) -> SessionId {
  self.session_id
}

///|
pub fn EngineEffect::kind(self : EngineEffect) -> EffectType {
  self.kind
}

///|
pub fn EngineEffect::request(self : EngineEffect) -> Json {
  detached(self.request)
}

///|
pub fn EngineEffect::json(self : EngineEffect) -> Json {
  object([
    ("id", Json::string(self.id.as_string())),
    (
      "kind",
      Json::string(
        match self.kind {
          Provider => "llm"
          Tool => "tool"
        },
      ),
    ),
    ("session_id", Json::string(self.session_id.as_string())),
    ("request", detached(self.request)),
  ])
}
