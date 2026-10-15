///|
test "development measurements wrap a real deterministic API turn" {
  let profiler = @hotpath.Profiler::new()
  let first = @trace.run(profiler)
  assert_eq(first, @trace.run(profiler))
  assert_true(first is { "status": "completed", .. })
  let report = profiler.render_text()
  for
    name in [
      "api.session_create", "api.session_send", "api.project_effect_stream", "api.complete_effect",
      "api.session_get",
    ] {
    assert_true(report.contains(name))
  }
}
