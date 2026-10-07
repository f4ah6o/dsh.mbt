///|
fn native_responses_fixture() -> String {
  "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_native\",\"status\":\"in_progress\"}}\n\n" +
  "event: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"id\":\"msg_1\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[]}}\n\n" +
  "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg_1\",\"output_index\":0,\"content_index\":0,\"delta\":\"中🌙\"}\n\n" +
  "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_native\",\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"中🌙\"}]}],\"usage\":{\"input_tokens\":2,\"output_tokens\":2,\"total_tokens\":4}}}\n\n"
}

///|
fn native_json_field(value : Json, name : String) -> Json? {
  match value {
    Json::Object(fields) => fields.get(name)
    _ => None
  }
}

///|
fn native_utf8_chunks(bytes : Bytes, cuts : Array[Int]) -> Result[Json, String] {
  let utf8 = Utf8StreamDecoder::new()
  let sse = @provider.ResponsesStreamDecoder::new()
  let boundaries = [0, ..cuts, bytes.length()]
  for index = 0; index + 1 < boundaries.length(); index = index + 1 {
    let chunk = bytes[boundaries[index]:boundaries[index + 1]]
    match utf8.feed(chunk) {
      Err(error) => return Err(error)
      Ok(text) =>
        match sse.feed(text) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
    }
  }
  match utf8.finish() {
    Err(error) => Err(error)
    Ok(_) => sse.finish()
  }
}

///|
test "native byte transport reconstructs UTF-8 split at every boundary" {
  let bytes = @utf8.encode(native_responses_fixture())
  // Every single cut, including cuts inside the three-byte Japanese scalar
  // and four-byte emoji, is decoded before the provider SSE parser sees text.
  for cut = 0; cut <= bytes.length(); cut = cut + 1 {
    let result = native_utf8_chunks(bytes, [cut])
    assert_true(result is Ok(_))
    match result {
      Ok(value) =>
        assert_true(
          native_json_field(value, "content") == Some(Json::string("中🌙")),
        )
      Err(_) => ()
    }
  }
  // Byte-at-a-time transport catches sequences split across several reads.
  let cuts : Array[Int] = []
  for index = 1; index < bytes.length(); index = index + 1 {
    cuts.push(index)
  }
  let bytewise = native_utf8_chunks(bytes, cuts)
  assert_true(bytewise is Ok(_))
  match bytewise {
    Ok(value) =>
      assert_true(
        native_json_field(value, "content") == Some(Json::string("中🌙")),
      )
    Err(_) => ()
  }
}

///|
test "native byte transport rejects malformed and truncated UTF-8" {
  let malformed = Utf8StreamDecoder::new()
  let bad_bytes = Bytes::from_array([b'\xc0', b'\xaf'])
  assert_true(Utf8StreamDecoder::feed(malformed, bad_bytes[:]) is Err(_))
  let truncated = Utf8StreamDecoder::new()
  let partial_bytes = Bytes::from_array([b'\xf0', b'\x9f'])
  assert_true(Utf8StreamDecoder::feed(truncated, partial_bytes[:]) is Ok(_))
  assert_true(truncated.finish() is Err(_))
}
