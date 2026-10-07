///|
fn replay_v4_retry_event(
  replay : V4Replay,
  kind : String,
  data : Json,
  line_number : Int,
) -> (Int, Int) raise EngineError {
  match kind {
    "llm/retry" => replay_v4_retry_schedule(replay, data, line_number)
    "llm/retry-started" => replay_v4_retry_started(replay, data)
    _ => raise Invalid("Unsupported Session v4 retry event: \{kind}")
  }
}

///|
fn replay_v4_retry_schedule(
  replay : V4Replay,
  data : Json,
  _line_number : Int,
) -> (Int, Int) raise EngineError {
  v4_only_fields(
    data,
    [
      "retryId", "turn", "step", "provider", "mode", "policyKey", "retry", "delayMs",
      "failure",
    ],
    ["maxRetries"],
    "LLM retry schedule",
  )
  if !replay.open_turn {
    raise Invalid("Session v4 llm/retry is outside an open turn")
  }
  let turn = int_value(required_field(data, "turn"), "retry turn", 1, 1000000)
  let step = int_value(required_field(data, "step"), "retry step", 0, 64)
  if turn != replay.turn || step != replay.step {
    raise Invalid(
      "Session v4 llm/retry does not match the current turn and step",
    )
  }
  let retry_id = v4_retry_nonempty_string(data, "retryId")
  let provider = v4_retry_nonempty_string(data, "provider")
  let policy_key = v4_retry_nonempty_string(data, "policyKey")
  let mode = required_string(data, "mode", max=32)
  if mode != "normal" && mode != "always" {
    raise Invalid("Session v4 llm/retry mode must be normal or always")
  }
  let retry = int_value(required_field(data, "retry"), "retry", 1, 32767)
  validate_v4_retry_delay(required_field(data, "delayMs"))
  validate_v4_retry_failure(required_field(data, "failure"))
  match (mode, fields(data).get("maxRetries")) {
    ("normal", Some(max_retries)) => {
      validate_v4_retry_positive_safe_integer(max_retries, "maxRetries")
      match max_retries {
        Json::Number(limit, ..) if retry.to_double() > limit =>
          raise Invalid("Session v4 llm/retry exceeds maxRetries")
        _ => ()
      }
    }
    ("normal", None) =>
      raise Invalid("Normal Session v4 llm/retry requires maxRetries")
    ("always", Some(_)) =>
      raise Invalid("Always Session v4 llm/retry must omit maxRetries")
    ("always", None) => ()
    _ => raise Invalid("Session v4 llm/retry mode is malformed")
  }
  let header = match replay.request_header {
    Some(header) => header
    None =>
      raise Invalid("Session v4 llm/retry has no preceding request/header")
  }
  let config = required_field(header, "config")
  if provider != required_string(config, "provider", max=256) {
    raise Invalid(
      "Session v4 llm/retry provider differs from the request/header",
    )
  }

  let chain_key = v4_retry_chain_key(turn, step, provider, policy_key)
  match replay.retry_chains.get(chain_key) {
    Some(previous) =>
      if retry != previous.retry + 1 || retry_id != previous.retry_id {
        raise Invalid(
          "Session v4 llm/retry must continue its policy chain with the same retryId",
        )
      }
    None => {
      if retry != 1 {
        raise Invalid("Session v4 llm/retry policy chain must begin at retry 1")
      }
      match replay.retry_ids.get(retry_id) {
        Some(_) =>
          raise Invalid(
            "Session v4 llm/retry reuses a retryId across policy chains",
          )
        None => replay.retry_ids.set(retry_id, chain_key)
      }
    }
  }
  let attempt_key = v4_retry_attempt_key(retry_id, retry)
  if replay.retry_schedules.get(attempt_key) is Some(_) {
    raise Invalid("Session v4 llm/retry duplicates a scheduled attempt")
  }
  replay.retry_chains.set(chain_key, { retry_id, retry, })
  replay.retry_schedules.set(attempt_key, { turn, step, })
  (turn, step)
}

///|
fn replay_v4_retry_started(
  replay : V4Replay,
  data : Json,
) -> (Int, Int) raise EngineError {
  v4_only_fields(
    data,
    ["retryId", "turn", "step", "retry"],
    [],
    "LLM retry start",
  )
  let retry_id = v4_retry_nonempty_string(data, "retryId")
  let turn = int_value(required_field(data, "turn"), "retry turn", 0, 1000000)
  let step = int_value(required_field(data, "step"), "retry step", 0, 64)
  let retry = int_value(required_field(data, "retry"), "retry", 1, 32767)
  let attempt_key = v4_retry_attempt_key(retry_id, retry)
  let scheduled = match replay.retry_schedules.get(attempt_key) {
    Some(scheduled) => scheduled
    None =>
      raise Invalid(
        "Session v4 llm/retry-started has no prior scheduled attempt",
      )
  }
  if scheduled.turn != turn || scheduled.step != step {
    raise Invalid(
      "Session v4 llm/retry-started changes its scheduled coordinates",
    )
  }
  if replay.started_retries.get(attempt_key) is Some(_) {
    raise Invalid("Session v4 llm/retry-started duplicates a scheduled attempt")
  }
  replay.started_retries.set(attempt_key, true)
  (turn, step)
}

///|
fn v4_retry_chain_key(
  turn : Int,
  step : Int,
  provider : String,
  policy_key : String,
) -> String {
  "\{turn}:\{step}:\{provider.length()}:\{provider}:\{policy_key.length()}:\{policy_key}"
}

///|
fn v4_retry_attempt_key(retry_id : String, retry : Int) -> String {
  "\{retry_id.length()}:\{retry_id}:\{retry}"
}

///|
fn v4_retry_nonempty_string(
  data : Json,
  key : String,
) -> String raise EngineError {
  let value = required_string(data, key)
  if value.length() == 0 {
    raise Invalid("Session v4 retry \{key} must not be empty")
  }
  value
}

///|
fn validate_v4_retry_delay(value : Json) -> Unit raise EngineError {
  match value {
    Json::Number(number, ..) =>
      if number.is_inf() || number.is_nan() || number < 0.0 {
        raise Invalid(
          "Session v4 llm/retry delayMs must be finite and non-negative",
        )
      }
    _ => raise Invalid("Session v4 llm/retry delayMs must be a finite number")
  }
}

///|
fn validate_v4_retry_positive_safe_integer(
  value : Json,
  label : String,
) -> Unit raise EngineError {
  match value {
    Json::Number(number, ..) =>
      if number.is_inf() ||
        number.is_nan() ||
        number < 1.0 ||
        number > 9007199254740991.0 ||
        number % 1.0 != 0.0 {
        raise Invalid(
          "Session v4 llm/retry \{label} must be a positive safe integer",
        )
      }
    _ =>
      raise Invalid(
        "Session v4 llm/retry \{label} must be a positive safe integer",
      )
  }
}

///|
fn validate_v4_retry_failure(value : Json) -> Unit raise EngineError {
  v4_only_fields(
    value,
    ["message", "code"],
    ["status", "providerRetryAfterMs", "requestId", "offloadImages"],
    "LLM retry failure",
  )
  if required_string(value, "message").length() == 0 ||
    required_string(value, "code").length() == 0 {
    raise Invalid(
      "Session v4 llm/retry failure message and code must not be empty",
    )
  }
  match fields(value).get("status") {
    Some(status) => ignore(int_value(status, "retry failure status", 100, 599))
    None => ()
  }
  match fields(value).get("providerRetryAfterMs") {
    Some(Json::Number(number, ..)) =>
      if number.is_inf() || number.is_nan() || number <= 0.0 {
        raise Invalid(
          "Session v4 retry failure providerRetryAfterMs must be positive and finite",
        )
      }
    Some(_) =>
      raise Invalid(
        "Session v4 retry failure providerRetryAfterMs must be a finite number",
      )
    None => ()
  }
  match fields(value).get("requestId") {
    Some(request_id) =>
      if string_value(request_id, "retry failure requestId").length() == 0 {
        raise Invalid("Session v4 retry failure requestId must not be empty")
      }
    None => ()
  }
  match fields(value).get("offloadImages") {
    Some(offload_images) =>
      validate_v4_retry_positive_safe_integer(offload_images, "offloadImages")
    None => ()
  }
}
