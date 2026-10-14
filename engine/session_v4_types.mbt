///|
priv struct ImportedCall {
  turn : Int32
  step : Int32
  name : String
  arguments : String
  mut call_seq : Int32?
  mut started : Bool
  mut settled : Bool
}

///|
priv struct InboxReplay {
  mut next_turn : Array[Json]
  mut next_step : Array[Json]
  mut claimed_turn : Array[Json]
  mut claimed_step : Array[Json]
  used_ids : Map[String, Bool]
}

///|
priv struct ImportedCompaction {
  id : String
  command : Json?
  turn : Int32?
  mut summary_seq : Int32?
  mut summary_span : Array[Int32]
  mut checkpoint_seq : Int32?
}

///|
priv struct ImportedPtcDispatch {
  root_call_id : String
  parent_call_id : String
  name : String
  arguments : Json
  mut settled : Bool
}

///|
priv struct ImportedWorkflowAgent {
  child_id : String
  mut settled : Bool
}

///|
priv struct ImportedWorkflowRun {
  owner_call_id : String
  mut next_agent_seq : Int32
  agents : Map[Int32, ImportedWorkflowAgent]
  mut ended : Bool
}

///|
priv struct ImportedSubagentCatalog {
  workflow_run_id : String?
  mut workflow_linked : Bool
}

///|
priv struct ImportedRetryChain {
  retry_id : String
  retry : Int32
}

///|
priv struct ImportedRetrySchedule {
  turn : Int32
  step : Int32
}

///|
priv struct V4Replay {
  mut turn : Int32
  mut step : Int32
  snapshot : Bool
  mut status : Status
  mut open_turn : Bool
  mut open_step : Bool
  seeded : Bool
  mut title : String
  mut seed_marker : Int32?
  mut fork_closing : Bool
  mut request_header : Json?
  mut request_context_seen : Bool
  mut surface : Array[Int32]
  mut protected_head : Int32?
  mut compaction : ImportedCompaction?
  mut pending_prune : Array[Int32]?
  mut admitted_prompt : Bool
  mut assistant_seen : Bool
  mut terminal_step_without_assistant : Bool
  source_types : Map[Int32, String]
  source_records : Map[Int32, Json]
  user_messages : Map[Int32, Bool]
  message_ids : Map[String, Bool]
  calls : Map[String, ImportedCall]
  call_order : Array[String]
  ptc_dispatches : Map[String, ImportedPtcDispatch]
  workflow_runs : Map[String, ImportedWorkflowRun]
  subagents : Map[String, ImportedSubagentCatalog]
  retry_chains : Map[String, ImportedRetryChain]
  retry_ids : Map[String, String]
  retry_schedules : Map[String, ImportedRetrySchedule]
  started_retries : Map[String, Bool]
  inbox : InboxReplay
}

///|
priv struct ProjectedContent {
  mut text : String
  mut reasoning : String
  calls : Array[Json]
  changes : Array[Json]
}

///|
/// Import the upstream Session v4 JSONL as inert source history. Only complete
