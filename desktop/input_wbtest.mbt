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

///|
test "Wayland committed text does not double insert physical keys" {
  let key = @primitives.Character("a")
  let none = @primitives.Modifiers::none()
  assert_eq(desktop_key_input_text(key, none, true), None)
  assert_eq(desktop_key_input_text(@primitives.Space, none, true), None)
  assert_eq(desktop_key_input_text(key, none, false), Some("a"))
  let ctrl = @primitives.Modifiers::new(
    shift=false,
    control=true,
    alt=false,
    meta=false,
  )
  assert_true(desktop_shortcut_modifier(ctrl, true))
  assert_false(desktop_shortcut_modifier(ctrl, false))
  assert_eq(desktop_key_input_text(key, ctrl, false), None)
}

///|
fn desktop_test_chars(text : String) -> Array[Char] {
  let characters : Array[Char] = []
  for character in text {
    characters.push(character)
  }
  characters
}

///|
fn desktop_test_composition(
  start : Int32,
  replaced : Int32,
  preedit : String,
) -> DesktopComposition {
  {
    start,
    replaced,
    preedit,
    cursor_utf16: preedit.length(),
    send_after_commit: false,
  }
}

///|
test "composition view overlays preedit at the caret without mutating draft" {
  let draft = desktop_test_chars("abc")
  let composition = desktop_test_composition(1, 0, "にほん")
  assert_eq(
    desktop_composition_view_text(draft, 1, true, Some(composition)),
    "aにほん|bc",
  )
  assert_eq(desktop_draft_string(draft), "abc")
  assert_eq(desktop_composition_view_text(draft, 1, true, None), "a|bc")
  assert_eq(desktop_composition_view_text(draft, 1, false, None), "abc")
  let all = desktop_test_composition(0, 3, "日本")
  assert_eq(desktop_composition_view_text(draft, 3, true, Some(all)), "日本|")
}

///|
test "composition commit replaces the captured span and advances the caret" {
  let draft = desktop_test_chars("abc")
  let insert = match
    desktop_composition_commit_draft(
      draft,
      desktop_test_composition(1, 0, "にほん"),
      "日本",
    ) {
    Some(value) => value
    None => fail("valid composition commit was rejected")
  }
  assert_eq(desktop_draft_string(insert.0), "a日本bc")
  assert_eq(insert.1, 3)
  let replace = match
    desktop_composition_commit_draft(
      draft,
      desktop_test_composition(1, 2, "ほん"),
      "日本語😀",
    ) {
    Some(value) => value
    None => fail("valid replacing commit was rejected")
  }
  assert_eq(desktop_draft_string(replace.0), "a日本語😀")
  assert_eq(replace.1, 5)
  let overflow = "a".repeat(16001)
  assert_true(
    desktop_composition_commit_draft(
      draft,
      desktop_test_composition(0, 3, ""),
      overflow,
    )
    is None,
  )
}

///|
test "composition caret and underline columns follow the wrapped composer" {
  assert_eq(desktop_line_caret_column("aにほん|bc"), 4)
  assert_eq(desktop_line_caret_column("abc"), 3)
  assert_eq(desktop_preedit_columns("にほん"), 3)
  assert_eq(desktop_preedit_columns("に\nほん"), 2)
  let (lines, caret_line, caret_column) = desktop_composer_layout(
    "aにほん|bc", 240.0,
  )
  assert_eq(lines.length(), 1)
  assert_eq(lines[0], "aにほん|bc")
  assert_eq(caret_line, 0)
  assert_eq(caret_column, 4)
}

///|
test "direct keyboard text is exclusive with compositor-owned commits" {
  assert_true(desktop_accept_direct_text(true, false, false, false))
  assert_false(desktop_accept_direct_text(false, false, false, false))
  assert_false(desktop_accept_direct_text(true, true, false, false))
  // Reject both preedit-time keys and the duplicate queued after Commit clears it.
  assert_false(desktop_accept_direct_text(true, false, true, true))
  assert_false(desktop_accept_direct_text(true, false, true, false))
  assert_false(desktop_accept_direct_text(true, false, false, true))
  // Leaving opt-in mode restores ordinary keyboard insertion.
  assert_true(desktop_accept_direct_text(true, false, false, false))
}

///|
test "cancel fences native transactions queued behind a session switch" {
  // Pointer/New is dequeued before native Start/Update/Commit: the app has no
  // visible preedit yet, but must still invoke native finish(false).
  assert_true(desktop_should_finish_composition(true, false, false))
  assert_true(desktop_should_finish_composition(true, true, false))
  assert_true(desktop_should_finish_composition(true, true, true))
  assert_false(desktop_should_finish_composition(true, false, true))
  assert_false(desktop_should_finish_composition(false, false, false))
}

///|
test "Windows ordinary TextInput remains admitted outside active preedit" {
  // Windows emits ordinary WM_CHAR as TextInput even with IME opt-in enabled.
  // Its adapter declares composition_owns_text_input=false; Wayland declares true.
  let enabled = true
  let windows_owns_text_input = false
  assert_true(
    desktop_accept_direct_text(
      true,
      false,
      enabled && windows_owns_text_input,
      false,
    ),
  )
  assert_false(
    desktop_accept_direct_text(
      true,
      false,
      enabled && windows_owns_text_input,
      true,
    ),
  )
}
