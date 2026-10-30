///|
const ARCHIVE_SHA256_MASK : Int64 = 0xffffffffL

///|
fn archive_sha256_rotr(value : Int64, shift : Int32) -> Int64 {
  ((value >> shift) | (value << (32 - shift))) & ARCHIVE_SHA256_MASK
}

///|
fn archive_sha256_hex_nibble(value : Int32) -> Char {
  let digits = "0123456789abcdef"[:]
  digits[value & 15].to_char().unwrap_or('0')
}

///|
/// Portable SHA-256 used at the engine archive boundary so an opaque source
/// cannot be manufactured from same-length but different content. The runtime
/// archive codec also uses the host system SHA-256 adapter; this independent
/// implementation lets every Engine target verify the canonical payload
/// instead of trusting a native proof type. Keep this helper within the same
/// 1 MiB limit used for encoded archive objects.
fn archive_sha256(value : String) -> String {
  let bytes = @utf8.encode(value)
  let byte_count = bytes.length()
  if byte_count > 1048576 {
    abort("Archive SHA-256 input exceeds its 1 MiB limit")
  }
  let padded_count = (byte_count + 9 + 63) / 64 * 64
  let padded : FixedArray[Byte] = FixedArray::make(padded_count, b'\x00')
  for index = 0; index < byte_count; index = index + 1 {
    padded[index] = bytes[index]
  }
  padded[byte_count] = b'\x80'
  let bit_length = byte_count.to_int64() * 8L
  for index = 0; index < 8; index = index + 1 {
    padded[padded_count - 1 - index] = ((bit_length >> (index * 8)) & 0xffL)
      .to_int()
      .to_byte()
  }

  let constants : Array[Int64] = [
    0x428a2f98L, 0x71374491L, 0xb5c0fbcfL, 0xe9b5dba5L, 0x3956c25bL, 0x59f111f1L,
    0x923f82a4L, 0xab1c5ed5L, 0xd807aa98L, 0x12835b01L, 0x243185beL, 0x550c7dc3L,
    0x72be5d74L, 0x80deb1feL, 0x9bdc06a7L, 0xc19bf174L, 0xe49b69c1L, 0xefbe4786L,
    0x0fc19dc6L, 0x240ca1ccL, 0x2de92c6fL, 0x4a7484aaL, 0x5cb0a9dcL, 0x76f988daL,
    0x983e5152L, 0xa831c66dL, 0xb00327c8L, 0xbf597fc7L, 0xc6e00bf3L, 0xd5a79147L,
    0x06ca6351L, 0x14292967L, 0x27b70a85L, 0x2e1b2138L, 0x4d2c6dfcL, 0x53380d13L,
    0x650a7354L, 0x766a0abbL, 0x81c2c92eL, 0x92722c85L, 0xa2bfe8a1L, 0xa81a664bL,
    0xc24b8b70L, 0xc76c51a3L, 0xd192e819L, 0xd6990624L, 0xf40e3585L, 0x106aa070L,
    0x19a4c116L, 0x1e376c08L, 0x2748774cL, 0x34b0bcb5L, 0x391c0cb3L, 0x4ed8aa4aL,
    0x5b9cca4fL, 0x682e6ff3L, 0x748f82eeL, 0x78a5636fL, 0x84c87814L, 0x8cc70208L,
    0x90befffaL, 0xa4506cebL, 0xbef9a3f7L, 0xc67178f2L,
  ]
  let hash : Array[Int64] = [
    0x6a09e667L, 0xbb67ae85L, 0x3c6ef372L, 0xa54ff53aL, 0x510e527fL, 0x9b05688cL,
    0x1f83d9abL, 0x5be0cd19L,
  ]

  let mut block = 0
  while block < padded_count {
    let words : Array[Int64] = Array::make(64, 0L)
    for index = 0; index < 16; index = index + 1 {
      let offset = block + index * 4
      words[index] = (padded[offset].to_int().to_int64() << 24) |
        (padded[offset + 1].to_int().to_int64() << 16) |
        (padded[offset + 2].to_int().to_int64() << 8) |
        padded[offset + 3].to_int().to_int64()
    }
    for index = 16; index < 64; index = index + 1 {
      let x = words[index - 15]
      let y = words[index - 2]
      let s0 = archive_sha256_rotr(x, 7) ^ archive_sha256_rotr(x, 18) ^ (x >> 3)
      let s1 = archive_sha256_rotr(y, 17) ^
        archive_sha256_rotr(y, 19) ^
        (y >> 10)
      words[index] = (words[index - 16] + s0 + words[index - 7] + s1) &
        ARCHIVE_SHA256_MASK
    }
    let mut a = hash[0]
    let mut b = hash[1]
    let mut c = hash[2]
    let mut d = hash[3]
    let mut e = hash[4]
    let mut f = hash[5]
    let mut g = hash[6]
    let mut h = hash[7]
    for index = 0; index < 64; index = index + 1 {
      let sum1 = archive_sha256_rotr(e, 6) ^
        archive_sha256_rotr(e, 11) ^
        archive_sha256_rotr(e, 25)
      let choice = (e & f) ^ ((e ^ ARCHIVE_SHA256_MASK) & g)
      let temp1 = (h + sum1 + choice + constants[index] + words[index]) &
        ARCHIVE_SHA256_MASK
      let sum0 = archive_sha256_rotr(a, 2) ^
        archive_sha256_rotr(a, 13) ^
        archive_sha256_rotr(a, 22)
      let majority = (a & b) ^ (a & c) ^ (b & c)
      let temp2 = (sum0 + majority) & ARCHIVE_SHA256_MASK
      h = g
      g = f
      f = e
      e = (d + temp1) & ARCHIVE_SHA256_MASK
      d = c
      c = b
      b = a
      a = (temp1 + temp2) & ARCHIVE_SHA256_MASK
    }
    hash[0] = (hash[0] + a) & ARCHIVE_SHA256_MASK
    hash[1] = (hash[1] + b) & ARCHIVE_SHA256_MASK
    hash[2] = (hash[2] + c) & ARCHIVE_SHA256_MASK
    hash[3] = (hash[3] + d) & ARCHIVE_SHA256_MASK
    hash[4] = (hash[4] + e) & ARCHIVE_SHA256_MASK
    hash[5] = (hash[5] + f) & ARCHIVE_SHA256_MASK
    hash[6] = (hash[6] + g) & ARCHIVE_SHA256_MASK
    hash[7] = (hash[7] + h) & ARCHIVE_SHA256_MASK
    block += 64
  }

  let result = StringBuilder()
  for word in hash {
    for shift in [28, 24, 20, 16, 12, 8, 4, 0] {
      result.write_char(
        archive_sha256_hex_nibble(((word >> shift) & 15L).to_int()),
      )
    }
  }
  result.to_string()
}
