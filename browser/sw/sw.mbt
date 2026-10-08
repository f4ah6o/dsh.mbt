///|
#external
priv type SwEvent

///|
#external
priv type SwRequest

///|
#external
priv type SwResponse

///|
#external
priv type SwCache

///|
#external
priv type SwReader

///|
#external
priv type SwChunk

///|
#external
priv type SwClient

///|
priv suberror WorkerFailure {
  WorkerFailure(String)
}

///|
let generation_prefix : String = "dsh-shell-generation-"

///|
let meta_cache_name : String = "dsh-shell-meta-v1"

///|
let staging_prefix : String = "/__dsh_shell_staging__/"

///|
let client_pin_prefix : String = "/__dsh_shell_client__/"

///|
let active_key : String = "/__dsh_shell_active__"

///|
let pending_key : String = "/__dsh_shell_pending__"

///|
let max_shell_asset_bytes : Int = 4 * 1024 * 1024

///|
let max_shell_bundle_bytes : Int = 8 * 1024 * 1024

///|
let text_content_type : String = "text/plain; charset=utf-8"

///|
let shell_fetch_timeout_ms : Int = 10_000

///|
let legacy_cache_names : ReadOnlyArray[String] = [
  "dsh-shell-v1", "dsh-shell-v2",
]

///|
let shell_assets : ReadOnlyArray[String] = [
  "/", "/index.html", "/kumo-standalone.css", "/yami-kumo-components.css", "/yami-kumo-shell.css",
  "/manifest.webmanifest", "/icon.svg", "/moonbit/browser.js",
]

///|
let shell_content_types : ReadOnlyArray[String] = [
  "application/javascript", "application/manifest+json", "image/svg+xml", "text/css",
  "text/html", "text/javascript",
]

///|
let refresh_in_flight : Ref[@js_async.Promise[String?]?] = Ref(None)

///|
let generation_counter : Ref[Int] = Ref(0)

///|
extern "js" fn sw_available() -> Bool =
  #| () => typeof self !== "undefined" && !!self.addEventListener && typeof caches !== "undefined"

///|
extern "js" fn sw_location_origin() -> String =
  #| () => self.location.origin

///|
extern "js" fn sw_add_event_listener(
  event_name : String,
  callback : (SwEvent) -> Unit,
) -> Unit =
  #| (name, callback) => self.addEventListener(name, callback)

///|
extern "js" fn sw_skip_waiting() -> Unit =
  #| () => { void self.skipWaiting(); }

///|
extern "js" fn sw_event_wait_until(
  event : SwEvent,
  promise : @js_async.Promise[Unit],
) -> Unit =
  #| (event, promise) => event.waitUntil(promise)

///|
extern "js" fn sw_event_respond_with(
  event : SwEvent,
  promise : @js_async.Promise[SwResponse],
) -> Unit =
  #| (event, promise) => event.respondWith(promise)

///|
extern "js" fn sw_event_request(event : SwEvent) -> SwRequest =
  #| (event) => event.request

///|
extern "js" fn sw_request_url(request : SwRequest) -> String =
  #| (request) => request.url

///|
extern "js" fn sw_request_method(request : SwRequest) -> String =
  #| (request) => request.method

///|
extern "js" fn sw_request_mode(request : SwRequest) -> String =
  #| (request) => request.mode

///|
extern "js" fn sw_request_has_header(
  request : SwRequest,
  name : String,
) -> Bool =
  #| (request, name) => request.headers.has(name)

///|
extern "js" fn sw_event_client_id(event : SwEvent) -> String =
  #| (event) => event.clientId || ""

///|
extern "js" fn sw_event_resulting_client_id(event : SwEvent) -> String =
  #| (event) => event.resultingClientId || ""

///|
extern "js" fn sw_url_origin(url : String) -> String =
  #| (url) => new URL(url).origin

///|
extern "js" fn sw_url_path(url : String) -> String =
  #| (url) => new URL(url).pathname

///|
extern "js" fn sw_url_search(url : String) -> String =
  #| (url) => new URL(url).search

///|
extern "js" fn sw_encode_component(value : String) -> String =
  #| (value) => encodeURIComponent(value)

///|
extern "js" fn sw_decode_component(value : String) -> String =
  #| (value) => { try { return decodeURIComponent(value); } catch { return ""; } }

///|
extern "js" fn sw_now_ms() -> String =
  #| () => String(Date.now())

///|
extern "js" fn sw_random_suffix() -> String =
  #| () => Math.random().toString(36).slice(2)

///|
fn sw_generation_nonce() -> String {
  sw_now_ms() + "-" + sw_random_suffix()
}

///|
extern "js" fn sw_cache_open(name : String) -> @js_async.Promise[SwCache] =
  #| (name) => caches.open(name)

///|
extern "js" fn sw_cache_names() -> @js_async.Promise[Array[String]] =
  #| () => caches.keys()

///|
extern "js" fn sw_cache_delete(name : String) -> @js_async.Promise[Bool] =
  #| (name) => caches.delete(name)

///|
extern "js" fn sw_cache_match(
  cache : SwCache,
  key : String,
) -> @js_async.Promise[SwResponse] =
  #| (cache, key) => cache.match(key)

///|
extern "js" fn sw_cache_has(
  cache : SwCache,
  key : String,
) -> @js_async.Promise[Bool] =
  #| (cache, key) => cache.match(key).then((response) => !!response)

///|
extern "js" fn sw_cache_put(
  cache : SwCache,
  key : String,
  response : SwResponse,
) -> @js_async.Promise[Unit] =
  #| (cache, key, response) => cache.put(key, response)

///|
extern "js" fn sw_cache_delete_key(
  cache : SwCache,
  key : String,
) -> @js_async.Promise[Bool] =
  #| (cache, key) => cache.delete(key)

///|
extern "js" fn sw_cache_keys(
  cache : SwCache,
) -> @js_async.Promise[Array[SwRequest]] =
  #| (cache) => cache.keys()

///|
extern "js" fn sw_response_text(
  response : SwResponse,
) -> @js_async.Promise[String] =
  #| (response) => response.text()

///|
extern "js" fn sw_text_response(
  value : String,
  content_type : String,
) -> SwResponse =
  #| (value, contentType) => new Response(value, { headers: { "content-type": contentType } })

///|
extern "js" fn sw_text_response_with_status(
  status : Int,
  body : String,
  content_type : String,
) -> SwResponse =
  #| (status, body, contentType) => new Response(body, { status, headers: { "content-type": contentType } })

///|
extern "js" fn sw_response_ok(response : SwResponse) -> Bool =
  #| (response) => response.ok

///|
extern "js" fn sw_response_type(response : SwResponse) -> String =
  #| (response) => response.type

///|
extern "js" fn sw_response_header(
  response : SwResponse,
  name : String,
) -> String =
  #| (response, name) => response.headers.get(name) || ""

///|
extern "js" fn sw_response_url(response : SwResponse) -> String =
  #| (response) => response.url || ""

///|
extern "js" fn sw_response_clone(response : SwResponse) -> SwResponse =
  #| (response) => response.clone()

///|
extern "js" fn sw_response_reader(response : SwResponse) -> SwReader =
  #| (response) => response.body.getReader()

///|
extern "js" fn sw_response_has_body(response : SwResponse) -> Bool =
  #| (response) => !!response.body

///|
extern "js" fn sw_reader_read(reader : SwReader) -> @js_async.Promise[SwChunk] =
  #| (reader) => reader.read()

///|
extern "js" fn sw_chunk_is_done(chunk : SwChunk) -> Bool =
  #| (chunk) => !!chunk.done

///|
extern "js" fn sw_chunk_byte_length(chunk : SwChunk) -> Int =
  #| (chunk) => chunk.value ? chunk.value.byteLength : 0

///|
extern "js" fn sw_reader_cancel(reader : SwReader) -> @js_async.Promise[Unit] =
  #| (reader) => reader.cancel()

///|
extern "js" fn sw_reader_release(reader : SwReader) -> Unit =
  #| (reader) => reader.releaseLock()

///|
extern "js" fn sw_fetch(
  url : String,
  request_method : String,
  cache : String,
  credentials : String,
  mode : String,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[SwResponse] =
  #| (url, requestMethod, cache, credentials, mode, signal) => fetch(url, { method: requestMethod, cache, credentials, mode, signal })

///|
extern "js" fn sw_with_timeout(
  promise : @js_async.Promise[Bool],
  timeout_ms : Int,
  error_message : String,
  on_timeout : () -> Unit,
) -> @js_async.Promise[Bool] =
  #| (promise, timeoutMs, errorMessage, onTimeout) => new Promise((resolve, reject) => {
  #|   const timer = setTimeout(() => { onTimeout(); reject(new Error(errorMessage)); }, timeoutMs);
  #|   promise.then((value) => { clearTimeout(timer); resolve(value); }, (error) => { clearTimeout(timer); reject(error); });
  #| })

///|
extern "js" fn sw_clients_match_all(
  client_type : String,
  include_uncontrolled : Bool,
) -> @js_async.Promise[Array[SwClient]] =
  #| (clientType, includeUncontrolled) => self.clients.matchAll({ type: clientType, includeUncontrolled })

///|
extern "js" fn sw_client_id(client : SwClient) -> String =
  #| (client) => client.id

///|
extern "js" fn sw_clients_claim() -> @js_async.Promise[Unit] =
  #| () => self.clients.claim()

///|
fn shell_cache_key(origin : String, path : String) -> String {
  origin + path
}

///|
fn active_cache_key(origin : String) -> String {
  origin + active_key
}

///|
fn pending_cache_key(origin : String) -> String {
  origin + pending_key
}

///|
fn encoded_metadata_key(
  origin : String,
  prefix : String,
  value : String,
) -> String {
  origin + prefix + sw_encode_component(value)
}

///|
fn is_generation_name(name : String) -> Bool {
  name.has_prefix(generation_prefix) || legacy_cache_names.contains(name)
}

///|
fn parse_nonnegative_length(value : String) -> Int? {
  if value == "" {
    return None
  }
  let mut result = 0
  for character in value {
    if character < '0' || character > '9' {
      return None
    }
    result = result * 10 + character.to_int() - '0'.to_int()
    if result > max_shell_bundle_bytes {
      return Some(result)
    }
  }
  Some(result)
}

///|
fn has_private_cache_directive(value : String) -> Bool {
  for directive in value.to_lower().split(",") {
    let name = directive.split("=").to_array()[0].trim().to_owned()
    if name == "private" {
      return true
    }
  }
  false
}

///|
async fn cancel_shell_body_reader(reader : SwReader) -> Unit {
  ignore(@js_async.Promise::wait(sw_reader_cancel(reader)) catch { _ => () })
}

///|
fn is_cacheable_shell_response(
  request : SwRequest,
  response : SwResponse,
  expected_url : String,
) -> Bool {
  if !sw_response_ok(response) || sw_response_type(response) == "opaque" {
    return false
  }
  if sw_request_has_header(request, "authorization") {
    return false
  }
  let mime = sw_response_header(response, "content-type").split(";").to_array()[0]
    .trim()
    .to_owned()
    .to_lower()
  if !shell_content_types.contains(mime) {
    return false
  }
  let cache_control = sw_response_header(response, "cache-control")
  if has_private_cache_directive(cache_control) ||
    sw_response_header(response, "set-cookie") != "" ||
    sw_response_header(response, "vary").trim() != "" {
    return false
  }
  let response_url = sw_response_url(response)
  response_url == "" || response_url == expected_url
}

///|
async fn consume_bounded_body(
  response : SwResponse,
  bundle_bytes : Ref[Int],
) -> Bool {
  let declared = sw_response_header(response, "content-length")
  if declared != "" {
    match parse_nonnegative_length(declared) {
      None => return false
      Some(length) =>
        if length > max_shell_asset_bytes ||
          length > max_shell_bundle_bytes - bundle_bytes.val {
          return false
        }
    }
  }
  if !sw_response_has_body(response) {
    return true
  }
  let reader = sw_response_reader(response)
  defer sw_reader_release(reader)
  let mut asset_bytes = 0
  while true {
    let chunk = @js_async.Promise::wait(sw_reader_read(reader)) catch {
      _ => {
        cancel_shell_body_reader(reader)
        return false
      }
    }
    if sw_chunk_is_done(chunk) {
      return true
    }
    let chunk_bytes = sw_chunk_byte_length(chunk)
    asset_bytes = asset_bytes + chunk_bytes
    bundle_bytes.val = bundle_bytes.val + chunk_bytes
    if asset_bytes > max_shell_asset_bytes ||
      bundle_bytes.val > max_shell_bundle_bytes {
      cancel_shell_body_reader(reader)
      return false
    }
  }
  false
}

///|
fn delete_generation_after_completion(
  work : @js_async.Promise[Bool],
  generation : String,
) -> Unit {
  ignore(
    @js_async.Promise::from_async(async fn() {
      ignore(@js_async.Promise::wait(work) catch { _ => false })
      ignore(@js_async.Promise::wait(sw_cache_delete(generation)))
    }),
  )
}

///|
async fn fetch_and_cache_shell_asset(
  asset : String,
  cache : SwCache,
  generation : String,
  bundle_bytes : Ref[Int],
) -> Bool {
  let origin = sw_location_origin()
  let expected_url = origin + asset
  let controller = @js_async.AbortController::new()
  let work = @js_async.Promise::from_async(async fn() {
    let request = sw_make_request(
      expected_url, "GET", "no-cache", "same-origin", "same-origin",
    )
    let response = @js_async.Promise::wait(
      sw_fetch(
        expected_url,
        "GET",
        "no-cache",
        "same-origin",
        "same-origin",
        controller.signal(),
      ),
    ) catch {
      _ => return false
    }
    if !is_cacheable_shell_response(request, response, expected_url) {
      return false
    }
    let cached_response = sw_response_clone(response)
    if !consume_bounded_body(response, bundle_bytes) {
      return false
    }
    try {
      @js_async.Promise::wait(
        sw_cache_put(cache, shell_cache_key(origin, asset), cached_response),
      )
      true
    } catch {
      _ => false
    }
  })
  let result = @js_async.Promise::wait(
    sw_with_timeout(
      work,
      shell_fetch_timeout_ms,
      "Timed out fetching shell asset: " + asset,
      () => controller.abort(),
    ),
  ) catch {
    _ => {
      delete_generation_after_completion(work, generation)
      false
    }
  }
  result
}

///|
extern "js" fn sw_make_request(
  url : String,
  request_method : String,
  cache_mode : String,
  credentials_mode : String,
  request_mode : String,
) -> SwRequest =
  #| (url, requestMethod, cacheMode, credentialsMode, requestMode) => new Request(url, { method: requestMethod, cache: cacheMode, credentials: credentialsMode, mode: requestMode })

///|
async fn metadata_cache() -> SwCache {
  @js_async.Promise::wait(sw_cache_open(meta_cache_name))
}

///|
async fn read_metadata(key : String) -> String? {
  let cache = metadata_cache()
  if @js_async.Promise::wait(sw_cache_has(cache, key)) {
    let response = @js_async.Promise::wait(sw_cache_match(cache, key))
    Some(@js_async.Promise::wait(sw_response_text(response)))
  } else {
    None
  }
}

///|
async fn write_metadata(key : String, value : String) -> Bool {
  let cache = metadata_cache()
  try {
    @js_async.Promise::wait(
      sw_cache_put(cache, key, sw_text_response(value, text_content_type)),
    )
    true
  } catch {
    _ => false
  }
}

///|
async fn delete_metadata(key : String) -> Unit {
  let cache = metadata_cache()
  ignore(@js_async.Promise::wait(sw_cache_delete_key(cache, key)))
}

///|
async fn read_active_generation() -> String? {
  let origin = sw_location_origin()
  match read_metadata(active_cache_key(origin)) {
    Some(name) if is_generation_name(name) =>
      if @js_async.Promise::wait(sw_cache_names()).contains(name) {
        Some(name)
      } else {
        None
      }
    _ => None
  }
}

///|
async fn read_client_generation(client_id : String) -> String? {
  if client_id == "" {
    return None
  }
  match
    read_metadata(
      encoded_metadata_key(sw_location_origin(), client_pin_prefix, client_id),
    ) {
    Some(name) if is_generation_name(name) => Some(name)
    _ => None
  }
}

///|
async fn create_shell_generation() -> String? {
  generation_counter.val = generation_counter.val + 1
  let generation = generation_prefix +
    sw_generation_nonce() +
    "-" +
    generation_counter.val.to_string()
  let origin = sw_location_origin()
  let staging_key = encoded_metadata_key(origin, staging_prefix, generation)
  if !write_metadata(staging_key, "1") {
    return None
  }
  let cache = @js_async.Promise::wait(sw_cache_open(generation)) catch {
    _ => {
      delete_metadata(staging_key)
      return None
    }
  }
  let bundle_bytes = Ref(0)
  let mut complete = true
  for asset in shell_assets {
    if !fetch_and_cache_shell_asset(asset, cache, generation, bundle_bytes) {
      complete = false
      break
    }
  }
  if !complete {
    ignore(@js_async.Promise::wait(sw_cache_delete(generation)))
    delete_metadata(staging_key)
    return None
  }
  Some(generation)
}

///|
async fn find_legacy_generation() -> String? {
  let names = @js_async.Promise::wait(sw_cache_names())
  for name in legacy_cache_names {
    if names.contains(name) {
      return Some(name)
    }
  }
  None
}

///|
async fn window_client_ids() -> Array[String] {
  let clients = @js_async.Promise::wait(sw_clients_match_all("window", true))
  let ids = []
  for client in clients {
    ids.push(sw_client_id(client))
  }
  ids
}

///|
async fn clear_generation_staging(generation : String) -> Unit {
  delete_metadata(
    encoded_metadata_key(sw_location_origin(), staging_prefix, generation),
  )
}

///|
async fn stage_for_install() -> Unit {
  match create_shell_generation() {
    None => raise WorkerFailure("Unable to stage a complete offline shell")
    Some(generation) => {
      let written = write_metadata(
        pending_cache_key(sw_location_origin()),
        generation,
      )
      if !written {
        ignore(@js_async.Promise::wait(sw_cache_delete(generation)))
        clear_generation_staging(generation)
        raise WorkerFailure("Unable to record the staged offline shell")
      }
      clear_generation_staging(generation)
    }
  }
}

///|
async fn activate_generation() -> Unit {
  let origin = sw_location_origin()
  let pending_name = read_metadata(pending_cache_key(origin))
  let cache_names = @js_async.Promise::wait(sw_cache_names())
  let pending = match pending_name {
    Some(name) if is_generation_name(name) && cache_names.contains(name) =>
      Some(name)
    _ => None
  }
  let current = match read_active_generation() {
    Some(name) => Some(name)
    None => find_legacy_generation()
  }
  let clients_before_claim = window_client_ids()
  match current {
    Some(generation) =>
      for client_id in clients_before_claim {
        if read_client_generation(client_id) is None {
          ignore(
            write_metadata(
              encoded_metadata_key(origin, client_pin_prefix, client_id),
              generation,
            ),
          )
        }
      }
    None => ()
  }
  let active = match pending {
    Some(name) => Some(name)
    None => current
  }
  match active {
    Some(name) => ignore(write_metadata(active_cache_key(origin), name))
    None => ()
  }
  delete_metadata(pending_cache_key(origin))
  @js_async.Promise::wait(sw_clients_claim())
  cleanup_old_generations(clients_before_claim)
}

///|
async fn cleanup_old_generations(
  additional_live_clients : Array[String],
) -> Unit {
  let origin = sw_location_origin()
  let meta = metadata_cache()
  let live_clients = window_client_ids()
  for client_id in additional_live_clients {
    if !live_clients.contains(client_id) {
      live_clients.push(client_id)
    }
  }
  let retained = []
  match read_active_generation() {
    Some(active) => retained.push(active)
    None => ()
  }
  match read_metadata(pending_cache_key(origin)) {
    Some(pending) if is_generation_name(pending) => retained.push(pending)
    _ => ()
  }
  let metadata_keys = @js_async.Promise::wait(sw_cache_keys(meta))
  for request in metadata_keys {
    let key = sw_request_url(request)
    let path = sw_url_path(key)
    if path.has_prefix(staging_prefix) {
      let encoded = path[staging_prefix.length():].to_owned()
      let generation = sw_decode_component(encoded)
      if is_generation_name(generation) && !retained.contains(generation) {
        retained.push(generation)
      }
    } else if path.has_prefix(client_pin_prefix) {
      let encoded = path[client_pin_prefix.length():].to_owned()
      let client_id = sw_decode_component(encoded)
      let generation = if @js_async.Promise::wait(sw_cache_has(meta, key)) {
        Some(
          @js_async.Promise::wait(
            sw_response_text(@js_async.Promise::wait(sw_cache_match(meta, key))),
          ),
        )
      } else {
        None
      }
      if !live_clients.contains(client_id) {
        ignore(@js_async.Promise::wait(sw_cache_delete_key(meta, key)))
      } else {
        match generation {
          Some(name) if is_generation_name(name) && !retained.contains(name) =>
            retained.push(name)
          _ => ()
        }
      }
    }
  }
  let names = @js_async.Promise::wait(sw_cache_names())
  for name in names {
    if is_generation_name(name) && !retained.contains(name) {
      ignore(@js_async.Promise::wait(sw_cache_delete(name)))
    }
  }
}

///|
async fn refresh_shell_generation_work() -> String? {
  match create_shell_generation() {
    None => None
    Some(candidate) => {
      let switched = write_metadata(
        active_cache_key(sw_location_origin()),
        candidate,
      )
      if !switched {
        ignore(@js_async.Promise::wait(sw_cache_delete(candidate)))
        clear_generation_staging(candidate)
        return None
      }
      clear_generation_staging(candidate)
      Some(candidate)
    }
  }
}

///|
async fn refresh_shell_generation() -> String? {
  let promise : @js_async.Promise[String?] = match refresh_in_flight.val {
    Some(current) => current
    None => {
      let created = @js_async.Promise::from_async(async fn() {
        refresh_shell_generation_work()
      })
      refresh_in_flight.val = Some(created)
      created
    }
  }
  let result = @js_async.Promise::wait(promise) catch { _ => None }
  match refresh_in_flight.val {
    Some(current) if sw_same_promise(current, promise) =>
      refresh_in_flight.val = None
    _ => ()
  }
  match result {
    Some(generation) => Some(generation)
    None => read_active_generation()
  }
}

///|
extern "js" fn sw_same_promise(
  left : @js_async.Promise[String?],
  right : @js_async.Promise[String?],
) -> Bool =
  #| (left, right) => left === right

///|
async fn generation_for_client(client_id : String) -> String? {
  match read_client_generation(client_id) {
    Some(pinned) if @js_async.Promise::wait(sw_cache_names()).contains(pinned) =>
      Some(pinned)
    _ =>
      match read_active_generation() {
        Some(active) => Some(active)
        None => find_legacy_generation()
      }
  }
}

///|
async fn serve_from_generation(
  url : String,
  generation : String?,
) -> SwResponse {
  match generation {
    None =>
      sw_text_response_with_status(
        503, "The app shell is unavailable offline.", text_content_type,
      )
    Some(name) => {
      let cache = @js_async.Promise::wait(sw_cache_open(name))
      if @js_async.Promise::wait(sw_cache_has(cache, url)) {
        @js_async.Promise::wait(sw_cache_match(cache, url))
      } else {
        sw_text_response_with_status(
          503, "The app shell asset is unavailable.", text_content_type,
        )
      }
    }
  }
}

///|
async fn handle_shell_request(event : SwEvent, url : String) -> SwResponse {
  let request = sw_event_request(event)
  let client_id = sw_event_client_id(event)
  let target_client_id = match sw_event_resulting_client_id(event) {
    "" => client_id
    value => value
  }
  let generation = if sw_request_mode(request) == "navigate" {
    let newest = refresh_shell_generation()
    let selected = match newest {
      Some(name) => Some(name)
      None => generation_for_client(client_id)
    }
    match (target_client_id, selected) {
      ("", _) => ()
      (_, Some(name)) =>
        ignore(
          write_metadata(
            encoded_metadata_key(
              sw_location_origin(),
              client_pin_prefix,
              target_client_id,
            ),
            name,
          ),
        )
      (_, None) => ()
    }
    let additional = if target_client_id == "" {
      []
    } else {
      [target_client_id]
    }
    cleanup_old_generations(additional)
    selected
  } else {
    generation_for_client(client_id)
  }
  serve_from_generation(url, generation)
}

///|
fn handle_install_event(event : SwEvent) -> Unit {
  sw_event_wait_until(
    event,
    @js_async.Promise::from_async(async fn() { stage_for_install() }),
  )
  sw_skip_waiting()
}

///|
fn handle_activate_event(event : SwEvent) -> Unit {
  sw_event_wait_until(
    event,
    @js_async.Promise::from_async(async fn() { activate_generation() }),
  )
}

///|
fn handle_fetch_event(event : SwEvent) -> Unit {
  let request = sw_event_request(event)
  if sw_request_method(request) != "GET" ||
    sw_request_has_header(request, "authorization") {
    return
  }
  let request_url = sw_request_url(request)
  let origin = sw_url_origin(request_url)
  if origin != sw_location_origin() {
    return
  }
  let path = sw_url_path(request_url)
  if !shell_assets.contains(path) || sw_url_search(request_url) != "" {
    return
  }
  sw_event_respond_with(
    event,
    @js_async.Promise::from_async(async fn() {
      handle_shell_request(event, origin + path)
    }),
  )
}

///|
#export_name("start_service_worker")
pub fn start_service_worker() -> Bool {
  if !sw_available() {
    return false
  }
  sw_add_event_listener("install", handle_install_event)
  sw_add_event_listener("activate", handle_activate_event)
  sw_add_event_listener("fetch", handle_fetch_event)
  true
}

///|
fn init {
  ignore(start_service_worker())
}
