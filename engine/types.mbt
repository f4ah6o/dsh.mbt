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
  mut retry_count : Int
  mut retry_max_retries : Int?
  mut retry_initial_delay_ms : Int?
  mut retry_max_delay_ms : Int?
  mut pending_retry_id : String?
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
    retry_count: 0,
    retry_max_retries: None,
    retry_initial_delay_ms: None,
    retry_max_delay_ms: None,
    pending_retry_id: None,
  }
}
