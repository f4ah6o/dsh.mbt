///|
/// Ported from deepseek-ai/deepseek-harness commit
/// 5badb15009ae1756c3afe0ae0cef1faafc290ccc:
/// packages/compaction/compaction-tool-result-pruner/src/config.ts and
/// src/index.ts. This v1 adaptation uses an explicit session operation and
/// keeps the original tool/result event as the durable source.
const PRUNE_MARKER : String = "\n\n[... tool result middle pruned ...]\n\n"

///|
const DEFAULT_PRUNE_THRESHOLD : Int = 8192

///|
const DEFAULT_PRUNE_HEAD : Int = 4096

///|
const DEFAULT_PRUNE_TAIL : Int = 1024

///|
pub struct ToolResultPruneConfig {
  threshold_chars : Int
  head_chars : Int
  tail_chars : Int
}

///|
pub fn ToolResultPruneConfig::new(
  threshold_chars : Int,
  head_chars : Int,
  tail_chars : Int,
) -> Result[ToolResultPruneConfig, String] {
  Ok(checked_prune_config(threshold_chars, head_chars, tail_chars)) catch {
    Invalid(message) => Err(message)
  }
}

///|
fn code_point_length(text : String) -> Int {
  text[:].char_length()
}

///|
fn reject_unknown_fields(
  value : Json,
  allowed : Array[String],
) -> Unit raise EngineError {
  for key, _ in fields(value) {
    if !allowed.any(candidate => candidate == key) {
      raise Invalid("Unknown field: \{key}")
    }
  }
}

///|
fn checked_prune_config(
  threshold_chars : Int,
  head_chars : Int,
  tail_chars : Int,
) -> ToolResultPruneConfig raise EngineError {
  if threshold_chars <= 0 || threshold_chars > SESSION_CAPACITY {
    raise Invalid(
      "threshold_chars must be an integer between 1 and \{SESSION_CAPACITY}",
    )
  }
  if head_chars < 0 || head_chars > SESSION_CAPACITY {
    raise Invalid(
      "head_chars must be an integer between 0 and \{SESSION_CAPACITY}",
    )
  }
  if tail_chars < 0 || tail_chars > SESSION_CAPACITY {
    raise Invalid(
      "tail_chars must be an integer between 0 and \{SESSION_CAPACITY}",
    )
  }
  let emitted = head_chars + code_point_length(PRUNE_MARKER) + tail_chars
  if emitted > threshold_chars {
    raise Invalid(
      "head_chars + marker + tail_chars (\{emitted}) must be at most threshold_chars (\{threshold_chars})",
    )
  }
  { threshold_chars, head_chars, tail_chars, }
}

///|
fn prune_config_from_input(
  input : Json,
) -> ToolResultPruneConfig raise EngineError {
  reject_unknown_fields(input, [
    "session_id", "threshold_chars", "head_chars", "tail_chars",
  ])
  let values = fields(input)
  let threshold_chars = match values.get("threshold_chars") {
    Some(value) => int_value(value, "threshold_chars", 1, SESSION_CAPACITY)
    None => DEFAULT_PRUNE_THRESHOLD
  }
  let head_chars = match values.get("head_chars") {
    Some(value) => int_value(value, "head_chars", 0, SESSION_CAPACITY)
    None => DEFAULT_PRUNE_HEAD
  }
  let tail_chars = match values.get("tail_chars") {
    Some(value) => int_value(value, "tail_chars", 0, SESSION_CAPACITY)
    None => DEFAULT_PRUNE_TAIL
  }
  checked_prune_config(threshold_chars, head_chars, tail_chars)
}

///|
fn prune_config_from_event(
  data : Json,
) -> ToolResultPruneConfig raise EngineError {
  reject_unknown_fields(data, [
    "source_seq", "result_seq", "call_id", "threshold_chars", "head_chars", "tail_chars",
    "chars_before", "chars_after", "content",
  ])
  checked_prune_config(
    int_value(
      required_field(data, "threshold_chars"),
      "threshold_chars",
      1,
      SESSION_CAPACITY,
    ),
    int_value(
      required_field(data, "head_chars"),
      "head_chars",
      0,
      SESSION_CAPACITY,
    ),
    int_value(
      required_field(data, "tail_chars"),
      "tail_chars",
      0,
      SESSION_CAPACITY,
    ),
  )
}

///|
fn prune_text(text : String, config : ToolResultPruneConfig) -> String? {
  let points = text[:].to_array()
  let total = points.length()
  if total <= config.threshold_chars {
    return None
  }
  let tail_start = total - config.tail_chars
  let head = StringView::from_array(points[0:config.head_chars]).to_owned()
  let tail = StringView::from_array(points[tail_start:total]).to_owned()
  Some(head + PRUNE_MARKER + tail)
}

///|
/// The latest projected text and durable event sequence for each original
/// tool/result. Original events are never mutated or removed.
fn Session::tool_result_pruning_state(
  self : Session,
) -> (Map[Int, String], Map[Int, Int]) {
  let content_by_result : Map[Int, String] = Map([])
  let latest_seq_by_result : Map[Int, Int] = Map([])
  for event in self.events {
    if event.kind == EngineEventKind::ToolResult {
      match event.data {
        Json::Object(data) =>
          match data.get("content") {
            Some(Json::String(content)) =>
              content_by_result[event.seq] = content
            _ => ()
          }
        _ => ()
      }
      latest_seq_by_result[event.seq] = event.seq
    } else if event.kind == EngineEventKind::ToolResultPruned {
      match event.data {
        Json::Object(data) =>
          match (data.get("result_seq"), data.get("content")) {
            (Some(Json::Number(number, ..)), Some(Json::String(content))) => {
              let result_seq = number.to_int()
              if result_seq >= 0 &&
                result_seq < self.events.length() &&
                result_seq.to_double() == number {
                content_by_result[result_seq] = content
                latest_seq_by_result[result_seq] = event.seq
              }
            }
            _ => ()
          }
        _ => ()
      }
    }
  }
  (content_by_result, latest_seq_by_result)
}

///|
fn projected_tool_result(
  event : Event,
  content_by_result : Map[Int, String],
) -> Json {
  match content_by_result.get(event.seq) {
    None => detached(event.data)
    Some(content) =>
      match event.data {
        Json::Object(values) => {
          let data = values.copy()
          data.set("content", Json::string(content))
          Json::object(data)
        }
        _ => detached(event.data)
      }
  }
}

///|
fn Session::prune_tool_results(
  self : Session,
  config : ToolResultPruneConfig,
) -> Json raise EngineError {
  let (content_by_result, latest_seq_by_result) = self.tool_result_pruning_state()
  let replacements : Array[Json] = []
  let mut chars_removed = 0
  let candidates = self.events.filter(event => {
    event.kind == EngineEventKind::ToolResult
  })
  for event in candidates {
    let original = match content_by_result.get(event.seq) {
      Some(content) => content
      None => raise Invalid("Tool result is missing projected content")
    }
    match prune_text(original, config) {
      None => ()
      Some(content) => {
        if self.events.length() >= 32768 {
          raise Invalid("Session event limit reached; create a new session")
        }
        let call_id = required_string(event.data, "tool_call_id", max=128)
        let source_seq = match latest_seq_by_result.get(event.seq) {
          Some(value) => value
          None => raise Invalid("Tool result is missing its durable source")
        }
        let chars_before = code_point_length(original)
        let chars_after = code_point_length(content)
        let replacement_seq = self.events.length()
        self.append(
          "tool/result/pruned",
          object([
            ("source_seq", integer(source_seq)),
            ("result_seq", integer(event.seq)),
            ("call_id", Json::string(call_id)),
            ("threshold_chars", integer(config.threshold_chars)),
            ("head_chars", integer(config.head_chars)),
            ("tail_chars", integer(config.tail_chars)),
            ("chars_before", integer(chars_before)),
            ("chars_after", integer(chars_after)),
            ("content", Json::string(content)),
          ]),
        )
        content_by_result[event.seq] = content
        latest_seq_by_result[event.seq] = replacement_seq
        chars_removed += chars_before - chars_after
        replacements.push(
          object([
            ("original_seq", integer(event.seq)),
            ("source_seq", integer(source_seq)),
            ("replacement_seq", integer(replacement_seq)),
            ("call_id", Json::string(call_id)),
            ("chars_before", integer(chars_before)),
            ("chars_after", integer(chars_after)),
          ]),
        )
      }
    }
  }
  object([
    ("session", self.json()),
    ("pruned", Json::array(replacements)),
    ("chars_removed", integer(chars_removed)),
    ("chars_unit", Json::string("unicode_code_points")),
  ])
}

///|
fn Engine::prune_session_tool_results(
  self : Engine,
  id : SessionId,
  config : ToolResultPruneConfig,
) -> Json raise EngineError {
  let session = self.lookup(id.as_string())
  if session.imported {
    raise Invalid(
      "Imported Session v4 histories are read-only and cannot be pruned",
    )
  }
  if (session.status != Idle && session.status != Completed) ||
    session.open_step ||
    session.active_effect is Some(_) ||
    session.active_tool_effect_count() > 0 ||
    session.approval is Some(_) {
    raise Invalid(
      "Tool results can only be pruned on an idle or completed session",
    )
  }
  session.prune_tool_results(config)
}

///|
/// Validate one persisted projection against its exact source and policy.
/// The source must be the latest projection of the cited original result.
fn Session::validate_tool_result_prune(
  self : Session,
  data : Json,
) -> Unit raise EngineError {
  let config = prune_config_from_event(data)
  let result_seq = int_value(
    required_field(data, "result_seq"),
    "result_seq",
    0,
    SESSION_CAPACITY,
  )
  let source_seq = int_value(
    required_field(data, "source_seq"),
    "source_seq",
    0,
    SESSION_CAPACITY,
  )
  if result_seq >= self.events.length() || source_seq >= self.events.length() {
    raise Invalid("Tool result pruning references a future event")
  }
  if (self.status != Idle && self.status != Completed) ||
    self.open_step ||
    self.active_effect is Some(_) ||
    self.active_tool_effect_count() > 0 ||
    self.approval is Some(_) {
    raise Invalid("Tool result pruning requires a settled closed turn")
  }
  let original = self.events[result_seq]
  if original.kind != EngineEventKind::ToolResult || source_seq < result_seq {
    raise Invalid("Tool result pruning does not cite an original result")
  }
  let call_id = required_string(data, "call_id", max=128)
  if required_string(original.data, "tool_call_id", max=128) != call_id {
    raise Invalid("Tool result pruning call identity differs from its source")
  }
  let (content_by_result, latest_seq_by_result) = self.tool_result_pruning_state()
  if latest_seq_by_result.get(result_seq) != Some(source_seq) {
    raise Invalid("Tool result pruning source is stale or unrelated")
  }
  let source = self.events[source_seq]
  if (source_seq == result_seq && source.kind != EngineEventKind::ToolResult) ||
    (
      source_seq != result_seq &&
      source.kind != EngineEventKind::ToolResultPruned
    ) {
    raise Invalid("Tool result pruning source has the wrong event type")
  }
  let current = match content_by_result.get(result_seq) {
    Some(content) => content
    None => raise Invalid("Tool result pruning source has no text content")
  }
  let before = code_point_length(current)
  if int_value(
      required_field(data, "chars_before"),
      "chars_before",
      0,
      SESSION_CAPACITY,
    ) !=
    before {
    raise Invalid("Tool result pruning input size disagrees with its source")
  }
  let expected = match prune_text(current, config) {
    Some(content) => content
    None => raise Invalid("Tool result pruning source is within its threshold")
  }
  let recorded = string_value(
    required_field(data, "content"),
    "pruned content",
    max=SESSION_CAPACITY,
  )
  let after = code_point_length(expected)
  if recorded != expected ||
    int_value(
      required_field(data, "chars_after"),
      "chars_after",
      0,
      SESSION_CAPACITY,
    ) !=
    after ||
    after >= before ||
    after > config.threshold_chars {
    raise Invalid("Tool result pruning projection does not match its policy")
  }
}
