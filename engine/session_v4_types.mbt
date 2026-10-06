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
priv struct V4Replay {
  mut turn : Int
  mut step : Int
  mut status : Status
  mut open_turn : Bool
  mut open_step : Bool
  seeded : Bool
  mut title : String
  mut seed_marker : Int?
  mut fork_closing : Bool
  mut request_header : Json?
  mut request_context_seen : Bool
  mut admitted_prompt : Bool
  mut assistant_seen : Bool
  mut terminal_step_without_assistant : Bool
  source_types : Map[Int, String]
  user_messages : Map[Int, Bool]
  message_ids : Map[String, Bool]
  calls : Map[String, ImportedCall]
  call_order : Array[String]
  inbox : InboxReplay
}

///|
priv struct ProjectedContent {
  mut text : String
  mut reasoning : String
  calls : Array[Json]
}

///|
/// Import the upstream Session v4 JSONL as inert source history. Only complete
