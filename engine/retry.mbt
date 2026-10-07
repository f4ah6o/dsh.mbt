///|
fn retryable_provider_code(code : String) -> Bool {
  code == "EMPTY_RESPONSE" ||
  code == "RATE_LIMIT" ||
  code == "SERVER" ||
  code == "TIMEOUT" ||
  code == "TRANSPORT"
}

///|
fn validate_retry_fields(
  value : Json,
  allowed : Array[String],
) -> Unit raise EngineError {
  for key, _ in fields(value) {
    if !allowed.contains(key) {
      raise Invalid("Unknown provider retry field: \{key}")
    }
  }
}

///|
fn validate_provider_request_id(value : Json?) -> Unit raise EngineError {
  match value {
    None => ()
    Some(String(id)) => {
      if id.is_empty() || id.length() > 128 {
        raise Invalid("Provider request id must contain 1 to 128 characters")
      }
      for character in id {
        if !((character >= 'a' && character <= 'z') ||
          (character >= 'A' && character <= 'Z') ||
          (character >= '0' && character <= '9') ||
          character == '_' ||
          character == '-' ||
          character == '.') {
          raise Invalid("Provider request id contains an invalid character")
        }
      }
    }
    _ => raise Invalid("Provider request id must be a string")
  }
}

///|
/// Persist an eligible retry schedule before the host waits. The original LLM
/// effect remains active, so cancellation and late-result fencing still apply.
fn Engine::schedule_retry_impl(
  self : Engine,
  effect_id : String,
  policy : Json,
) -> Result[Json, String] {
  try {
    validate_retry_fields(policy, [
      "failure", "max_retries", "initial_delay_ms", "max_delay_ms",
    ])
    let effect = match self.effects.get(effect_id) {
      Some(effect) => effect
      None => raise Invalid("Unknown or settled provider effect")
    }
    let session = self.lookup(effect.session_id)
    if effect.kind != Llm ||
      session.status != Running ||
      session.active_effect != Some(effect_id) ||
      session.active_kind != Some(Llm) ||
      session.turn_id != effect.turn_id ||
      session.step != effect.step ||
      !session.open_step {
      raise Invalid("Stale or misplaced provider retry")
    }
    if session.pending_retry_id is Some(_) {
      raise Invalid("Provider retry is already waiting")
    }
    let failure = required_field(policy, "failure")
    validate_retry_fields(failure, [
      "code", "message", "status", "retry_after_ms", "request_id",
    ])
    validate_provider_request_id(fields(failure).get("request_id"))
    let code = required_string(failure, "code", max=32)
    let message = required_string(failure, "message", max=512)
    if !retryable_provider_code(code) {
      return Ok(object([("scheduled", boolean(false))]))
    }
    let max_retries = int_value(
      required_field(policy, "max_retries"),
      "max_retries",
      0,
      MAX_PROVIDER_RETRIES,
    )
    let initial_delay_ms = int_value(
      required_field(policy, "initial_delay_ms"),
      "initial_delay_ms",
      0,
      MAX_PROVIDER_RETRY_DELAY_MS,
    )
    let max_delay_ms = int_value(
      required_field(policy, "max_delay_ms"),
      "max_delay_ms",
      1,
      MAX_PROVIDER_RETRY_DELAY_MS,
    )
    if initial_delay_ms > max_delay_ms {
      raise Invalid("initial_delay_ms must not exceed max_delay_ms")
    }
    if session.retry_max_retries is Some(previous) &&
      (
        previous != max_retries ||
        session.retry_initial_delay_ms != Some(initial_delay_ms) ||
        session.retry_max_delay_ms != Some(max_delay_ms)
      ) {
      raise Invalid("Retry policy changed during the provider step")
    }
    let provider_retry_after_ms = match fields(failure).get("retry_after_ms") {
      None => None
      Some(value) => Some(int_value(value, "retry_after_ms", 0, 2147483647))
    }
    if session.stream_projection(effect_id).0 ||
      session.retry_count >= max_retries ||
      (provider_retry_after_ms is Some(delay) && delay > max_delay_ms) {
      return Ok(object([("scheduled", boolean(false))]))
    }
    let retry = session.retry_count + 1
    let delay_ms = match provider_retry_after_ms {
      Some(delay) if delay > 0 => delay
      _ =>
        @retry_math.capped_exponential_delay(
          initial_delay_ms, retry, max_delay_ms,
        )
    }
    let retry_id = "retry-\{effect_id}-\{retry}"
    let durable_failure = Map::from_array([
      ("code", Json::string(code)),
      ("message", Json::string(message)),
    ])
    match fields(failure).get("status") {
      Some(value) =>
        durable_failure.set(
          "status",
          integer(int_value(value, "status", 100, 599)),
        )
      None => ()
    }
    match provider_retry_after_ms {
      Some(delay) => durable_failure.set("retry_after_ms", integer(delay))
      None => ()
    }
    match fields(failure).get("request_id") {
      Some(value) => durable_failure.set("request_id", value)
      None => ()
    }
    session.append(
      "llm/retry",
      object([
        ("retry_id", Json::string(retry_id)),
        ("effect_id", Json::string(effect_id)),
        ("turn", integer(session.turn_id)),
        ("step", integer(session.step)),
        ("retry", integer(retry)),
        ("max_retries", integer(max_retries)),
        ("initial_delay_ms", integer(initial_delay_ms)),
        ("max_delay_ms", integer(max_delay_ms)),
        ("delay_ms", integer(delay_ms)),
        ("failure", Json::object(durable_failure)),
      ]),
    )
    session.retry_count = retry
    session.retry_max_retries = Some(max_retries)
    session.retry_initial_delay_ms = Some(initial_delay_ms)
    session.retry_max_delay_ms = Some(max_delay_ms)
    session.pending_retry_id = Some(retry_id)
    Ok(
      object([
        ("scheduled", boolean(true)),
        ("retry_id", Json::string(retry_id)),
        ("retry", integer(retry)),
        ("delay_ms", integer(delay_ms)),
      ]),
    )
  } catch {
    Invalid(message) => Err(message)
  }
}

///|
/// Persist that the wait completed before the host issues the next request.
fn Engine::start_retry_impl(
  self : Engine,
  effect_id : String,
  retry_id : String,
) -> Result[Json, String] {
  try {
    let effect = match self.effects.get(effect_id) {
      Some(effect) => effect
      None => raise Invalid("Unknown or settled provider effect")
    }
    let session = self.lookup(effect.session_id)
    if effect.kind != Llm ||
      session.status != Running ||
      session.active_effect != Some(effect_id) ||
      session.active_kind != Some(Llm) ||
      session.turn_id != effect.turn_id ||
      session.step != effect.step ||
      !session.open_step ||
      session.pending_retry_id != Some(retry_id) {
      raise Invalid("Retry start does not match the pending provider retry")
    }
    session.append(
      "llm/retry-started",
      object([
        ("retry_id", Json::string(retry_id)),
        ("effect_id", Json::string(effect_id)),
        ("turn", integer(session.turn_id)),
        ("step", integer(session.step)),
        ("retry", integer(session.retry_count)),
      ]),
    )
    session.pending_retry_id = None
    Ok(session.json())
  } catch {
    Invalid(message) => Err(message)
  }
}
