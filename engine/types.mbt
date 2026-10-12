///|
/// A provider-independent harness. All state and event history is owned by
/// this value; the host performs only the effects returned by take_effects.
pub struct Engine {
  priv tools : Array[Tool]
  priv sessions : Map[String, Session]
  priv order : Array[String]
  priv effects : Map[String, Effect]
  priv queued : Array[String]
  priv mut next_session : Int
  priv mut next_effect : Int
  priv config_error : String?
}

///|
/// Opaque checkpoint for a native Stop-hook decision. The token is issued only
/// after a provider completion has durably entered the stopping boundary and
/// cannot be constructed or edited by callers.
pub struct NativeStopHookCheckpoint {
  priv session_id : String
  priv turn_id : Int
  priv event_seq : Int
}

///|
/// Opaque checkpoint for admitting a native child prompt and its claimed
/// SubagentStart inbox batch through UserPromptSubmit.
pub struct NativeSubagentPromptHookCheckpoint {
  priv session_id : String
  priv turn_id : Int
  priv step : Int
  priv generation : Int
  priv initial : Bool
  priv prompt : String
  priv contexts : Array[String]
}

///|
/// Opaque checkpoint for admitting a committed PostToolUse context batch
/// through the next UserPromptSubmit hook before the following provider step.
pub struct NativePostToolPromptHookCheckpoint {
  priv session_id : String
  priv turn_id : Int
  priv step : Int
  priv generation : Int
  priv event_seq : Int
  priv contexts : Array[String]
}

///|
/// Opaque identity for a durable native command-hook invocation. The event is
/// checkpointed before the external command starts; a result can only be paired
/// with this exact open invocation.
pub struct NativeHookInvocationCheckpoint {
  priv session_id : String
  priv turn_id : Int
  priv point : String
  priv handler_id : String
  priv event_seq : Int
}

///|
priv enum Status {
  Idle
  Running
  AwaitingApproval
  Completed
  Failed
  Cancelled
} derive(Eq)

///|
priv enum EffectClass {
  Read
  Write
  Shell
  Session
} derive(Eq)

///|
priv enum EffectKind {
  Llm
  ToolExecution
} derive(Eq)

///|
priv enum CallStage {
  Pending
  Called
  Waiting
  Approved
  Denied
  Dispatched
  OutcomeKnown
  Completed
  Settled
} derive(Eq)

///|
/// Custom text input remains tagged through engine history. The host executes
/// only function-shaped calls whose arguments pass the configured schema.
priv enum ToolCallKind {
  FunctionCall
  CustomCall
} derive(Eq)

///|
priv struct Tool {
  name : String
  description : String
  input_schema : Json
  effect : EffectClass
}

///|
priv struct ToolCall {
  id : String
  name : String
  arguments : String
  kind : ToolCallKind
  mut stage : CallStage
  mut effect_id : String?
  mut completed_content : String?
  mut completed_error : Bool?
  mut completed_contexts : Array[String]
}

///|
priv struct Approval {
  call_id : String
  name : String
  arguments : Json
}

///|
priv struct Event {
  seq : Int
  kind : EngineEventKind
  turn_id : Int
  step : Int
  data : Json
}

///|
priv struct Session {
  id : String
  title : String
  system_prompt : String
  max_steps : Int
  mut imported : Bool
  mut fork_source : ForkSource?
  mut status : Status
  mut turn_id : Int
  mut step : Int
  events : Array[Event]
  calls : Array[ToolCall]
  used_calls : Map[String, Bool]
  /// First call whose durable result has not entered model history.
  mut cursor : Int
  /// First call not yet admitted to execution.
  mut schedule_cursor : Int
  /// The current consecutive read-only call group is open for replenishment.
  mut parallel_group : Bool
  /// Host effects currently executing for read-only calls, keyed by effect id.
  active_tool_effects : Map[String, String]
  mut approval : Approval?
  mut active_effect : String?
  mut active_kind : EffectKind?
  mut open_step : Bool
  /// Latest validated whole-list todo/write snapshot; cleared at turn/start.
  mut todos : Array[Json]?
  mut retry_count : Int
  mut retry_max_retries : Int?
  mut retry_initial_delay_ms : Int?
  mut retry_max_delay_ms : Int?
  mut pending_retry_id : String?
  /// Sticky max-token ending retained across same-turn Stop-hook continuations.
  mut sticky_max_tokens : Bool
  /// A completed provider step is paused while the native Stop hook runs.
  mut stop_hook_pending : Bool
  mut stop_hook_event_seq : Int?
  /// The next-step message is staged before UserPromptSubmit runs.
  mut stop_continuation_text : String?
  /// Start inbox claimed together with a staged Stop continuation.
  mut stop_continuation_hook_contexts : Array[String]
  mut stop_continuation_admitted : Bool
  mut stop_prompt_context_count : Int
  mut stop_prompt_context_length : Int
  /// Ephemeral SubagentStart context waiting for the next provider request.
  pending_hook_contexts : Array[String]
  /// The child runtime opts in so Start input pauses at the next pre-step hook.
  mut subagent_prompt_hook_admission : Bool
  /// One claimed batch is immutable while its UserPromptSubmit command runs.
  mut subagent_prompt_hook_active : Bool
  mut subagent_prompt_hook_initial : Bool
  mut subagent_prompt_hook_generation : Int
  mut subagent_prompt_hook_contexts : Array[String]
  mut subagent_prompt_hook_prompt : String?
  /// Root tool completions opt into deferred PostToolUse prompt admission.
  mut post_tool_prompt_hook_admission : Bool
  /// PostToolUse contexts claimed at the next root pre-step boundary.
  mut post_tool_prompt_hook_active : Bool
  mut post_tool_prompt_hook_generation : Int
  mut post_tool_prompt_hook_event_seq : Int?
  mut post_tool_prompt_hook_contexts : Array[String]
  mut post_tool_prompt_hook_messages : Array[Json]
  /// Ephemeral child PostToolUse inbox messages retain one message per call.
  pending_subagent_post_tool_contexts : Array[String]
  pending_subagent_post_tool_messages : Array[Json]
  mut subagent_prompt_hook_start_contexts : Array[String]
  mut subagent_prompt_hook_post_tool_messages : Array[Json]
}

///|
priv struct ForkSource {
  parent_session_id : String
  source_event_count : Int
  source_status : String
  source_turn_id : Int
  source_step : Int
  effect_map : Array[(String, String)]
}

///|
priv struct Effect {
  id : String
  kind : EffectKind
  session_id : String
  turn_id : Int
  step : Int
  call_id : String?
  request : Json
}

///|
priv struct LlmCompletion {
  content : String
  reasoning : String?
  calls : Array[ToolCall]
  finish_reason : String
  usage : Json?
}

///|
priv suberror EngineError {
  Invalid(String)
}

///|
fn status_text(status : Status) -> String {
  match status {
    Idle => "idle"
    Running => "running"
    AwaitingApproval => "awaiting_approval"
    Completed => "completed"
    Failed => "failed"
    Cancelled => "cancelled"
  }
}

///|
fn effect_text(effect : EffectClass) -> String {
  match effect {
    Read => "read"
    Write => "write"
    Shell => "shell"
    Session => "session"
  }
}

///|
fn Session::is_busy(self : Session) -> Bool {
  self.status == Running || self.status == AwaitingApproval
}

///|
fn fresh_session(
  id : String,
  title : String,
  system_prompt : String,
  max_steps : Int,
) -> Session {
  {
    id,
    title,
    system_prompt,
    max_steps,
    imported: false,
    fork_source: None,
    status: Idle,
    turn_id: 0,
    step: 0,
    events: [],
    calls: [],
    used_calls: Map([]),
    cursor: 0,
    schedule_cursor: 0,
    parallel_group: false,
    active_tool_effects: Map([]),
    approval: None,
    active_effect: None,
    active_kind: None,
    open_step: false,
    todos: None,
    retry_count: 0,
    retry_max_retries: None,
    retry_initial_delay_ms: None,
    retry_max_delay_ms: None,
    pending_retry_id: None,
    sticky_max_tokens: false,
    stop_hook_pending: false,
    stop_hook_event_seq: None,
    stop_continuation_text: None,
    stop_continuation_hook_contexts: [],
    stop_continuation_admitted: false,
    stop_prompt_context_count: 0,
    stop_prompt_context_length: 0,
    pending_hook_contexts: [],
    subagent_prompt_hook_admission: false,
    subagent_prompt_hook_active: false,
    subagent_prompt_hook_initial: false,
    subagent_prompt_hook_generation: 0,
    subagent_prompt_hook_contexts: [],
    subagent_prompt_hook_prompt: None,
    post_tool_prompt_hook_admission: false,
    post_tool_prompt_hook_active: false,
    post_tool_prompt_hook_generation: 0,
    post_tool_prompt_hook_event_seq: None,
    post_tool_prompt_hook_contexts: [],
    post_tool_prompt_hook_messages: [],
    pending_subagent_post_tool_messages: [],
    pending_subagent_post_tool_contexts: [],
    subagent_prompt_hook_start_contexts: [],
    subagent_prompt_hook_post_tool_messages: [],
  }
}
