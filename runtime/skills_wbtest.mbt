///|
fn native_skill_test_file(
  name : String,
  description : String,
  body : String,
  extra? : String = "",
) -> String {
  "---\nname: " +
  name +
  "\ndescription: " +
  description +
  "\n" +
  extra +
  "---\n" +
  body
}

///|
fn native_skill_test_tool_response(name : String, skill_name : String) -> Json {
  {
    "ok": Json::boolean(true),
    "content": Json::string(""),
    "reasoning": Json::string(""),
    "tool_calls": Json::array([
      {
        "id": Json::string("load-skill-once"),
        "name": Json::string(name),
        "arguments": Json::string(
          Json::object(Map([("name", Json::string(skill_name))])).stringify(),
        ),
      },
    ]),
    "finish_reason": Json::string("tool_calls"),
    "usage": {
      "input_tokens": Json::number(1.0),
      "output_tokens": Json::number(1.0),
      "total_tokens": Json::number(2.0),
    },
  }
}

///|
test "native skills accept bounded scalar frontmatter and reject ambiguous policies" {
  let valid = native_skill_parse(
    "skills/review.md", "---\nname: review-plan\ndescription: 'Review a plan'\ndisable-model-invocation: true\nuser-invocable: false\n---\nRead the plan carefully.",
  ).unwrap()
  assert_eq(valid.name, "review-plan")
  assert_false(valid.model_invocable)
  assert_false(valid.user_invocable)
  assert_eq(valid.content, "Read the plan carefully.")
  let e2e = native_skill_parse(
    "e2e.md", "---\nname: e2e\ndescription: E2E workflows\n---\nbody",
  ).unwrap()
  assert_eq(e2e.name, "e2e")
  assert_eq(e2e.description, "E2E workflows")
  let numeric_hyphen = native_skill_parse(
    "numeric.md", "---\nname: 1-2\ndescription: Plan version 1-2\n---\nbody",
  ).unwrap()
  assert_eq(numeric_hyphen.name, "1-2")
  assert_true(
    native_skill_parse(
      "number.md", "---\nname: number\ndescription: 1e2\n---\nbody",
    )
    is Err(_),
  )
  assert_true(
    native_skill_parse(
      "bad.md", "---\nname: bad\ndescription: bad\ndisable-model-invocation: yes\n---\nbody",
    )
    is Err(_),
  )
  assert_true(
    native_skill_parse(
      "bad.md", "---\nname: bad\ndescription: bad\nuser-invocable:\n---\nbody",
    )
    is Err(_),
  )
  assert_true(
    native_skill_parse(
      "bad.md", "---\nname: bad\ndescription: [a, b]\n---\nbody",
    )
    is Err(_),
  )
  assert_true(
    native_skill_parse(
      "bad.md", "---\nname: bad\ndescription: bad\nuserInvocable: false\n---\nbody",
    )
    is Err(_),
  )
  assert_true(
    native_skill_parse(
      "bad.md", "---\nname: bad\ndescription: bad\nmetadata:\n  source: hidden\n---\nbody",
    )
    is Err(_),
  )
  assert_true(
    native_skill_parse(
      "large.md",
      "---\nname: large\ndescription: large\n---\n" + "x".repeat(60001),
    )
    is Err(_),
  )
  assert_true(
    native_skill_parse("large.md", "x".repeat(NATIVE_SKILL_FILE_LIMIT + 1))
    is Err(_),
  )
}

///|
test "native skill catalog escaping stays under the engine descriptor limit" {
  let catalog : Array[(String, String)] = []
  for _ in 0..<NATIVE_SKILL_MODEL_CATALOG_LIMIT {
    catalog.push(
      (
        "skill-" + "a".repeat(58),
        native_skill_catalog_description("&".repeat(1000)),
      ),
    )
  }
  let tool = @plugins.skill_tool(catalog)
  let description = string_field(tool, "description").unwrap()
  assert_true(description.length() <= 4096)
  assert_true(catalog.all(entry => entry.1.length() <= 120))
  assert_true(description.contains("&amp;"))
}

///|
async test "native skills discover deterministic workspace roots and hide host paths and model-disabled summaries" {
  let fixture = @fs.tmpdir(prefix="dsh-native-skills-discovery")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    let outside = fixture + "/outside"
    @fs.mkdir(workspace)
    @fs.mkdir(outside)
    @fs.mkdir(workspace + "/.dsh/skills/duplicate", recursive=true)
    @fs.mkdir(workspace + "/.dsh/skills/human-only", recursive=true)
    @fs.mkdir(workspace + "/.dsh/skills/private-store", recursive=true)
    @fs.mkdir(workspace + "/.agents/skills", recursive=true)
    @fs.mkdir(workspace + "/custom/skills", recursive=true)
    @fs.mkdir(outside + "/external-skill", recursive=true)
    @fs.write_file(
      workspace + "/.dsh/skills/duplicate/SKILL.md",
      native_skill_test_file("duplicate", "First root", "project body"),
    )
    @fs.write_file(
      workspace + "/.dsh/skills/human-only/SKILL.md",
      native_skill_test_file(
        "human-only",
        "Private routing text",
        "User-only instructions",
        extra="disable-model-invocation: true\n",
      ),
    )
    @fs.write_file(
      workspace + "/.dsh/skills/private-store/SKILL.md",
      native_skill_test_file("private-store", "Must stay hidden", "host state"),
    )
    @fs.write_file(
      workspace + "/.agents/skills/duplicate.md",
      native_skill_test_file("duplicate", "Second root", "agents body"),
    )
    @fs.write_file(
      workspace + "/.agents/skills/agent.md",
      native_skill_test_file(
        "agent",
        "Not for model invocation",
        "agent body",
        extra="user-invocable: false\n",
      ),
    )
    @fs.write_file(
      workspace + "/custom/skills/custom.md",
      native_skill_test_file(
        "custom", "A <custom> & useful skill", "custom body",
      ),
    )
    @fs.write_file(
      outside + "/external-skill/SKILL.md",
      native_skill_test_file(
        "outside", "External", "never follow host symlinks",
      ),
    )
    @fs.symlink(
      workspace + "/.agents/skills/external-link",
      target=outside + "/external-skill",
    )
    let root = SafeRoot::open(workspace).unwrap()
    group.add_defer(() => root.close())
    let skills = NativeSkills::discover(
      root,
      true,
      ["custom/skills"],
      Some(".dsh/skills/private-store"),
    ).unwrap()
    assert_eq(skills.entries.map(entry => entry.name), [
      "agent", "custom", "duplicate", "human-only",
    ])
    let duplicate = native_skill_find_entry(skills.entries, "duplicate").unwrap()
    assert_eq(duplicate.source, "project-dsh")
    assert_eq(duplicate.description, "First root")
    assert_false(skills.entries.any(entry => entry.name == "outside"))
    assert_false(skills.entries.any(entry => entry.name == "private-store"))
    let catalog = skills.model_catalog()
    assert_eq(catalog.map(entry => entry.0), ["agent", "custom", "duplicate"])
    let rendered_catalog = catalog
      .map(entry => entry.0 + ": " + entry.1)
      .join("\n")
    assert_false(rendered_catalog.contains("Private routing text"))
    assert_true(
      rendered_catalog.contains("A &lt;custom&gt; &amp; useful skill"),
    )
  }
}

///|
async test "native skill loading rereads bodies and rechecks model and user invocation controls" {
  let fixture = @fs.tmpdir(prefix="dsh-native-skills-reread")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    @fs.mkdir(workspace + "/.dsh/skills/user-only", recursive=true)
    @fs.mkdir(workspace + "/.agents/skills/model-only", recursive=true)
    let user_path = workspace + "/.dsh/skills/user-only/SKILL.md"
    let model_path = workspace + "/.agents/skills/model-only.md"
    @fs.write_file(
      user_path,
      native_skill_test_file(
        "user-only",
        "Only a user may invoke this",
        "user body",
        extra="disable-model-invocation: true\n",
      ),
    )
    @fs.write_file(
      model_path,
      native_skill_test_file(
        "model-only",
        "Model loaded",
        "old model body",
        extra="user-invocable: false\n",
      ),
    )
    let root = SafeRoot::open(workspace).unwrap()
    group.add_defer(() => root.close())
    let skills = NativeSkills::discover(root, true, [], None).unwrap()
    assert_eq(
      skills
      .expand_user_prompt(root, "  /user-only please review")
      .unwrap()
      .contains("<skill_content name=\"user-only\""),
      true,
    )
    assert_eq(
      skills.expand_user_prompt(root, "/model-only keep as prose"),
      Ok("/model-only keep as prose"),
    )
    assert_eq(
      skills.expand_user_prompt(root, "/missing keep as prose"),
      Ok("/missing keep as prose"),
    )
    @fs.write_file(
      user_path,
      native_skill_test_file(
        "user-only",
        "Only a user may invoke this",
        "x".repeat(17000),
        extra="disable-model-invocation: true\n",
      ),
    )
    let too_long = match skills.expand_user_prompt(root, "/user-only") {
      Ok(_) => fail("oversized user-only instructions were accepted")
      Err(error) => error
    }
    assert_true(too_long.contains("shorten the skill instructions or prompt"))
    assert_false(too_long.contains("load it through the skill tool"))
    assert_true(skills.model_catalog().any(entry => entry.0 == "model-only"))
    assert_false(skills.model_catalog().any(entry => entry.0 == "user-only"))

    @fs.write_file(
      model_path,
      native_skill_test_file(
        "model-only",
        "Model loaded",
        "new body from disk",
        extra="user-invocable: false\n",
      ),
    )
    let loaded = skills.execute(root, {
      "name": "skill",
      "arguments": { "name": "model-only" },
    })
    assert_eq(object_field(loaded, "ok"), Some(Json::boolean(true)))
    assert_true(
      string_field(loaded, "content").unwrap().contains("new body from disk"),
    )
    assert_true(
      string_field(loaded, "content")
      .unwrap()
      .contains("source=\"project-agents\""),
    )

    @fs.write_file(
      model_path,
      native_skill_test_file(
        "renamed",
        "Model loaded",
        "changed identity",
        extra="user-invocable: false\n",
      ),
    )
    let renamed = skills.execute(root, {
      "name": "skill",
      "arguments": { "name": "model-only" },
    })
    assert_false(renamed.stringify().contains("changed identity"))
    assert_true(string_field(renamed, "error").unwrap().contains("unknown"))

    @fs.write_file(
      model_path,
      native_skill_test_file(
        "model-only",
        "Model loaded",
        "policy changed",
        extra="disable-model-invocation: true\n",
      ),
    )
    let disabled = skills.execute(root, {
      "name": "skill",
      "arguments": { "name": "model-only" },
    })
    assert_true(
      string_field(disabled, "error")
      .unwrap()
      .contains("not available for model invocation"),
    )
  }
}

///|
async test "native skill catalog, tool result, and direct invocation are durable across reopen" {
  let fixture = @fs.tmpdir(prefix="dsh-native-skills-runtime")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    @fs.mkdir(workspace + "/.dsh/skills/guide", recursive=true)
    @fs.mkdir(workspace + "/.dsh/skills/hidden", recursive=true)
    @fs.mkdir(workspace + "/.agents/skills/user-only", recursive=true)
    @fs.write_file(
      workspace + "/.dsh/skills/guide/SKILL.md",
      native_skill_test_file(
        "guide", "A guide for review", "Follow the guide body.",
      ),
    )
    @fs.write_file(
      workspace + "/.dsh/skills/hidden/SKILL.md",
      native_skill_test_file(
        "hidden",
        "SECRET-DESCRIPTION-MUST-NOT-LEAK",
        "Hidden body",
        extra="disable-model-invocation: true\n",
      ),
    )
    @fs.write_file(
      workspace + "/.agents/skills/user-only/SKILL.md",
      native_skill_test_file(
        "user-only",
        "A user-invocable workflow",
        "User direct instructions.",
        extra="disable-model-invocation: true\n",
      ),
    )
    let data_dir = fixture + "/data"
    let runtime = NativeRuntime::open(
      data_dir,
      workspace,
      false,
      true,
      enable_skills=true,
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(runtime.close()))
    })
    let session_id = "native-skill-durable-session"
    runtime
    .invoke("session_create", { "id": session_id, "title": "Skills" })
    .unwrap()
    |> ignore
    let (_, initial) = runtime
      .invoke("session_send", {
        "session_id": session_id,
        "prompt": "Please use the guide skill.",
      })
      .unwrap()
    let provider = native_effect_by_kind(initial, @engine.EffectType::Provider).unwrap()
    let tools = match object_field(provider.request(), "tools") {
      Some(Json::Array(values)) => values
      _ => fail("provider request omitted the registered tool catalog")
    }
    let skill_descriptors = tools.filter(tool => {
      string_field(tool, "name") == Some("skill")
    })
    assert_eq(skill_descriptors.length(), 1)
    let descriptor = skill_descriptors[0]
    let description = string_field(descriptor, "description").unwrap()
    assert_true(description.contains("guide`: A guide for review"))
    assert_false(description.contains("SECRET-DESCRIPTION-MUST-NOT-LEAK"))
    assert_eq(string_field(descriptor, "effect"), Some("read"))
    let schema = object_field(descriptor, "input_schema").unwrap()
    assert_eq(
      object_field(schema, "required").unwrap().stringify(),
      "[\"name\"]",
    )

    let (_, tool_effects) = runtime
      .complete(
        provider.id(),
        native_skill_test_tool_response("skill", "guide"),
      )
      .unwrap()
    assert_eq(tool_effects.length(), 1)
    assert_true(tool_effects[0].kind() == @engine.EffectType::Tool)
    let (_, follow_up) = runtime.run_tool_effect(tool_effects[0]).unwrap()
    assert_eq(follow_up.length(), 1)
    assert_true(follow_up[0].kind() == @engine.EffectType::Provider)
    assert_true(
      follow_up[0].request().stringify().contains("Follow the guide body."),
    )
    assert_true(
      follow_up[0].request().stringify().contains("source=\\\"project-dsh\\\""),
    )
    let durable = runtime.store.load().unwrap().engine.stringify()
    assert_true(durable.contains("Follow the guide body."))
    assert_true(durable.contains("project-dsh"))

    let (_, done) = runtime
      .complete(
        follow_up[0].id(),
        native_demo_response("I followed the loaded guide."),
      )
      .unwrap()
    assert_true(done.is_empty())

    let direct_session = "native-skill-user-invocation"
    runtime
    .invoke("session_create", {
      "id": direct_session,
      "title": "Direct skill invocation",
    })
    .unwrap()
    |> ignore
    let (_, direct_effects) = runtime
      .invoke("session_send", {
        "session_id": direct_session,
        "prompt": "/user-only Apply this workflow.",
      })
      .unwrap()
    let direct_provider = native_effect_by_kind(
      direct_effects,
      @engine.EffectType::Provider,
    ).unwrap()
    assert_true(
      direct_provider
      .request()
      .stringify()
      .contains("User direct instructions."),
    )
    assert_true(
      direct_provider.request().stringify().contains("skill-invocation"),
    )
    assert_true(
      runtime.store.load().unwrap().engine
      .stringify()
      .contains("User direct instructions."),
    )
    let (_, cancel_effects) = runtime
      .invoke("session_cancel", { "session_id": direct_session })
      .unwrap()
    assert_true(cancel_effects.is_empty())
    let canceled = runtime
      .invoke("session_get", { "session_id": direct_session })
      .unwrap().0
    assert_eq(string_field(canceled, "status"), Some("cancelled"))
    assert_true(runtime.close() is Ok(_))

    let reopened = NativeRuntime::open(
      data_dir,
      workspace,
      false,
      true,
      enable_skills=true,
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(reopened.close()))
    })
    let (restored, effects) = reopened
      .invoke("session_get", { "session_id": session_id })
      .unwrap()
    assert_true(effects.is_empty())
    assert_eq(string_field(restored, "status"), Some("completed"))
    assert_true(restored.stringify().contains("Follow the guide body."))
    assert_true(restored.stringify().contains("project-dsh"))
    let (restored_direct, direct_effects) = reopened
      .invoke("session_get", { "session_id": direct_session })
      .unwrap()
    assert_true(direct_effects.is_empty())
    assert_eq(string_field(restored_direct, "status"), Some("cancelled"))
    assert_true(
      restored_direct.stringify().contains("User direct instructions."),
    )
    assert_true(restored_direct.stringify().contains("skill-invocation"))
    assert_true(reopened.close() is Ok(_))
    match NativeRuntime::open(data_dir, workspace, false, true) {
      Err(error) =>
        assert_true(error.contains("cannot restore native engine snapshot"))
      Ok(disabled) => {
        ignore(disabled.close())
        assert_true(false)
      }
    }
  }
}

///|
async test "ordinary existing native stores can adopt enabled workspace skills" {
  let fixture = @fs.tmpdir(prefix="dsh-native-skills-adoption")
  @async.with_task_group() <| group => {
    group.add_defer(() => @fs.rmdir(fixture, recursive=true))
    let workspace = fixture + "/workspace"
    @fs.mkdir(workspace)
    let data_dir = fixture + "/data"
    let original = NativeRuntime::open(data_dir, workspace, false, true).unwrap()
    original
    .invoke("session_create", { "id": "pre-skills", "title": "Legacy" })
    .unwrap()
    |> ignore
    original.close().unwrap()
    let enabled = NativeRuntime::open(
      data_dir,
      workspace,
      false,
      true,
      enable_skills=true,
    ).unwrap()
    group.add_defer(() => {
      @async.protect_from_cancel(() => ignore(enabled.close()))
    })
    assert_true(enabled.close() is Ok(_))
  }
}
