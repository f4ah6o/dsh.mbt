///|
fn archive_codec_test_read_schema() -> Json {
  Json::object({
    "type": Json::string("object"),
    "required": Json::array([Json::string("file_path")]),
    "properties": Json::object({
      "file_path": Json::object({ "type": Json::string("string") }),
    }),
    "additionalProperties": Json::boolean(false),
  })
}

///|
fn archive_codec_test_completed_engine(content : String) -> @engine.Engine {
  let engine = @engine.Engine::new([
    Json::object({
      "name": Json::string("read"),
      "description": Json::string("Archive codec fixture"),
      "input_schema": archive_codec_test_read_schema(),
      "effect": Json::string("read"),
    }),
  ])
  ignore(
    engine
    .invoke(
      "session_create",
      Json::object({ "id": Json::string("archive-codec") }),
    )
    .unwrap(),
  )
  ignore(
    engine
    .invoke(
      "session_send",
      Json::object({
        "session_id": Json::string("archive-codec"),
        "prompt": Json::string("Read the file"),
      }),
    )
    .unwrap(),
  )
  let first = engine.take_effects()
  if first.length() != 1 {
    abort("Archive codec fixture expected one initial provider effect")
  }
  ignore(
    engine
    .complete(
      match first[0] {
        Json::Object(fields) =>
          match fields.get("id") {
            Some(Json::String(id)) => id
            _ => abort("Archive codec fixture has no provider effect id")
          }
        _ => abort("Archive codec fixture has no provider effect id")
      },
      Json::object({
        "ok": Json::boolean(true),
        "content": Json::string(""),
        "tool_calls": Json::array([
          Json::object({
            "id": Json::string("archive-codec-call"),
            "name": Json::string("read"),
            "arguments": Json::string("{\"file_path\":\"long.txt\"}"),
          }),
        ]),
        "finish_reason": Json::string("tool_calls"),
      }),
    )
    .unwrap(),
  )
  let read = engine.take_effects()
  if read.length() != 1 {
    abort("Archive codec fixture expected one read effect")
  }
  ignore(
    engine
    .complete(
      match read[0] {
        Json::Object(fields) =>
          match fields.get("id") {
            Some(Json::String(id)) => id
            _ => abort("Archive codec fixture has no read effect id")
          }
        _ => abort("Archive codec fixture has no read effect id")
      },
      Json::object({
        "ok": Json::boolean(true),
        "content": Json::string(content),
      }),
    )
    .unwrap(),
  )
  let followup = engine.take_effects()
  if followup.length() != 1 {
    abort("Archive codec fixture expected one follow-up provider effect")
  }
  ignore(
    engine
    .complete(
      match followup[0] {
        Json::Object(fields) =>
          match fields.get("id") {
            Some(Json::String(id)) => id
            _ => abort("Archive codec fixture has no follow-up effect id")
          }
        _ => abort("Archive codec fixture has no follow-up effect id")
      },
      Json::object({
        "ok": Json::boolean(true),
        "content": Json::string("Read complete"),
        "tool_calls": Json::array([]),
        "finish_reason": Json::string("stop"),
      }),
    )
    .unwrap(),
  )
  engine
}

///|
fn archive_codec_test_result_seq(engine : @engine.Engine) -> Int32 {
  let session = engine
    .invoke(
      "session_get",
      Json::object({ "session_id": Json::string("archive-codec") }),
    )
    .unwrap()
  let events = match session {
    Json::Object(fields) =>
      match fields.get("events").unwrap() {
        Json::Array(values) => values
        _ => abort("Archive codec fixture events are missing")
      }
    _ => abort("Archive codec fixture session is missing")
  }
  for event in events {
    match event {
      Json::Object(fields) if fields.get("type") ==
        Some(Json::string("tool/result")) =>
        match fields.get("seq") {
          Some(Json::Number(seq, ..)) => return seq.to_int()
          _ => abort("Archive codec fixture result sequence is malformed")
        }
      _ => ()
    }
  }
  abort("Archive codec fixture has no tool result")
}

///|
fn archive_codec_test_projection(engine : @engine.Engine) -> String {
  let session = engine
    .invoke(
      "session_get",
      Json::object({ "session_id": Json::string("archive-codec") }),
    )
    .unwrap()
  let events = match session {
    Json::Object(fields) =>
      match fields.get("events").unwrap() {
        Json::Array(values) => values
        _ => abort("Archive codec fixture events are missing")
      }
    _ => abort("Archive codec fixture session is missing")
  }
  for event in events {
    match event {
      Json::Object(event_fields) if event_fields.get("type") ==
        Some(Json::string("tool/result/pruned")) =>
        match event_fields.get("data").unwrap() {
          Json::Object(data) =>
            match data.get("content") {
              Some(Json::String(content)) => return content
              _ => abort("Archive codec fixture prune projection is missing")
            }
          _ => abort("Archive codec fixture prune data is missing")
        }
      _ => ()
    }
  }
  abort("Archive codec fixture has no pruning projection")
}

///|
fn archive_codec_test_candidate(
  content : String,
) -> (
  @engine.Engine,
  @engine.ToolResultArchivePlan,
  String,
  Int32,
  Int32,
  Int32,
) {
  let engine = archive_codec_test_completed_engine(content)
  let threshold = native_tool_archive_codepoint_length(
      NATIVE_TOOL_RESULT_ARCHIVE_PRUNE_MARKER,
    ) +
    7
  let head = 4
  let tail = 3
  let result_seq = archive_codec_test_result_seq(engine)
  if engine.plan_tool_result_archive(
      @engine.SessionId::new("archive-codec").unwrap(),
      result_seq,
    )
    is Ok(_) {
    abort("An unpruned result must be denied by archive preflight")
  }
  ignore(
    engine
    .invoke(
      "session_prune_tool_results",
      Json::object({
        "session_id": Json::string("archive-codec"),
        "threshold_chars": Json::number(threshold.to_double()),
        "head_chars": Json::number(head.to_double()),
        "tail_chars": Json::number(tail.to_double()),
      }),
    )
    .unwrap(),
  )
  let plan = engine
    .plan_tool_result_archive(
      @engine.SessionId::new("archive-codec").unwrap(),
      result_seq,
    )
    .unwrap()
  (engine, plan, archive_codec_test_projection(engine), threshold, head, tail)
}

///|
test "archive object codec preserves Unicode content and emits a content-free reference" {
  let original = "😀e\u{301}xy"[:].repeat(128).to_owned()
  assert_true(@utf8.encode(original).length() < 65536)
  let (engine, plan, projection, threshold, head, tail) = archive_codec_test_candidate(
    original,
  )
  ignore(engine)
  let archive = NativeToolResultArchiveObject::from_unverified_plan_parts(
    plan, original, projection, threshold, head, tail,
  ).unwrap()
  assert_eq(archive.original_content(), original)
  let points = original[:].to_array()
  let expected_projection = StringView::from_array(points[0:head]).to_owned() +
    NATIVE_TOOL_RESULT_ARCHIVE_PRUNE_MARKER +
    StringView::from_array(points[points.length() - tail:points.length()]).to_owned()
  assert_eq(archive.pruned_content(), expected_projection)
  let reference = archive.reference()
  let reference_json = reference.encoded_reference()
  assert_true(!reference_json.contains("😀e"))
  assert_true(reference_json.contains(reference.object_id()))
  let verified = NativeToolResultArchiveObject::verify(
    archive.encoded_object(),
    NativeToolResultArchiveRef::from_json(reference.json()).unwrap(),
  ).unwrap()
  assert_eq(verified.original_content(), original)
  assert_eq(verified.pruned_content(), expected_projection)
}

///|
test "archive object rejects changed content, projection, identity, and truncated input" {
  let original = "private-output-😀".repeat(96)
  let (engine, plan, projection, threshold, head, tail) = archive_codec_test_candidate(
    original,
  )
  ignore(engine)
  let archive = NativeToolResultArchiveObject::from_unverified_plan_parts(
    plan, original, projection, threshold, head, tail,
  ).unwrap()
  let reference = archive.reference()
  let raw = archive.encoded_object()
  assert_true(
    NativeToolResultArchiveObject::verify(
      raw[:raw.length() - 1].to_owned(),
      reference,
    )
    is Err(_),
  )
  let parsed = @json.parse(raw) catch {
    _ => abort("Created archive JSON must parse")
  }
  let original_metadata = match parsed {
    Json::Object(fields) => native_tool_archive_parse_metadata(fields).unwrap()
    _ => abort("Archive object must be an object")
  }
  let source_points = original[:].to_array()
  let changed_source_points = source_points.copy()
  changed_source_points[source_points.length() / 2] = 'Z'
  let changed_source = StringView::from_array(changed_source_points[:]).to_owned()
  assert_eq(changed_source.length(), original.length())
  assert_eq(
    @utf8.encode(changed_source).length(),
    @utf8.encode(original).length(),
  )
  let same_length_tamper = native_tool_archive_object_encoded(
    original_metadata, changed_source, projection, true,
  )
  assert_true(
    NativeToolResultArchiveObject::verify(same_length_tamper, reference)
    is Err(_),
  )
  let changed_fields = match parsed {
    Json::Object(fields) => fields.copy()
    _ => abort("Archive object must be an object")
  }
  changed_fields["content"] = Json::string("other-private-output")
  assert_true(
    NativeToolResultArchiveObject::verify(
      Json::object(changed_fields).stringify(),
      reference,
    )
    is Err(_),
  )
  let changed_projection = match parsed {
    Json::Object(fields) => fields.copy()
    _ => abort("Archive object must be an object")
  }
  changed_projection["pruned_content"] = Json::string("forged projection")
  assert_true(
    NativeToolResultArchiveObject::verify(
      Json::object(changed_projection).stringify(),
      reference,
    )
    is Err(_),
  )
  let wrong_identity_fields = match reference.json() {
    Json::Object(fields) => fields.copy()
    _ => abort("Archive reference must be an object")
  }
  wrong_identity_fields["call_id"] = Json::string("different-call")
  let wrong_identity = NativeToolResultArchiveRef::from_json(
    Json::object(wrong_identity_fields),
  ).unwrap()
  assert_true(
    NativeToolResultArchiveObject::verify(raw, wrong_identity) is Err(_),
  )

  // Recalculate every self-contained digest after changing the projection.
  // The forged object and matching reference are structurally consistent, but
  // exact pruning recomputation must still reject the false projection.
  let forged_projection = projection.replace(old="pruned"[:], new="forged"[:])
  assert_eq(forged_projection.length(), projection.length())
  assert_eq(
    @utf8.encode(forged_projection).length(),
    @utf8.encode(projection).length(),
  )
  let forged_fields = match parsed {
    Json::Object(fields) => fields.copy()
    _ => abort("Archive object must be an object")
  }
  forged_fields["content_sha256"] = Json::string(
    native_tool_archive_sha256(original).unwrap(),
  )
  forged_fields["pruned_content"] = Json::string(forged_projection)
  forged_fields["pruned_sha256"] = Json::string(
    native_tool_archive_sha256(forged_projection).unwrap(),
  )
  let forged_metadata = native_tool_archive_parse_metadata(forged_fields).unwrap()
  let forged_payload = native_tool_archive_object_encoded(
    forged_metadata, original, forged_projection, false,
  )
  let forged_object_id = native_tool_archive_sha256(forged_payload).unwrap()
  let forged_metadata : NativeToolResultArchiveMetadata = {
    ..forged_metadata,
    object_id: forged_object_id,
  }
  let forged_object = native_tool_archive_object_encoded(
    forged_metadata, original, forged_projection, true,
  )
  let forged_reference = NativeToolResultArchiveRef::from_json(
    native_tool_archive_reference_json(forged_metadata),
  ).unwrap()
  assert_true(
    NativeToolResultArchiveObject::verify(forged_object, forged_reference)
    is Err(_),
  )
}

///|
test "archive object and reference reject unknown fields and invalid lengths" {
  let original = "untrusted-fragment-🧭".repeat(96)
  let (engine, plan, projection, threshold, head, tail) = archive_codec_test_candidate(
    original,
  )
  ignore(engine)
  let archive = NativeToolResultArchiveObject::from_unverified_plan_parts(
    plan, original, projection, threshold, head, tail,
  ).unwrap()
  let raw = archive.encoded_object()
  let parsed = @json.parse(raw) catch {
    _ => abort("Created archive JSON must parse")
  }
  let object_fields = match parsed {
    Json::Object(fields) => fields.copy()
    _ => abort("Archive object must be an object")
  }
  object_fields["extra"] = Json::boolean(true)
  assert_true(
    NativeToolResultArchiveObject::verify(
      Json::object(object_fields).stringify(),
      archive.reference(),
    )
    is Err(_),
  )
  let ref_fields = match archive.reference().json() {
    Json::Object(fields) => fields.copy()
    _ => abort("Archive reference must be an object")
  }
  ref_fields["content_bytes"] = Json::number(1.0)
  assert_true(
    NativeToolResultArchiveRef::from_json(Json::object(ref_fields)) is Err(_),
  )
  let ref_extra = match archive.reference().json() {
    Json::Object(fields) => fields.copy()
    _ => abort("Archive reference must be an object")
  }
  ref_extra["content"] = Json::string("must never appear in the reference")
  assert_true(
    NativeToolResultArchiveRef::from_json(Json::object(ref_extra)) is Err(_),
  )
  assert_true(
    NativeToolResultArchiveRef::from_json_text(
      archive
      .reference()
      .encoded_reference()
      .replace(old="{"[:], new="{\"extra\":true,"[:]),
    )
    is Err(_),
  )
}

///|
test "archive constructor rejects a projection or source that disagrees with the candidate" {
  let original = "a longer result 😀".repeat(128)
  let (engine, plan, projection, threshold, head, tail) = archive_codec_test_candidate(
    original,
  )
  ignore(engine)
  assert_true(
    NativeToolResultArchiveObject::from_unverified_plan_parts(
      plan,
      original,
      projection + "tampered",
      threshold,
      head,
      tail,
    )
    is Err(_),
  )
  assert_true(
    NativeToolResultArchiveObject::from_unverified_plan_parts(
      plan, "different source with a different length", projection, threshold, head,
      tail,
    )
    is Err(_),
  )
  assert_true(
    NativeToolResultArchiveObject::from_unverified_plan_parts(
      plan,
      original,
      projection,
      threshold,
      head + 1,
      tail,
    )
    is Err(_),
  )
}

///|
test "archive codec binds exact bytes but plan lengths do not prove source provenance" {
  let original = "private-output-😀".repeat(96)
  let (engine, plan, projection, threshold, head, tail) = archive_codec_test_candidate(
    original,
  )
  let before = engine.snapshot()
  let original_points = original[:].to_array()
  let alternate_points = original_points.copy()
  alternate_points[alternate_points.length() / 2] = 'Z'
  let alternate = StringView::from_array(alternate_points[:]).to_owned()
  assert_eq(alternate.length(), original.length())
  let alternate_projection = native_tool_archive_prune(
    alternate, threshold, head, tail,
  ).unwrap()
  assert_eq(alternate_projection, projection)
  let archive = NativeToolResultArchiveObject::from_unverified_plan_parts(
    plan, alternate, projection, threshold, head, tail,
  ).unwrap()
  assert_eq(
    NativeToolResultArchiveObject::verify(
      archive.encoded_object(),
      archive.reference(),
    )
    .unwrap()
    .original_content(),
    alternate,
  )
  assert_true(engine.take_effects().is_empty())
  assert_eq(engine.snapshot(), before)
}

///|
test "archive codec distinguishes equal projections with different prune policy metadata" {
  let original = "policy-check-😀".repeat(96)
  let (engine, plan, projection, threshold, head, tail) = archive_codec_test_candidate(
    original,
  )
  ignore(engine)
  let first = NativeToolResultArchiveObject::from_unverified_plan_parts(
    plan, original, projection, threshold, head, tail,
  ).unwrap()
  let second = NativeToolResultArchiveObject::from_unverified_plan_parts(
    plan,
    original,
    projection,
    threshold + 1,
    head,
    tail,
  ).unwrap()
  assert_eq(first.pruned_content(), second.pruned_content())
  assert_true(first.reference().object_id() != second.reference().object_id())
  let fields = match second.reference().json() {
    Json::Object(fields) => fields
    _ => abort("Archive reference must be an object")
  }
  assert_eq(
    fields.get("threshold_chars"),
    Some(Json::number((threshold + 1).to_double())),
  )
}

///|
test "archive reference rejects mismatched session effect sequence digest and byte count" {
  let original = "identity-binding-😀".repeat(96)
  let (engine, plan, projection, threshold, head, tail) = archive_codec_test_candidate(
    original,
  )
  ignore(engine)
  let archive = NativeToolResultArchiveObject::from_unverified_plan_parts(
    plan, original, projection, threshold, head, tail,
  ).unwrap()
  let raw = archive.encoded_object()
  let bad_refs : Array[(String, Json)] = []
  for
    (name, value) in [
      ("session_id", Json::string("other-session")),
      ("effect_id", Json::string("effect-999")),
      ("result_seq", Json::number((plan.result_sequence() + 1).to_double())),
      (
        "content_sha256",
        Json::string(
          "0000000000000000000000000000000000000000000000000000000000000000",
        ),
      ),
      (
        "content_bytes",
        Json::number((@utf8.encode(original).length() + 1).to_double()),
      ),
    ] {
    let fields = match archive.reference().json() {
      Json::Object(fields) => fields.copy()
      _ => abort("Archive reference must be an object")
    }
    fields[name] = value
    bad_refs.push((name, Json::object(fields)))
  }
  for (name, forged_json) in bad_refs {
    let forged_reference = match
      NativeToolResultArchiveRef::from_json(forged_json) {
      Ok(value) => value
      Err(_) => abort("Structurally valid forged reference must decode")
    }
    if NativeToolResultArchiveObject::verify(raw, forged_reference) is Ok(_) {
      abort("Archive object must reject a mismatched " + name)
    }
  }
  let sequence_fields = match archive.reference().json() {
    Json::Object(fields) => fields.copy()
    _ => abort("Archive reference must be an object")
  }
  sequence_fields["request_seq"] = Json::number(
    plan.call_sequence().to_double(),
  )
  assert_true(
    NativeToolResultArchiveRef::from_json(Json::object(sequence_fields))
    is Err(_),
  )
}

///|
test "archive wire decoder rejects duplicate fields and alternate number spellings" {
  let original = "wire-form-😀".repeat(96)
  let (engine, plan, projection, threshold, head, tail) = archive_codec_test_candidate(
    original,
  )
  ignore(engine)
  let archive = NativeToolResultArchiveObject::from_unverified_plan_parts(
    plan, original, projection, threshold, head, tail,
  ).unwrap()
  let raw = archive.encoded_object()
  let duplicate = raw.replace(
    old="\"call_id\":\"archive-codec-call\","[:],
    new="\"call_id\":\"archive-codec-call\",\"call_id\":\"archive-codec-call\","[:],
  )
  assert_true(
    NativeToolResultArchiveObject::verify(duplicate, archive.reference())
    is Err(_),
  )
  let alternate_number = raw.replace(
    old="\"format_version\":2,"[:],
    new="\"format_version\":2.0,"[:],
  )
  assert_true(
    NativeToolResultArchiveObject::verify(alternate_number, archive.reference())
    is Err(_),
  )
  let duplicate_ref = archive
    .reference()
    .encoded_reference()
    .replace(
      old="\"call_id\":\"archive-codec-call\","[:],
      new="\"call_id\":\"archive-codec-call\",\"call_id\":\"archive-codec-call\","[:],
    )
  assert_true(
    NativeToolResultArchiveRef::from_json_text(duplicate_ref) is Err(_),
  )
  let alternate_ref_number = archive
    .reference()
    .encoded_reference()
    .replace(old="\"format_version\":2,"[:], new="\"format_version\":2.0,"[:])
  assert_true(
    NativeToolResultArchiveRef::from_json_text(alternate_ref_number) is Err(_),
  )
}

///|
test "archive codec escapes control text and enforces exact UTF-8 byte limits" {
  let escaped = "quote=\" slash=\\ newline=\n tab=\t carriage=\r back=\u{8} form=\u{c} control=\u{1} nul=\u{0}".repeat(
    96,
  )
  let (engine, plan, projection, threshold, head, tail) = archive_codec_test_candidate(
    escaped,
  )
  ignore(engine)
  let escaped_archive = NativeToolResultArchiveObject::from_unverified_plan_parts(
    plan, escaped, projection, threshold, head, tail,
  ).unwrap()
  assert_true(escaped_archive.encoded_object().contains("\\u0001"))
  assert_true(escaped_archive.encoded_object().contains("\\u0000"))
  assert_true(escaped_archive.encoded_object().contains("\\b"))
  assert_true(escaped_archive.encoded_object().contains("\\f"))
  assert_true(escaped_archive.encoded_object().contains("\\r"))
  assert_eq(
    NativeToolResultArchiveObject::verify(
      escaped_archive.encoded_object(),
      escaped_archive.reference(),
    )
    .unwrap()
    .original_content(),
    escaped,
  )
  let exactly_65536 = "😀"[:].repeat(16384).to_owned()
  let (
    exact_engine,
    exact_plan,
    exact_projection,
    exact_threshold,
    exact_head,
    exact_tail,
  ) = archive_codec_test_candidate(exactly_65536)
  ignore(exact_engine)
  assert_eq(@utf8.encode(exactly_65536).length(), 65536)
  assert_true(
    NativeToolResultArchiveObject::from_unverified_plan_parts(
      exact_plan, exactly_65536, exact_projection, exact_threshold, exact_head, exact_tail,
    )
    is Ok(_),
  )
  let over_65536 = exactly_65536 + "x"
  let (
    over_engine,
    over_plan,
    over_projection,
    over_threshold,
    over_head,
    over_tail,
  ) = archive_codec_test_candidate(over_65536)
  ignore(over_engine)
  assert_eq(@utf8.encode(over_65536).length(), 65537)
  assert_true(
    NativeToolResultArchiveObject::from_unverified_plan_parts(
      over_plan, over_65536, over_projection, over_threshold, over_head, over_tail,
    )
    is Err(_),
  )
}
