// Copyright 2026 dsh.mbt contributors. SPDX-License-Identifier: MIT

///|
fn engine_benchmark_one_turn(typed : Bool) -> Json {
  let engine = @engine.Engine::new([])
  let session_id = @engine.SessionId::new("bench-session").unwrap()
  if typed {
    engine
    .apply(
      @engine.EngineCommand::CreateSession(
        Some("bench-session"),
        "Benchmark",
        "You are a test fixture.",
        Some(4),
      ),
    )
    .unwrap()
    |> ignore
    engine
    .apply(
      @engine.EngineCommand::SendPrompt(
        session_id, "Return the fixed fixture response.",
      ),
    )
    .unwrap()
    |> ignore
  } else {
    engine
    .invoke("session_create", {
      "id": "bench-session",
      "title": "Benchmark",
      "system_prompt": "You are a test fixture.",
      "max_steps": 4,
    })
    .unwrap()
    |> ignore
    engine
    .invoke("session_send", {
      "session_id": "bench-session",
      "prompt": "Return the fixed fixture response.",
    })
    .unwrap()
    |> ignore
  }
  let effect = engine.take_typed_effects()[0]
  engine
  .project_effect_stream(effect.id(), "fixed fixture response", "")
  .unwrap()
  |> ignore
  engine
  .complete_effect(effect.id(), {
    "ok": true,
    "content": "fixed fixture response",
    "tool_calls": [],
    "finish_reason": "stop",
  })
  .unwrap()
  |> ignore
  engine.snapshot()
}

///|
test "bench typed engine and compatibility JSON one-turn trace" (it : @bench.T) {
  let typed_snapshot = engine_benchmark_one_turn(true).stringify()
  let compatibility_snapshot = engine_benchmark_one_turn(false).stringify()
  assert_eq(typed_snapshot, compatibility_snapshot)
  it.bench(name="typed-command one-turn trace", fn() {
    it.keep(engine_benchmark_one_turn(true))
  })
  it.bench(name="compatibility-JSON one-turn trace", fn() {
    it.keep(engine_benchmark_one_turn(false))
  })
}
