///|
/// A deterministic API turn. Measurements belong to this development caller;
/// the product API does not allocate or retain a profiler.
pub fn run(profiler : @hotpath.Profiler) -> Json {
  let api = @api.HarnessApi::new().unwrap()
  profiler.measure("api.session_create", () => {
    api.invoke("session_create", { "id": "perf", "max_steps": 4 }).unwrap()
  })
  |> ignore
  profiler.measure("api.session_send", () => {
    api
    .invoke("session_send", { "session_id": "perf", "prompt": "fixture" })
    .unwrap()
  })
  |> ignore
  let effect = api.take_typed_effects()[0]
  profiler.measure("api.project_effect_stream", () => {
    api.project_effect_stream(effect.id(), "fixed response", "").unwrap()
  })
  |> ignore
  profiler.measure("api.complete_effect", () => {
    api
    .complete_effect(effect.id(), {
      "ok": true,
      "content": "fixed response",
      "tool_calls": [],
      "finish_reason": "stop",
    })
    .unwrap()
  })
  |> ignore
  let result = profiler.measure("api.session_get", () => {
    api.invoke("session_get", { "session_id": "perf" }).unwrap()
  })
  api.close()
  result
}
