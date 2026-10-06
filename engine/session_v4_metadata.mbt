///|
fn replay_v4_metadata(
  replay : V4Replay,
  kind : String,
  data : Json,
  line_number : Int,
) -> Unit raise EngineError {
  match kind {
    "tool/ptc-dispatch-start" => {
      v4_only_fields(
        data,
        ["rootCallId", "parentCallId", "subCallId", "name", "arguments"],
        [],
        "PTC dispatch start",
      )
      if !replay.open_turn || !replay.open_step {
        raise Invalid("Session v4 PTC dispatch start is outside an open step")
      }
      let root = required_string(data, "rootCallId", max=128)
      let parent = required_string(data, "parentCallId", max=128)
      let sub = required_string(data, "subCallId", max=128)
      let name = required_string(data, "name", max=128)
      if root.length() == 0 ||
        parent.length() == 0 ||
        sub.length() == 0 ||
        name.length() == 0 ||
        sub == root ||
        sub == parent ||
        replay.calls.get(sub) is Some(_) ||
        replay.ptc_dispatches.get(sub) is Some(_) {
        raise Invalid("Malformed or duplicate Session v4 PTC dispatch start")
      }
      match v4_open_call(replay, root) {
        Some(_) => ()
        None => raise Invalid("Session v4 PTC rootCallId has no open tool call")
      }
      if parent != root {
        match replay.ptc_dispatches.get(parent) {
          Some(parent_dispatch) if parent_dispatch.root_call_id == root &&
            !parent_dispatch.settled => ()
          _ =>
            raise Invalid(
              "Session v4 PTC parentCallId does not belong to its open root",
            )
        }
      }
      replay.ptc_dispatches.set(sub, {
        root_call_id: root,
        parent_call_id: parent,
        name,
        arguments: required_field(data, "arguments"),
        settled: false,
      })
    }
    "tool/ptc-dispatch" => {
      v4_only_fields(
        data,
        [
          "rootCallId", "parentCallId", "subCallId", "name", "arguments", "isError",
          "content",
        ],
        ["error"],
        "PTC dispatch result",
      )
      let sub = required_string(data, "subCallId", max=128)
      let started = match replay.ptc_dispatches.get(sub) {
        Some(dispatch) if !dispatch.settled => dispatch
        _ => raise Invalid("Session v4 PTC dispatch has no unique start")
      }
      if required_string(data, "rootCallId", max=128) != started.root_call_id ||
        required_string(data, "parentCallId", max=128) != started.parent_call_id ||
        required_string(data, "name", max=128) != started.name ||
        required_field(data, "arguments") != started.arguments {
        raise Invalid("Session v4 PTC dispatch result differs from its start")
      }
      match v4_open_call(replay, started.root_call_id) {
        Some(_) => ()
        None =>
          raise Invalid(
            "Session v4 PTC result has no still-open root tool call",
          )
      }
      if started.parent_call_id != started.root_call_id {
        match replay.ptc_dispatches.get(started.parent_call_id) {
          Some(parent) if parent.root_call_id == started.root_call_id &&
            !parent.settled => ()
          _ =>
            raise Invalid("Session v4 PTC result has no still-open parent call")
        }
      }
      require_v4_ptc_children_settled(replay, sub)
      let is_error = bool_value(required_field(data, "isError"), "PTC isError")
      ignore(
        project_v4_content(
          required_field(data, "content"),
          false,
          false,
          line_number,
        ),
      )
      match fields(data).get("error") {
        None => ()
        Some(error) => {
          if !is_error {
            raise Invalid(
              "Session v4 PTC result has an error with isError=false",
            )
          }
          v4_only_fields(error, ["name", "code"], ["reason"], "PTC error")
          ignore(required_string(error, "name", max=128))
          ignore(required_string(error, "code", max=128))
          match fields(error).get("reason") {
            Some(reason) =>
              ignore(string_value(reason, "PTC error reason", max=8192))
            None => ()
          }
        }
      }
      started.settled = true
    }
    "subagent/catalog" => {
      v4_only_fields(
        data,
        ["version", "childId", "childCreatedAt", "mode"],
        ["label"],
        "subagent catalog",
      )
      if !replay.open_turn || !replay.open_step {
        raise Invalid("Session v4 subagent catalog is outside an open step")
      }
      if int_value(required_field(data, "version"), "catalog version", 0, 1) !=
        0 {
        raise Invalid("Unsupported Session v4 subagent catalog version")
      }
      validate_safe_number(
        required_field(data, "childCreatedAt"),
        "childCreatedAt",
      )
      let child_id = required_string(data, "childId", max=128)
      let mode = required_string(data, "mode", max=32)
      if child_id.length() == 0 ||
        replay.subagents.get(child_id) is Some(_) ||
        (mode != "one-shot" && mode != "continuable") {
        raise Invalid(
          "Malformed or duplicate Session v4 subagent catalog entry",
        )
      }
      match (mode, fields(data).get("label")) {
        ("continuable", Some(label)) =>
          ignore(string_value(label, "subagent label", max=512))
        ("continuable", None) =>
          raise Invalid(
            "Continuable Session v4 subagent catalog entry requires a label",
          )
        (_, Some(label)) =>
          ignore(string_value(label, "subagent label", max=512))
        (_, None) => ()
      }
      let workflow = v4_only_open_workflow(replay)
      let workflow_run_id = match workflow {
        Some(id) => Some(id)
        None =>
          match v4_only_open_call_named(replay, "subagent") {
            Some(_) => None
            None =>
              raise Invalid(
                "Session v4 subagent catalog has no unique open owner",
              )
          }
      }
      replay.subagents.set(child_id, {
        workflow_run_id,
        workflow_linked: false,
      })
    }
    "tool-workflow/run-start" => {
      v4_only_fields(data, ["runId", "name"], [], "workflow run start")
      if !replay.open_turn || !replay.open_step {
        raise Invalid("Session v4 workflow run start is outside an open step")
      }
      let run_id = required_string(data, "runId", max=128)
      let run_name = required_string(data, "name", max=256)
      if run_id.length() == 0 ||
        run_name.length() == 0 ||
        replay.workflow_runs.get(run_id) is Some(_) {
        raise Invalid("Malformed or uncorrelated Session v4 workflow run start")
      }
      let owner_call_id = match v4_only_open_call_named(replay, "workflow") {
        Some(id) => id
        None =>
          raise Invalid(
            "Malformed or uncorrelated Session v4 workflow run start",
          )
      }
      let owner = match replay.calls.get(owner_call_id) {
        Some(call) => call
        None => raise Invalid("Session v4 workflow owner call is missing")
      }
      for _, prior_run in replay.workflow_runs {
        if prior_run.owner_call_id == owner_call_id {
          raise Invalid("Session v4 workflow owner has more than one run")
        }
      }
      let owner_arguments = parse_arguments(owner.arguments)
      let owner_meta = required_field(owner_arguments, "meta")
      if run_name != required_string(owner_meta, "name", max=256) {
        raise Invalid(
          "Session v4 workflow run name differs from owner meta.name",
        )
      }
      match fields(owner_arguments).get("run_in_background") {
        None | Some(Json::False) => ()
        Some(Json::True) =>
          raise Invalid(
            "Background Session v4 workflow runs are outside the supported import subset",
          )
        Some(_) =>
          raise Invalid("Session v4 workflow run_in_background must be boolean")
      }
      replay.workflow_runs.set(run_id, {
        owner_call_id,
        next_agent_seq: 1,
        agents: Map([]),
        ended: false,
      })
    }
    "tool-workflow/agent-start" => {
      v4_only_fields(
        data,
        ["runId", "seq", "label", "childId"],
        ["phase"],
        "workflow agent start",
      )
      let run_id = required_string(data, "runId", max=128)
      let run = match replay.workflow_runs.get(run_id) {
        Some(run) if !run.ended => run
        _ => raise Invalid("Session v4 workflow agent start has no open run")
      }
      let seq = int_value(
        required_field(data, "seq"),
        "workflow agent seq",
        1,
        32767,
      )
      if seq != run.next_agent_seq {
        raise Invalid("Session v4 workflow agent sequence is not contiguous")
      }
      ignore(
        string_value(
          required_field(data, "label"),
          "workflow agent label",
          max=512,
        ),
      )
      match fields(data).get("phase") {
        Some(phase) =>
          ignore(string_value(phase, "workflow agent phase", max=512))
        None => ()
      }
      let child_id = required_string(data, "childId", max=128)
      match replay.subagents.get(child_id) {
        Some(catalog) if catalog.workflow_run_id == Some(run_id) &&
          !catalog.workflow_linked => catalog.workflow_linked = true
        _ =>
          raise Invalid(
            "Session v4 workflow agent start has no matching child catalog",
          )
      }
      if run.agents.get(seq) is Some(_) {
        raise Invalid("Session v4 workflow agent sequence is duplicated")
      }
      run.agents.set(seq, { child_id, settled: false, })
      run.next_agent_seq += 1
    }
    "tool-workflow/agent-end" => {
      v4_only_fields(
        data,
        ["runId", "seq", "outcome"],
        [],
        "workflow agent end",
      )
      let run_id = required_string(data, "runId", max=128)
      let run = match replay.workflow_runs.get(run_id) {
        Some(run) if !run.ended => run
        _ => raise Invalid("Session v4 workflow agent end has no open run")
      }
      let seq = int_value(
        required_field(data, "seq"),
        "workflow agent seq",
        1,
        32767,
      )
      let agent = match run.agents.get(seq) {
        Some(agent) if !agent.settled => agent
        _ => raise Invalid("Session v4 workflow agent end has no unique start")
      }
      if agent.child_id.length() == 0 {
        raise Invalid("Session v4 workflow agent identity is empty")
      }
      let outcome = required_string(data, "outcome", max=32)
      if outcome != "completed" && outcome != "failed" && outcome != "cancelled" {
        raise Invalid("Unknown Session v4 workflow agent outcome")
      }
      agent.settled = true
    }
    "tool-workflow/run-end" => {
      v4_only_fields(data, ["runId", "stopReason"], [], "workflow run end")
      let run_id = required_string(data, "runId", max=128)
      let run = match replay.workflow_runs.get(run_id) {
        Some(run) if !run.ended => run
        _ => raise Invalid("Session v4 workflow run end has no unique start")
      }
      let reason = required_string(data, "stopReason", max=32)
      if reason != "completed" && reason != "cancelled" && reason != "error" {
        raise Invalid("Unknown Session v4 workflow stop reason")
      }
      for _, agent in run.agents {
        if !agent.settled {
          raise Invalid(
            "Session v4 workflow run ended with an unresolved agent",
          )
        }
      }
      run.ended = true
    }
    _ => ()
  }
}
