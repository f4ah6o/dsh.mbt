///|
/// The JS FFI exports strings and integers only. No host object, credential,
/// filesystem handle, or Promise enters the portable MoonBit runtime.
let current : Ref[@api.HarnessApi?] = Ref(None)

///|
let incarnation : Ref[Int] = Ref(0)

///|
let streams : Map[Int, @provider.StreamDecoder] = Map([])

///|
let next_stream : Ref[Int] = Ref(0)

///|
fn response(result : Result[Json, String]) -> String {
  let value : Json = match result {
    Ok(result) => { "ok": true, "result": result }
    Err(error) => { "ok": false, "error": error.to_json() }
  }
  value.stringify()
}

///|
// Keep a tighter transport bound than core's 1024-level parser default. The
// pinned core exposes this limit through its deprecated optional parameter.
#warnings("-deprecated")
fn parse(raw : String) -> Result[Json, String] {
  if raw.length() > 16_777_216 {
    return Err("JSON input exceeds the 16 MiB character limit")
  }
  Ok(@json.parse(raw, max_nesting_depth=32)) catch {
    _ => Err("invalid JSON input")
  }
}

///|
fn active() -> Result[@api.HarnessApi, String] {
  match current.val {
    Some(api) => Ok(api)
    None => Err("application is not started")
  }
}

///|
#export_name("start")
pub fn start() -> String {
  if current.val is Some(_) {
    return response(Ok(true))
  }
  if incarnation.val >= 2147483646 {
    return response(Err("application lifetime counter exhausted"))
  }
  match @api.HarnessApi::new() {
    Ok(api) => {
      incarnation.val += 1
      current.val = Some(api)
      response(Ok(true))
    }
    Err(error) => response(Err(error))
  }
}

///|
#export_name("stop")
pub fn stop() -> String {
  if current.val is Some(api) {
    api.close()
  }
  current.val = None
  streams.clear()
  response(Ok(true))
}

///|
#export_name("dispatch")
pub fn dispatch(raw : String) -> String {
  let input = match parse(raw) {
    Ok(value) => value
    Err(error) => return response(Err(error))
  }
  let api = match active() {
    Ok(api) => api
    Err(error) => return response(Err(error))
  }
  match input {
    { "operation": String(operation), "input": input, .. } =>
      response(api.invoke(operation, input))
    _ => response(Err("expected {operation: string, input: object}"))
  }
}

///|
#export_name("take_effects")
pub fn take_effects() -> String {
  match active() {
    Ok(api) => {
      let effects = api.take_effects()
      for effect in effects {
        if effect is Object(fields) {
          if fields.get("id") is Some(String(id)) {
            fields["id"] = Json::string(incarnation.val.to_string() + ":" + id)
          }
        }
      }
      Json::array(effects).stringify()
    }
    Err(_) => "[]"
  }
}

///|
#export_name("complete")
pub fn complete(id : String, raw : String) -> String {
  let prefix = incarnation.val.to_string() + ":"
  let internal_id = match id.strip_prefix(prefix) {
    None =>
      return response(Err("effect belongs to a different application lifetime"))
    Some(value) => value.to_owned()
  }
  let result = match parse(raw) {
    Ok(value) => value
    Err(error) => return response(Err(error))
  }
  match active() {
    Ok(api) => response(api.complete(internal_id, result))
    Err(error) => response(Err(error))
  }
}

///|
#export_name("retry_schedule")
pub fn retry_schedule(id : String, raw : String) -> String {
  let prefix = incarnation.val.to_string() + ":"
  let internal_id = match id.strip_prefix(prefix) {
    None =>
      return response(Err("effect belongs to a different application lifetime"))
    Some(value) => value.to_owned()
  }
  let policy = match parse(raw) {
    Ok(value) => value
    Err(error) => return response(Err(error))
  }
  match active() {
    Ok(api) => response(api.schedule_retry(internal_id, policy))
    Err(error) => response(Err(error))
  }
}

///|
#export_name("retry_started")
pub fn retry_started(id : String, retry_id : String) -> String {
  let prefix = incarnation.val.to_string() + ":"
  let internal_id = match id.strip_prefix(prefix) {
    None =>
      return response(Err("effect belongs to a different application lifetime"))
    Some(value) => value.to_owned()
  }
  match active() {
    Ok(api) => response(api.start_retry(internal_id, retry_id))
    Err(error) => response(Err(error))
  }
}

///|
#export_name("stream_project")
pub fn stream_project(
  id : String,
  content : String,
  reasoning : String,
) -> String {
  let prefix = incarnation.val.to_string() + ":"
  let internal_id = match id.strip_prefix(prefix) {
    None =>
      return response(Err("stream belongs to a different application lifetime"))
    Some(value) => value.to_owned()
  }
  match active() {
    Ok(api) => response(api.project_stream(internal_id, content, reasoning))
    Err(error) => response(Err(error))
  }
}

///|
#export_name("snapshot")
pub fn snapshot() -> String {
  match active() {
    Ok(api) => api.snapshot().stringify()
    Err(error) => response(Err(error))
  }
}

///|
#export_name("restore")
pub fn restore(raw : String) -> String {
  let snapshot = match parse(raw) {
    Ok(value) => value
    Err(error) => return response(Err(error))
  }
  match active() {
    Err(error) => response(Err(error))
    Ok(api) =>
      match api.restore(snapshot) {
        Ok(_) => response(Ok(true))
        Err(error) => response(Err(error))
      }
  }
}

///|
#export_name("mcp_handle")
pub fn mcp_handle(line : String) -> String {
  match active() {
    Ok(api) => api.mcp_handle(line).unwrap_or("")
    Err(error) => response(Err(error))
  }
}

///|
#export_name("api_manifest")
pub fn api_manifest() -> String {
  match active() {
    Ok(api) => api.manifest()
    Err(error) => response(Err(error))
  }
}

///|
#export_name("prepare_request")
pub fn prepare_request(mode : String, model : String, raw : String) -> String {
  match parse(raw) {
    Ok(value) => response(@provider.prepare(mode, model, value))
    Err(error) => response(Err(error))
  }
}

///|
#export_name("decode_response")
pub fn decode_response(mode : String, raw : String) -> String {
  match parse(raw) {
    Ok(value) => response(@provider.decode(mode, value))
    Err(error) => response(Err(error))
  }
}

///|
#export_name("stream_start")
pub fn stream_start(mode : String) -> Int {
  if streams.length() >= 128 || next_stream.val >= 2147483646 {
    return -1
  }
  next_stream.val += 1
  let handle = next_stream.val
  streams[handle] = @provider.StreamDecoder::new(mode)
  handle
}

///|
#export_name("stream_feed")
pub fn stream_feed(handle : Int, chunk : String) -> String {
  match streams.get(handle) {
    None => response(Err("unknown stream handle"))
    Some(stream) =>
      match stream.feed(chunk) {
        Ok(_) => response(Ok(true))
        Err(error) => response(Err(error))
      }
  }
}

///|
#export_name("stream_take_deltas")
pub fn stream_take_deltas(handle : Int) -> String {
  match streams.get(handle) {
    None => response(Err("unknown stream handle"))
    Some(stream) => response(Ok(Json::array(stream.take_deltas())))
  }
}

///|
#export_name("stream_finish")
pub fn stream_finish(handle : Int) -> String {
  match streams.get(handle) {
    None => response(Err("unknown stream handle"))
    Some(stream) => {
      streams.remove(handle)
      response(stream.finish())
    }
  }
}

///|
#export_name("stream_abort")
pub fn stream_abort(handle : Int) -> Unit {
  streams.remove(handle)
}

///|
#export_name("render_ui")
pub fn render_ui(raw : String, width : Int, height : Int) -> String {
  match parse(raw) {
    Ok(value) => @ui.render(value, width, height)
    Err(_) => @ui.render(Json::empty_object(), width, height)
  }
}

///|
#export_name("measure_ui")
pub fn measure_ui(raw : String, width : Int) -> Int {
  match parse(raw) {
    Ok(value) => @ui.measure(value, width)
    Err(_) => @ui.measure(Json::empty_object(), width)
  }
}
