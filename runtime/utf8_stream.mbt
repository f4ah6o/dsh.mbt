///|
/// Incremental UTF-8 decoding for byte-oriented HTTP readers. The Responses
/// SSE parser accepts strings, so this adapter retains only an incomplete
/// final scalar and never replaces malformed provider bytes.
pub struct Utf8StreamDecoder {
  mut pending : Array[Byte]
  mut closed : Bool
}

///|
pub fn Utf8StreamDecoder::new() -> Utf8StreamDecoder {
  { pending: [], closed: false, }
}

///|
fn utf8_continuation(byte : Byte) -> Bool {
  let value = byte.to_int()
  value >= 0x80 && value <= 0xBF
}

///|
fn decode_utf8_strict(bytes : BytesView) -> Result[String, BytesView] {
  let text = @utf8.decode(bytes) catch {
    @utf8.Malformed(suffix) => return Err(suffix)
  }
  Ok(text)
}

///|
/// Return true only when bytes are a well-formed, incomplete final scalar.
/// Overlong encodings, surrogates, out-of-range code points, and stray
/// continuation bytes are rejected as malformed input.
fn utf8_is_incomplete_tail(bytes : BytesView) -> Bool {
  let len = bytes.length()
  if len <= 0 || len > 3 {
    return false
  }
  let lead = bytes[0].to_int()
  let expected = match lead {
    0xC2..=0xDF => 2
    0xE0..=0xEF => 3
    0xF0..=0xF4 => 4
    _ => return false
  }
  if len >= expected {
    return false
  }
  if len >= 2 {
    let second = bytes[1].to_int()
    let valid_second = match lead {
      0xE0 => second >= 0xA0 && second <= 0xBF
      0xED => second >= 0x80 && second <= 0x9F
      0xF0 => second >= 0x90 && second <= 0xBF
      0xF4 => second >= 0x80 && second <= 0x8F
      _ => second >= 0x80 && second <= 0xBF
    }
    if !valid_second {
      return false
    }
  }
  for index = 2; index < len; index = index + 1 {
    if !utf8_continuation(bytes[index]) {
      return false
    }
  }
  true
}

///|
pub fn Utf8StreamDecoder::feed(
  self : Utf8StreamDecoder,
  bytes : BytesView,
) -> Result[String, String] {
  if self.closed {
    return Err("UTF-8 decoder is closed")
  }
  let all : Array[Byte] = self.pending.copy()
  for byte in bytes {
    all.push(byte)
  }
  let joined = Bytes::from_array(all[:])
  match decode_utf8_strict(joined[:]) {
    Ok(text) => {
      self.pending = []
      Ok(text)
    }
    Err(suffix) => {
      if !utf8_is_incomplete_tail(suffix) {
        return Err("provider response contains malformed UTF-8")
      }
      let valid_len = all.length() - suffix.length()
      let valid = Bytes::from_array(all[:valid_len])
      let prefix = match decode_utf8_strict(valid[:]) {
        Ok(text) => text
        Err(_) => return Err("provider response contains malformed UTF-8")
      }
      self.pending = suffix.to_array()
      Ok(prefix)
    }
  }
}

///|
pub fn Utf8StreamDecoder::finish(
  self : Utf8StreamDecoder,
) -> Result[Unit, String] {
  self.closed = true
  if !self.pending.is_empty() {
    self.pending = []
    Err("provider response ended inside a UTF-8 scalar")
  } else {
    Ok(())
  }
}
