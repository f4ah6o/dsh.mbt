///|
priv struct ImportedCall {
  turn : Int
  step : Int
  name : String
  arguments : String
  mut call_seq : Int?
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
  turn : Int?
  mut summary_seq : Int?
  mut summary_span : Array[Int]
  mut checkpoint_seq : Int?
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
  mut next_agent_seq : Int
  agents : Map[Int, ImportedWorkflowAgent]
  mut ended : Bool
}

///|
priv struct ImportedSubagentCatalog {
  workflow_run_id : String?
  mut workflow_linked : Bool
}

///|
priv struct V4Replay {
  mut turn : Int
  mut step : Int
  snapshot : Bool
  mut status : Status
  mut open_turn : Bool
  mut open_step : Bool
  seeded : Bool
  mut title : String
  mut seed_marker : Int?
  mut fork_closing : Bool
  mut request_header : Json?
  mut request_context_seen : Bool
  mut surface : Array[Int]
  mut protected_head : Int?
  mut compaction : ImportedCompaction?
  mut pending_prune : Array[Int]?
  mut admitted_prompt : Bool
  mut assistant_seen : Bool
  mut terminal_step_without_assistant : Bool
  source_types : Map[Int, String]
  source_records : Map[Int, Json]
  user_messages : Map[Int, Bool]
  message_ids : Map[String, Bool]
  calls : Map[String, ImportedCall]
  call_order : Array[String]
  ptc_dispatches : Map[String, ImportedPtcDispatch]
  workflow_runs : Map[String, ImportedWorkflowRun]
  subagents : Map[String, ImportedSubagentCatalog]
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
