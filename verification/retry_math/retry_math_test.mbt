///|
test "capped exponential delay respects boundary cases" {
  assert_eq(@retry_math.capped_exponential_delay(0, 5, 10000), 0)
  assert_eq(@retry_math.capped_exponential_delay(500, 1, 10000), 500)
  assert_eq(@retry_math.capped_exponential_delay(500, 5, 10000), 8000)
  assert_eq(@retry_math.capped_exponential_delay(6000, 2, 10000), 10000)
}

///|
test "QuickCheck verifies bounded retry delays over the valid policy domain" {
  @quickcheck.check(
    (input : (Int, Int)) => {
      let (base, retry) = input
      let normalized_base = Int::abs(base % 10001)
      let normalized_retry = Int::abs(retry % 5) + 1
      let result = @retry_math.capped_exponential_delay(
        normalized_base, normalized_retry, 10000,
      )
      result >= 0 && result <= 10000
    },
    count=100U,
    seed=20261007,
  )
}
