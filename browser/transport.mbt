///|
#external
priv type BrowserResponse

///|
extern "js" fn browser_fetch(
  path : String,
  http_method : String,
  body : String,
  body_present : Bool,
  cache_mode : String,
  credentials_mode : String,
  accept : String,
  content_type : String,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[BrowserResponse] =
  #| (path, httpMethod, body, bodyPresent, cacheMode, credentialsMode, accept, contentType, signal) => fetch(path, {
  #|   method: httpMethod,
  #|   body: bodyPresent ? body : undefined,
  #|   signal,
  #|   cache: cacheMode,
  #|   credentials: credentialsMode,
  #|   headers: { Accept: accept, ...(contentType ? { "Content-Type": contentType } : {}) },
  #| })

///|
extern "js" fn browser_response_ok(response : BrowserResponse) -> Bool =
  #| (response) => response.ok

///|
extern "js" fn browser_response_status(response : BrowserResponse) -> Int =
  #| (response) => response.status

///|
extern "js" fn browser_response_text(
  response : BrowserResponse,
) -> @js_async.Promise[String] =
  #| (response) => response.text()

///|
extern "js" fn browser_timeout(
  callback : () -> Unit,
  milliseconds : Int,
) -> Int =
  #| (callback, milliseconds) => setTimeout(callback, milliseconds)

///|
extern "js" fn browser_clear_timeout(timer : Int) -> Unit =
  #| (timer) => clearTimeout(timer)

///|
extern "js" fn browser_local_storage_get(key : String) -> String? =
  #| (key) => { try { return localStorage.getItem(key) ?? undefined; } catch { return undefined; } }

///|
extern "js" fn browser_local_storage_set(key : String, value : String) -> Unit =
  #| (key, value) => { try { localStorage.setItem(key, value); } catch {} }

///|
extern "js" fn browser_local_storage_remove(key : String) -> Unit =
  #| (key) => { try { localStorage.removeItem(key); } catch {} }

///|
extern "js" fn browser_now_ms() -> String =
  #| () => String(Date.now())

///|
extern "js" fn browser_entropy_hex() -> String =
  #| () => {
  #|   const bytes = crypto.getRandomValues(new Uint8Array(16));
  #|   return Array.from(bytes, byte => byte.toString(16).padStart(2, "0")).join("");
  #| }

///|
extern "js" fn browser_encode_uri_component(value : String) -> String =
  #| (value) => encodeURIComponent(value)

///|
extern "js" fn browser_event_source_new(url : String) -> BrowserValue =
  #| (url) => new EventSource(url)

///|
extern "js" fn browser_event_source_close(stream : BrowserValue) -> Unit =
  #| (stream) => stream.close()

///|
pub fn browser_event_url(cursor : String, session_id : String) -> String {
  let base = "/api/v1/events?cursor=" + browser_encode_uri_component(cursor)
  if session_id == "" {
    base
  } else {
    base + "&session_id=" + browser_encode_uri_component(session_id)
  }
}

///|
extern "js" fn browser_event_data(event : BrowserValue) -> String =
  #| (event) => String(event?.data ?? "")

///|
extern "js" fn browser_event_last_id(event : BrowserValue) -> String =
  #| (event) => String(event?.lastEventId ?? "")

///|
#warnings("-deprecated")
fn browser_json(raw : String) -> Result[Json, String] {
  let value = @json.parse(raw, max_nesting_depth=32) catch {
    _ => return Err("invalid JSON")
  }
  Ok(value)
}

///|
fn browser_json_field(value : Json, key : String) -> Json? {
  match value {
    Json::Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn browser_json_string(value : Json, key : String) -> String {
  match browser_json_field(value, key) {
    Some(Json::String(text)) => text
    _ => ""
  }
}

///|
fn browser_json_bool(value : Json, key : String) -> Bool {
  match browser_json_field(value, key) {
    Some(Json::True) => true
    _ => false
  }
}
