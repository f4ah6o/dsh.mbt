///|
fn archive_hash_test_reference(
  content : String,
  projection : String,
  object_id : String,
) -> ToolResultArchiveRef {
  let threshold = PRUNE_MARKER[:].char_length() + 4
  let value = Json::object(
    Map::from_array([
      ("schema", Json::string("dsh.tool-result-archive-reference-v2")),
      ("format_version", Json::number(2.0)),
      ("session_id", Json::string("archive-hash")),
      ("call_id", Json::string("archive-call")),
      ("effect_id", Json::string("effect-1")),
      ("call_seq", Json::number(1.0)),
      ("request_seq", Json::number(2.0)),
      ("completed_seq", Json::number(3.0)),
      ("result_seq", Json::number(4.0)),
      ("pruned_seq", Json::number(5.0)),
      (
        "content_bytes",
        Json::number(@utf8.encode(content).length().to_double()),
      ),
      ("chars_before", Json::number(content[:].char_length().to_double())),
      ("content_sha256", Json::string(archive_sha256(content))),
      (
        "pruned_bytes",
        Json::number(@utf8.encode(projection).length().to_double()),
      ),
      ("chars_after", Json::number(projection[:].char_length().to_double())),
      ("pruned_sha256", Json::string(archive_sha256(projection))),
      ("threshold_chars", Json::number(threshold.to_double())),
      ("head_chars", Json::number(2.0)),
      ("tail_chars", Json::number(2.0)),
      ("object_id", Json::string(object_id)),
    ]),
  )
  match ToolResultArchiveRef::from_json(value) {
    Ok(reference) => reference
    Err(error) => abort("Valid archive hash test reference rejected: " + error)
  }
}

///|
test "portable SHA-256 matches standard empty and abc vectors" {
  assert_eq(
    archive_sha256(""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_eq(
    archive_sha256("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

///|
test "portable SHA-256 matches FIPS padding boundaries and Unicode vectors" {
  let vectors : Array[(String, String)] = [
    (
      "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
    ),
    (
      "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
      "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1",
    ),
    (
      "A😀日本語é﻿\u0000\n\u001fZ", "08e38fab2342b85657cdfd503afc5100fd0ccfccc0263280545e0256cb5b01b9",
    ),
    (
      "a".repeat(55),
      "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318",
    ),
    (
      "a".repeat(56),
      "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a",
    ),
    (
      "a".repeat(63),
      "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34",
    ),
    (
      "a".repeat(64),
      "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
    ),
    (
      "a".repeat(65),
      "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0",
    ),
    (
      "a".repeat(119),
      "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb",
    ),
    (
      "a".repeat(120),
      "2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c",
    ),
    (
      "a".repeat(121),
      "e9615320128cc7a3d6078e9af05603188e5ccbf0d07d8b735d3df5e8e0c1281f",
    ),
    (
      "😀"[:].repeat(14).to_owned(),
      "057ae8eade36f1887737614f966005cb521bc9c51dc0f53573b1fa54c1b160bb",
    ),
    (
      "😀"[:].repeat(16).to_owned(),
      "e1e2db96ab0de4009a27bbf9aa2e715a3f2549f77e232dc43ff6a192662ed5e0",
    ),
    (
      "a".repeat(65536),
      "bf718b6f653bebc184e1479f1935b8da974d701b893afcf49e701f3e2f9f9c5a",
    ),
  ]
  for (input, expected) in vectors {
    assert_eq(archive_sha256(input), expected)
  }
}

///|
test "archive source rejects same-length middle tampering despite an unchanged projection" {
  let content = "ab" + "x".repeat(PRUNE_MARKER[:].char_length() + 8) + "yz"
  let threshold = PRUNE_MARKER[:].char_length() + 4
  let config = ToolResultPruneConfig::new(threshold, 2, 2).unwrap()
  let projection = prune_text(content, config).unwrap()
  let initial = archive_hash_test_reference(
    content, projection, "0000000000000000000000000000000000000000000000000000000000000000",
  )
  let content_sha = archive_sha256(content)
  let projection_sha = archive_sha256(projection)
  let payload = native_archive_object_encode(
    initial, content, projection, content_sha, projection_sha, false,
  )
  let object_id = archive_sha256(payload)
  let reference = archive_hash_test_reference(content, projection, object_id)
  let encoded = native_archive_object_encode(
    reference, content, projection, content_sha, projection_sha, true,
  )
  let source = match
    ToolResultArchiveSource::from_object_text(reference, encoded) {
    Ok(value) => value
    Err(error) => abort("Valid archive object rejected: " + error)
  }
  assert_eq(source.content(), content)
  assert_eq(source.pruned_content(), projection)

  let changed = "ab" + "z".repeat(PRUNE_MARKER[:].char_length() + 8) + "yz"
  assert_eq(prune_text(changed, config), Some(projection))
  let forged = native_archive_object_encode(
    reference, changed, projection, content_sha, projection_sha, true,
  )
  assert_true(
    ToolResultArchiveSource::from_object_text(reference, forged) is Err(_),
  )
}
