// Copyright 2026 dsh.mbt contributors. SPDX-License-Identifier: MIT

///|
/// Calculate the deterministic exponential delay for a retry, bounded by the
/// configured ceiling. The engine validates this function's preconditions.
pub fn capped_exponential_delay(
  base_ms : Int,
  retry_number : Int,
  cap_ms : Int,
) -> Int where {
  proof_require: 0 <= base_ms,
  proof_require: base_ms <= cap_ms,
  proof_require: 1 <= retry_number,
  proof_require: retry_number <= 5,
  proof_require: cap_ms <= 10000,
  proof_ensure: result => 0 <= result && result <= cap_ms,
} {
  let mut delay = base_ms
  for _ in 0..<(retry_number - 1) {
    let doubled = delay * 2
    delay = if doubled > cap_ms { cap_ms } else { doubled }
  } where {
    proof_invariant: 0 <= delay,
    proof_invariant: delay <= cap_ms,
    proof_reasoning: (
      #|The initial delay is within the configured ceiling. Each retry doubles
      #|a nonnegative value and clamps it to the same ceiling, so both bounds
      #|remain true. The contract limits the loop to four doublings and 10000
      #|milliseconds, well below machine-integer overflow.
    ),
  }
  delay
}
