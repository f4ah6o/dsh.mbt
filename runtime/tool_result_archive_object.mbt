///|
/// Versioned, immutable archive object codec for one directly pruned regular
/// Read result. This codec does not publish objects or authorize a stale plan;
/// callers must rederive preflight and read the exact correlated result while
/// holding the runtime mutation gate before using the encoded object.
const NATIVE_TOOL_RESULT_ARCHIVE_OBJECT_SCHEMA : String = "dsh.tool-result-archive-object-v2"

///|
const NATIVE_TOOL_RESULT_ARCHIVE_REFERENCE_SCHEMA : String = "dsh.tool-result-archive-reference-v2"

///|
const NATIVE_TOOL_RESULT_ARCHIVE_FORMAT_VERSION : Int32 = 2

///|
const NATIVE_TOOL_RESULT_ARCHIVE_CONTENT_BYTE_LIMIT : Int32 = 65536

///|
// JSON escaping can expand each source byte, especially for control
// characters. Keep the encoded immutable object bounded independently of the
// native tool's source-output limit.
const NATIVE_TOOL_RESULT_ARCHIVE_OBJECT_BYTE_LIMIT : Int32 = 1048576

///|
const NATIVE_TOOL_RESULT_ARCHIVE_PRUNE_MARKER : String = "\n\n[... tool result middle pruned ...]\n\n"

///|
priv struct NativeToolResultArchiveMetadata {
  session_id : String
  call_id : String
  effect_id : String
  call_seq : Int32
  request_seq : Int32
  completed_seq : Int32
  result_seq : Int32
  pruned_seq : Int32
  content_bytes : Int32
  chars_before : Int32
  content_sha256 : String
  pruned_bytes : Int32
  chars_after : Int32
  pruned_sha256 : String
  threshold_chars : Int32
  head_chars : Int32
  tail_chars : Int32
  object_id : String
}

///|
/// Content-free, structurally validated but untrusted pointer to an archive
/// object. It carries identity/integrity metadata but never result text; object
/// decoding and engine-history provenance are separate checks.
pub struct NativeToolResultArchiveRef {
  priv metadata : NativeToolResultArchiveMetadata
}

///|
/// Decoded archive object. Access to the original and projected text is
/// explicit because both may contain sensitive workspace data. Digests cover
/// UTF-8 re-encoding of these MoonBit strings; they do not prove the bytes of
/// a source file or a disk object read before decoding/BOM handling.
pub struct NativeToolResultArchiveObject {
  priv metadata : NativeToolResultArchiveMetadata
  priv content : String
  priv pruned_content : String
  priv encoded : String
}

///|
fn native_tool_archive_object_fields() -> Array[String] {
  [
    "schema", "format_version", "session_id", "call_id", "effect_id", "call_seq",
    "request_seq", "completed_seq", "result_seq", "pruned_seq", "content", "content_bytes",
    "chars_before", "content_sha256", "pruned_content", "pruned_bytes", "chars_after",
    "pruned_sha256", "threshold_chars", "head_chars", "tail_chars", "object_id",
  ]
}

///|
fn native_tool_archive_reference_fields() -> Array[String] {
  [
    "schema", "format_version", "session_id", "call_id", "effect_id", "call_seq",
    "request_seq", "completed_seq", "result_seq", "pruned_seq", "content_bytes",
    "chars_before", "content_sha256", "pruned_bytes", "chars_after", "pruned_sha256",
    "threshold_chars", "head_chars", "tail_chars", "object_id",
  ]
}

///|
fn native_tool_archive_fields(
  value : Json,
  allowed : Array[String],
) -> Result[Map[String, Json], String] {
  match value {
    Json::Object(fields) => {
      if fields.length() != allowed.length() {
        return Err("archive JSON has missing or unknown fields")
      }
      for name, _ in fields {
        if !allowed.contains(name) {
          return Err("archive JSON has missing or unknown fields")
        }
      }
      for name in allowed {
        if !fields.contains(name) {
          return Err("archive JSON has missing or unknown fields")
        }
      }
      Ok(fields)
    }
    _ => Err("archive JSON must be an object")
  }
}

///|
fn native_tool_archive_string(
  fields : Map[String, Json],
  name : String,
  maximum : Int32,
) -> Result[String, String] {
  match fields.get(name) {
    Some(Json::String(value)) if value.length() <= maximum => Ok(value)
    _ => Err("archive JSON has an invalid string field")
  }
}

///|
fn native_tool_archive_integer(
  fields : Map[String, Json],
  name : String,
  minimum : Int32,
  maximum : Int32,
) -> Result[Int32, String] {
  match fields.get(name) {
    Some(Json::Number(value, ..)) if value >= minimum.to_double() &&
      value <= maximum.to_double() &&
      value.to_int().to_double() == value => Ok(value.to_int())
    _ => Err("archive JSON has an invalid integer field")
  }
}

///|
fn native_tool_archive_codepoint_length(value : String) -> Int32 {
  value[:].char_length()
}

///|
fn native_tool_archive_prune(
  content : String,
  threshold_chars : Int32,
  head_chars : Int32,
  tail_chars : Int32,
) -> Result[String, String] {
  let marker_chars = native_tool_archive_codepoint_length(
    NATIVE_TOOL_RESULT_ARCHIVE_PRUNE_MARKER,
  )
  if threshold_chars <= 0 ||
    head_chars < 0 ||
    tail_chars < 0 ||
    threshold_chars > 262144 ||
    head_chars > 262144 ||
    tail_chars > 262144 ||
    head_chars + marker_chars + tail_chars > threshold_chars {
    return Err("archive pruning budget is invalid")
  }
  let points = content[:].to_array()
  if points.length() <= threshold_chars {
    return Err("archive source is not above its pruning threshold")
  }
  let tail_start = points.length() - tail_chars
  if head_chars > tail_start {
    return Err("archive pruning ranges overlap")
  }
  let head = StringView::from_array(points[0:head_chars]).to_owned()
  let tail = StringView::from_array(points[tail_start:points.length()]).to_owned()
  Ok(head + NATIVE_TOOL_RESULT_ARCHIVE_PRUNE_MARKER + tail)
}

///|
fn native_tool_archive_validate_sequence_order(
  metadata : NativeToolResultArchiveMetadata,
) -> Result[Unit, String] {
  if metadata.call_seq < 0 ||
    metadata.request_seq <= metadata.call_seq ||
    metadata.completed_seq <= metadata.request_seq ||
    metadata.result_seq <= metadata.completed_seq ||
    metadata.pruned_seq <= metadata.result_seq ||
    metadata.pruned_seq >= 32768 {
    return Err("archive event identities are not strictly ordered")
  }
  Ok(())
}

///|
fn native_tool_archive_validate_metadata(
  metadata : NativeToolResultArchiveMetadata,
) -> Result[Unit, String] {
  if @engine.SessionId::new(metadata.session_id) is Err(_) ||
    @engine.ToolCallId::new(metadata.call_id) is Err(_) ||
    @engine.EffectId::new(metadata.effect_id) is Err(_) {
    return Err("archive identity metadata is invalid")
  }
  match native_tool_archive_validate_sequence_order(metadata) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if metadata.content_bytes <= 0 ||
    metadata.content_bytes > NATIVE_TOOL_RESULT_ARCHIVE_CONTENT_BYTE_LIMIT ||
    metadata.chars_before <= 0 ||
    metadata.chars_before > metadata.content_bytes ||
    metadata.pruned_bytes <= 0 ||
    metadata.pruned_bytes > NATIVE_TOOL_RESULT_ARCHIVE_CONTENT_BYTE_LIMIT ||
    metadata.chars_after <= 0 ||
    metadata.chars_after >= metadata.chars_before ||
    metadata.chars_after > metadata.pruned_bytes ||
    metadata.threshold_chars <= 0 ||
    metadata.threshold_chars > 262144 ||
    metadata.head_chars < 0 ||
    metadata.tail_chars < 0 ||
    metadata.head_chars +
    native_tool_archive_codepoint_length(
      NATIVE_TOOL_RESULT_ARCHIVE_PRUNE_MARKER,
    ) +
    metadata.tail_chars >
    metadata.threshold_chars ||
    metadata.chars_before <= metadata.threshold_chars ||
    metadata.chars_after !=
    metadata.head_chars +
    native_tool_archive_codepoint_length(
      NATIVE_TOOL_RESULT_ARCHIVE_PRUNE_MARKER,
    ) +
    metadata.tail_chars {
    return Err("archive content lengths or pruning metadata are invalid")
  }
  if !native_mcp_valid_fingerprint(metadata.content_sha256) ||
    !native_mcp_valid_fingerprint(metadata.pruned_sha256) ||
    !native_mcp_valid_fingerprint(metadata.object_id) {
    return Err("archive digest metadata is invalid")
  }
  Ok(())
}

///|
fn native_tool_archive_metadata_fields(
  metadata : NativeToolResultArchiveMetadata,
  schema : String,
  include_object_id : Bool,
) -> Map[String, Json] {
  let fields : Map[String, Json] = {
    "schema": Json::string(schema),
    "format_version": Json::number(
      NATIVE_TOOL_RESULT_ARCHIVE_FORMAT_VERSION.to_double(),
    ),
    "session_id": Json::string(metadata.session_id),
    "call_id": Json::string(metadata.call_id),
    "effect_id": Json::string(metadata.effect_id),
    "call_seq": Json::number(metadata.call_seq.to_double()),
    "request_seq": Json::number(metadata.request_seq.to_double()),
    "completed_seq": Json::number(metadata.completed_seq.to_double()),
    "result_seq": Json::number(metadata.result_seq.to_double()),
    "pruned_seq": Json::number(metadata.pruned_seq.to_double()),
    "content_bytes": Json::number(metadata.content_bytes.to_double()),
    "chars_before": Json::number(metadata.chars_before.to_double()),
    "content_sha256": Json::string(metadata.content_sha256),
    "pruned_bytes": Json::number(metadata.pruned_bytes.to_double()),
    "chars_after": Json::number(metadata.chars_after.to_double()),
    "pruned_sha256": Json::string(metadata.pruned_sha256),
    "threshold_chars": Json::number(metadata.threshold_chars.to_double()),
    "head_chars": Json::number(metadata.head_chars.to_double()),
    "tail_chars": Json::number(metadata.tail_chars.to_double()),
  }
  if include_object_id {
    fields["object_id"] = Json::string(metadata.object_id)
  }
  fields
}

///|
fn native_tool_archive_hex_byte(value : Int32) -> String {
  let digits = "0123456789abcdef"[:]
  let output = StringBuilder()
  output.write_char(digits[(value >> 4) & 15].to_char().unwrap_or('0'))
  output.write_char(digits[value & 15].to_char().unwrap_or('0'))
  output.to_string()
}

///|
// Hashes bind to these exact versioned bytes. Fixed field order, integer-only
// numeric fields, and deterministic string escaping avoid generic Json object
// ordering and number formatting.
fn native_tool_archive_quote(value : String) -> String {
  let output = StringBuilder()
  output.write_char('"')
  for character in value {
    match character {
      '"' => output.write_string("\\\"")
      '\\' => output.write_string("\\\\")
      '\b' => output.write_string("\\b")
      '\t' => output.write_string("\\t")
      '\n' => output.write_string("\\n")
      '\f' => output.write_string("\\f")
      '\r' => output.write_string("\\r")
      _ if character.to_int() < 0x20 =>
        output.write_string(
          "\\u00" + native_tool_archive_hex_byte(character.to_int()),
        )
      _ => output.write_char(character)
    }
  }
  output.write_char('"')
  output.to_string()
}

///|
fn native_tool_archive_encode_entries(
  entries : Array[(String, Json)],
) -> String {
  let output = StringBuilder()
  output.write_char('{')
  for index, (name, value) in entries {
    if index > 0 {
      output.write_char(',')
    }
    output.write_string(native_tool_archive_quote(name))
    output.write_char(':')
    match value {
      Json::String(text) => output.write_string(native_tool_archive_quote(text))
      Json::Number(number, ..) =>
        output.write_string(number.to_int().to_string())
      _ => abort("Archive codec contains an unsupported JSON value")
    }
  }
  output.write_char('}')
  output.to_string()
}

///|
fn native_tool_archive_metadata_entries(
  metadata : NativeToolResultArchiveMetadata,
  schema : String,
) -> Array[(String, Json)] {
  [
    ("schema", Json::string(schema)),
    (
      "format_version",
      Json::number(NATIVE_TOOL_RESULT_ARCHIVE_FORMAT_VERSION.to_double()),
    ),
    ("session_id", Json::string(metadata.session_id)),
    ("call_id", Json::string(metadata.call_id)),
    ("effect_id", Json::string(metadata.effect_id)),
    ("call_seq", Json::number(metadata.call_seq.to_double())),
    ("request_seq", Json::number(metadata.request_seq.to_double())),
    ("completed_seq", Json::number(metadata.completed_seq.to_double())),
    ("result_seq", Json::number(metadata.result_seq.to_double())),
    ("pruned_seq", Json::number(metadata.pruned_seq.to_double())),
    ("content_bytes", Json::number(metadata.content_bytes.to_double())),
    ("chars_before", Json::number(metadata.chars_before.to_double())),
    ("content_sha256", Json::string(metadata.content_sha256)),
    ("pruned_bytes", Json::number(metadata.pruned_bytes.to_double())),
    ("chars_after", Json::number(metadata.chars_after.to_double())),
    ("pruned_sha256", Json::string(metadata.pruned_sha256)),
    ("threshold_chars", Json::number(metadata.threshold_chars.to_double())),
    ("head_chars", Json::number(metadata.head_chars.to_double())),
    ("tail_chars", Json::number(metadata.tail_chars.to_double())),
  ]
}

///|
fn native_tool_archive_object_encoded(
  metadata : NativeToolResultArchiveMetadata,
  content : String,
  pruned_content : String,
  include_object_id : Bool,
) -> String {
  let entries : Array[(String, Json)] = [
    ("schema", Json::string(NATIVE_TOOL_RESULT_ARCHIVE_OBJECT_SCHEMA)),
    (
      "format_version",
      Json::number(NATIVE_TOOL_RESULT_ARCHIVE_FORMAT_VERSION.to_double()),
    ),
    ("session_id", Json::string(metadata.session_id)),
    ("call_id", Json::string(metadata.call_id)),
    ("effect_id", Json::string(metadata.effect_id)),
    ("call_seq", Json::number(metadata.call_seq.to_double())),
    ("request_seq", Json::number(metadata.request_seq.to_double())),
    ("completed_seq", Json::number(metadata.completed_seq.to_double())),
    ("result_seq", Json::number(metadata.result_seq.to_double())),
    ("pruned_seq", Json::number(metadata.pruned_seq.to_double())),
    ("content", Json::string(content)),
    ("content_bytes", Json::number(metadata.content_bytes.to_double())),
    ("chars_before", Json::number(metadata.chars_before.to_double())),
    ("content_sha256", Json::string(metadata.content_sha256)),
    ("pruned_content", Json::string(pruned_content)),
    ("pruned_bytes", Json::number(metadata.pruned_bytes.to_double())),
    ("chars_after", Json::number(metadata.chars_after.to_double())),
    ("pruned_sha256", Json::string(metadata.pruned_sha256)),
    ("threshold_chars", Json::number(metadata.threshold_chars.to_double())),
    ("head_chars", Json::number(metadata.head_chars.to_double())),
    ("tail_chars", Json::number(metadata.tail_chars.to_double())),
  ]
  if include_object_id {
    entries.push(("object_id", Json::string(metadata.object_id)))
  }
  native_tool_archive_encode_entries(entries)
}

///|
fn native_tool_archive_reference_encoded(
  metadata : NativeToolResultArchiveMetadata,
) -> String {
  let entries = native_tool_archive_metadata_entries(
    metadata,
    NATIVE_TOOL_RESULT_ARCHIVE_REFERENCE_SCHEMA,
  )
  entries.push(("object_id", Json::string(metadata.object_id)))
  native_tool_archive_encode_entries(entries)
}

///|
fn native_tool_archive_reference_json(
  metadata : NativeToolResultArchiveMetadata,
) -> Json {
  Json::object(
    native_tool_archive_metadata_fields(
      metadata,
      NATIVE_TOOL_RESULT_ARCHIVE_REFERENCE_SCHEMA,
      true,
    ),
  )
}

///|
fn native_tool_archive_parse_metadata(
  fields : Map[String, Json],
) -> Result[NativeToolResultArchiveMetadata, String] {
  let schema = match fields.get("schema") {
    Some(Json::String(value)) => value
    _ => return Err("archive schema is missing")
  }
  if schema != NATIVE_TOOL_RESULT_ARCHIVE_OBJECT_SCHEMA &&
    schema != NATIVE_TOOL_RESULT_ARCHIVE_REFERENCE_SCHEMA {
    return Err("archive schema is unsupported")
  }
  let version = match
    native_tool_archive_integer(fields, "format_version", 2, 2) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if version != NATIVE_TOOL_RESULT_ARCHIVE_FORMAT_VERSION {
    return Err("archive format version is unsupported")
  }
  let session_id = match native_tool_archive_string(fields, "session_id", 128) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let call_id = match native_tool_archive_string(fields, "call_id", 128) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let effect_id = match native_tool_archive_string(fields, "effect_id", 128) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let call_seq = match
    native_tool_archive_integer(fields, "call_seq", 0, 32767) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let request_seq = match
    native_tool_archive_integer(fields, "request_seq", 0, 32767) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let completed_seq = match
    native_tool_archive_integer(fields, "completed_seq", 0, 32767) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let result_seq = match
    native_tool_archive_integer(fields, "result_seq", 0, 32767) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let pruned_seq = match
    native_tool_archive_integer(fields, "pruned_seq", 0, 32767) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let content_bytes = match
    native_tool_archive_integer(
      fields,
      "content_bytes",
      0,
      NATIVE_TOOL_RESULT_ARCHIVE_CONTENT_BYTE_LIMIT,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let chars_before = match
    native_tool_archive_integer(fields, "chars_before", 0, 262144) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let content_sha256 = match
    native_tool_archive_string(fields, "content_sha256", 64) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let pruned_bytes = match
    native_tool_archive_integer(
      fields,
      "pruned_bytes",
      0,
      NATIVE_TOOL_RESULT_ARCHIVE_CONTENT_BYTE_LIMIT,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let chars_after = match
    native_tool_archive_integer(fields, "chars_after", 0, 262144) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let pruned_sha256 = match
    native_tool_archive_string(fields, "pruned_sha256", 64) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let threshold_chars = match
    native_tool_archive_integer(fields, "threshold_chars", 0, 262144) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let head_chars = match
    native_tool_archive_integer(fields, "head_chars", 0, 262144) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let tail_chars = match
    native_tool_archive_integer(fields, "tail_chars", 0, 262144) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let object_id = match native_tool_archive_string(fields, "object_id", 64) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let metadata : NativeToolResultArchiveMetadata = {
    session_id,
    call_id,
    effect_id,
    call_seq,
    request_seq,
    completed_seq,
    result_seq,
    pruned_seq,
    content_bytes,
    chars_before,
    content_sha256,
    pruned_bytes,
    chars_after,
    pruned_sha256,
    threshold_chars,
    head_chars,
    tail_chars,
    object_id,
  }
  match native_tool_archive_validate_metadata(metadata) {
    Err(error) => Err(error)
    Ok(_) => Ok(metadata)
  }
}

///|
#warnings("-deprecated")
fn native_tool_archive_parse_json(
  raw : String,
  maximum_bytes : Int32,
) -> Result[Json, String] {
  if @utf8.encode(raw).length() > maximum_bytes {
    return Err("archive JSON exceeds its byte limit")
  }
  let value = @json.parse(raw, max_nesting_depth=4) catch {
    _ => return Err("archive JSON is malformed")
  }
  Ok(value)
}

///|
fn native_tool_archive_sha256(value : String) -> Result[String, String] {
  // Use the host's existing system SHA-256 adapter. In particular, a failed
  // digest operation stays an error and can never be treated as a match.
  native_mcp_sha256_hex(value)
}

///|
fn native_tool_archive_reference_from_metadata(
  metadata : NativeToolResultArchiveMetadata,
) -> NativeToolResultArchiveRef {
  { metadata, }
}

///|
/// Parse a content-free reference with exact fields and v2 wire encoding.
pub fn NativeToolResultArchiveRef::from_json_text(
  raw : String,
) -> Result[NativeToolResultArchiveRef, String] {
  let value = match native_tool_archive_parse_json(raw, 8192) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let fields = match
    native_tool_archive_fields(value, native_tool_archive_reference_fields()) {
    Ok(fields) => fields
    Err(error) => return Err(error)
  }
  if fields.get("schema") !=
    Some(Json::string(NATIVE_TOOL_RESULT_ARCHIVE_REFERENCE_SCHEMA)) {
    return Err("archive reference schema is unsupported")
  }
  let metadata = match native_tool_archive_parse_metadata(fields) {
    Ok(metadata) => metadata
    Err(error) => return Err(error)
  }
  if native_tool_archive_reference_encoded(metadata) != raw {
    return Err("archive reference encoding is not canonical for v2")
  }
  Ok(native_tool_archive_reference_from_metadata(metadata))
}

///|
/// Decode a reference value after enforcing its exact field set. Call
/// `from_json_text` at the storage boundary when duplicate keys or alternate
/// encodings must also be rejected.
pub fn NativeToolResultArchiveRef::from_json(
  value : Json,
) -> Result[NativeToolResultArchiveRef, String] {
  let fields = match
    native_tool_archive_fields(value, native_tool_archive_reference_fields()) {
    Ok(fields) => fields
    Err(error) => return Err(error)
  }
  if fields.get("schema") !=
    Some(Json::string(NATIVE_TOOL_RESULT_ARCHIVE_REFERENCE_SCHEMA)) {
    return Err("archive reference schema is unsupported")
  }
  match native_tool_archive_parse_metadata(fields) {
    Ok(metadata) => Ok(native_tool_archive_reference_from_metadata(metadata))
    Err(error) => Err(error)
  }
}

///|
/// Return the content-free JSON pointer. This value contains no archived
/// content and is safe to place in a future session manifest.
pub fn NativeToolResultArchiveRef::json(
  self : NativeToolResultArchiveRef,
) -> Json {
  native_tool_archive_reference_json(self.metadata)
}

///|
/// Return the v2 fixed-order reference encoding, which contains no result
/// content. Use this form for byte-level strict decode checks.
pub fn NativeToolResultArchiveRef::encoded_reference(
  self : NativeToolResultArchiveRef,
) -> String {
  native_tool_archive_reference_encoded(self.metadata)
}

///|
/// Get the immutable object name digest. The host must still validate the
/// object against this full reference before returning its content.
pub fn NativeToolResultArchiveRef::object_id(
  self : NativeToolResultArchiveRef,
) -> String {
  self.metadata.object_id
}

///|
/// Encode caller-supplied parts that are checked against the plan's identity,
/// sequence, and length metadata. The plan contains lengths but no source text,
/// digest, or freshness revision; this constructor cannot prove that `content`
/// came from the correlated engine event. Host integration must acquire the
/// event content and rederive preflight under its mutation gate before use.
pub fn NativeToolResultArchiveObject::from_unverified_plan_parts(
  plan : @engine.ToolResultArchivePlan,
  content : String,
  pruned_content : String,
  threshold_chars : Int32,
  head_chars : Int32,
  tail_chars : Int32,
) -> Result[NativeToolResultArchiveObject, String] {
  let content_bytes = @utf8.encode(content).length()
  let pruned_bytes = @utf8.encode(pruned_content).length()
  if content_bytes <= 0 ||
    content_bytes > NATIVE_TOOL_RESULT_ARCHIVE_CONTENT_BYTE_LIMIT ||
    pruned_bytes <= 0 ||
    pruned_bytes > NATIVE_TOOL_RESULT_ARCHIVE_CONTENT_BYTE_LIMIT {
    return Err("archive source or projection exceeds its byte limit")
  }
  let chars_before = native_tool_archive_codepoint_length(content)
  let chars_after = native_tool_archive_codepoint_length(pruned_content)
  if chars_before != plan.chars_before() || chars_after != plan.chars_after() {
    return Err("archive source lengths disagree with the preflight plan")
  }
  let expected_projection = match
    native_tool_archive_prune(content, threshold_chars, head_chars, tail_chars) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if expected_projection != pruned_content {
    return Err("archive projection does not match the source pruning rule")
  }
  let content_sha256 = match native_tool_archive_sha256(content) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let pruned_sha256 = match native_tool_archive_sha256(pruned_content) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let metadata : NativeToolResultArchiveMetadata = {
    session_id: plan.session_id().as_string(),
    call_id: plan.call_id().as_string(),
    effect_id: plan.effect_id().as_string(),
    call_seq: plan.call_sequence(),
    request_seq: plan.request_sequence(),
    completed_seq: plan.completed_sequence(),
    result_seq: plan.result_sequence(),
    pruned_seq: plan.pruned_sequence(),
    content_bytes,
    chars_before,
    content_sha256,
    pruned_bytes,
    chars_after,
    pruned_sha256,
    threshold_chars,
    head_chars,
    tail_chars,
    // A temporary syntactically valid digest lets the common metadata checker
    // validate all other fields before the payload digest is computed.
    object_id: "0000000000000000000000000000000000000000000000000000000000000000",
  }
  match native_tool_archive_validate_metadata(metadata) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let payload = native_tool_archive_object_encoded(
    metadata, content, pruned_content, false,
  )
  let object_id = match native_tool_archive_sha256(payload) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let metadata : NativeToolResultArchiveMetadata = { ..metadata, object_id, }
  let encoded = native_tool_archive_object_encoded(
    metadata, content, pruned_content, true,
  )
  if @utf8.encode(encoded).length() >
    NATIVE_TOOL_RESULT_ARCHIVE_OBJECT_BYTE_LIMIT {
    return Err("archive object exceeds its encoded byte limit")
  }
  let reference = native_tool_archive_reference_from_metadata(metadata)
  NativeToolResultArchiveObject::verify(encoded, reference)
}

///|
/// Strictly decode one object and prove that its exact identity, content,
/// lengths, hashes, and prune projection match the supplied structurally valid
/// reference. This does not prove that either value belongs in a session's
/// engine history, nor that UTF-8 re-encoding reproduces any source file bytes
/// that were decoded or BOM-normalized before the tool result was created.
/// This codec alone must not be used as an object-adoption decision.
pub fn NativeToolResultArchiveObject::verify(
  raw : String,
  reference : NativeToolResultArchiveRef,
) -> Result[NativeToolResultArchiveObject, String] {
  let value = match
    native_tool_archive_parse_json(
      raw,
      NATIVE_TOOL_RESULT_ARCHIVE_OBJECT_BYTE_LIMIT,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let fields = match
    native_tool_archive_fields(value, native_tool_archive_object_fields()) {
    Ok(fields) => fields
    Err(error) => return Err(error)
  }
  if fields.get("schema") !=
    Some(Json::string(NATIVE_TOOL_RESULT_ARCHIVE_OBJECT_SCHEMA)) {
    return Err("archive object schema is unsupported")
  }
  let metadata = match native_tool_archive_parse_metadata(fields) {
    Ok(metadata) => metadata
    Err(error) => return Err(error)
  }
  let fields = match
    native_tool_archive_fields(value, native_tool_archive_object_fields()) {
    Ok(fields) => fields
    Err(error) => return Err(error)
  }
  let content = match
    native_tool_archive_string(
      fields,
      "content",
      NATIVE_TOOL_RESULT_ARCHIVE_CONTENT_BYTE_LIMIT,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let pruned_content = match
    native_tool_archive_string(
      fields,
      "pruned_content",
      NATIVE_TOOL_RESULT_ARCHIVE_CONTENT_BYTE_LIMIT,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if native_tool_archive_reference_encoded(metadata) !=
    native_tool_archive_reference_encoded(reference.metadata) {
    return Err("archive object identity does not match its reference")
  }
  if native_tool_archive_object_encoded(metadata, content, pruned_content, true) !=
    raw {
    return Err("archive object encoding is not canonical for v2")
  }
  if @utf8.encode(content).length() != metadata.content_bytes ||
    native_tool_archive_codepoint_length(content) != metadata.chars_before ||
    @utf8.encode(pruned_content).length() != metadata.pruned_bytes ||
    native_tool_archive_codepoint_length(pruned_content) != metadata.chars_after {
    return Err("archive object content lengths do not match metadata")
  }
  let content_sha256 = match native_tool_archive_sha256(content) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let pruned_sha256 = match native_tool_archive_sha256(pruned_content) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if content_sha256 != metadata.content_sha256 ||
    pruned_sha256 != metadata.pruned_sha256 {
    return Err("archive object content digest does not match metadata")
  }
  let expected_projection = match
    native_tool_archive_prune(
      content,
      metadata.threshold_chars,
      metadata.head_chars,
      metadata.tail_chars,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if expected_projection != pruned_content {
    return Err("archive object projection does not match pruning metadata")
  }
  let payload = native_tool_archive_object_encoded(
    metadata, content, pruned_content, false,
  )
  let object_id = match native_tool_archive_sha256(payload) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if object_id != metadata.object_id {
    return Err("archive object identity digest does not match its content")
  }
  Ok({ metadata, content, pruned_content, encoded: raw, })
}

///|
/// Serialize the immutable object for a bounded host store. This contains the
/// full original result and must be treated as sensitive workspace content.
pub fn NativeToolResultArchiveObject::encoded_object(
  self : NativeToolResultArchiveObject,
) -> String {
  self.encoded
}

///|
/// Return the content-free pointer for a future manifest.
pub fn NativeToolResultArchiveObject::reference(
  self : NativeToolResultArchiveObject,
) -> NativeToolResultArchiveRef {
  native_tool_archive_reference_from_metadata(self.metadata)
}

///|
/// Explicitly retrieve the original tool output after object verification.
pub fn NativeToolResultArchiveObject::original_content(
  self : NativeToolResultArchiveObject,
) -> String {
  self.content
}

///|
/// Explicitly retrieve the validated provider-facing pruning projection.
pub fn NativeToolResultArchiveObject::pruned_content(
  self : NativeToolResultArchiveObject,
) -> String {
  self.pruned_content
}
