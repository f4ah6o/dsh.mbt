///|
test "native prompt editing preserves pasted Unicode through send payload" {
  let seed : Array[Char] = []
  for character in "前後" {
    seed.push(character)
  }
  let (draft, cursor) = desktop_insert_at(
    seed, 1, false, "日本語😀العربية",
  )
  assert_eq(cursor, 12)
  let prompt = desktop_draft_string(draft)
  assert_eq(prompt, "前日本語😀العربية後")
  let payload = desktop_prompt_payload(prompt)
  assert_eq(desktop_json_string(payload, "prompt"), prompt)
  assert_eq(
    desktop_renderable_text(prompt, 100),
    "前日本語□□□□□□□□後",
  )
}

///|
test "native select-all replacement preserves pasted Japanese and emoji" {
  let seed : Array[Char] = []
  for character in "old prompt" {
    seed.push(character)
  }
  let (draft, cursor) = desktop_insert_at(seed, 3, true, "助けて😀")
  let prompt = desktop_draft_string(draft)
  assert_eq(cursor, 4)
  assert_eq(prompt, "助けて😀")
  assert_eq(
    desktop_json_string(desktop_prompt_payload(prompt), "prompt"),
    prompt,
  )
}

///|
test "native physical space key inserts a prompt separator" {
  let modifiers = @primitives.Modifiers::none()
  assert_eq(desktop_insertable_key(@primitives.Space, modifiers), Some(" "))
  assert_eq(desktop_insertable_key(@primitives.Tab, modifiers), Some("\t"))
  assert_eq(
    desktop_insertable_key(
      @primitives.Space,
      @primitives.Modifiers::new(
        shift=false,
        control=false,
        alt=false,
        meta=true,
      ),
    ),
    None,
  )
}

///|
test "render boundary normalizes controls without changing prompt data" {
  let prompt = "one\tline\r\nnext\u0001\u007f\u0085end"
  let (draft, _) = desktop_insert_at([], 0, true, prompt)
  let raw_prompt = desktop_draft_string(draft)
  assert_eq(raw_prompt, prompt)
  assert_eq(
    desktop_json_string(desktop_prompt_payload(raw_prompt), "prompt"),
    prompt,
  )
  let visible = desktop_renderable_text(raw_prompt, 100)
  assert_eq(visible, "one\tline\r\nnext□□□end")
  assert_eq(@ui.wrap_text(visible, 80), ["one    line", "next□□□end"])
  assert_eq(
    desktop_renderable_single_line("Title\tone\r\nnext\u0085", 100),
    "Title one next□",
  )
}
