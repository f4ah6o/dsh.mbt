///|
fn main {
  let profiler = @hotpath.Profiler::new()
  @trace.run(profiler) |> ignore
  println(profiler.render_text())
}
