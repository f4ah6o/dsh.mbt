///|
priv struct NativeArchiveCommit {
  plan : @engine.ToolResultArchivePlan
  source : @engine.ToolResultArchiveSource
  object : NativeToolResultArchiveObject
}

///|
priv struct NativeArchiveCommandReceipt {
  command_id : String
  fingerprint : String
  identity_key : String
}

///|
fn native_archive_session_event(
  session : Json,
  sequence : Int32,
  event_type : String,
) -> Json? {
  match object_field(session, "events") {
    Some(Json::Array(events)) =>
      for event in events {
        if int_field(event, "seq") == Some(sequence) &&
          string_field(event, "type") == Some(event_type) {
          return Some(event)
        }
      }
    _ => ()
  }
  None
}

///|
/// Consider every original result after prune has run. In particular, a
/// result that was directly pruned in an earlier v1 checkpoint will not
/// appear in this invocation's newly-pruned response.
fn native_archive_unarchived_result_sequences(
  session : Json,
) -> Result[Array[Int32], String] {
  let events = match object_field(session, "events") {
    Some(Json::Array(value)) => value
    _ => return Err("archive candidate session has no events")
  }
  let sequences : Array[Int32] = []
  for event in events {
    if string_field(event, "type") != Some("tool/result") {
      continue
    }
    let data = match object_field(event, "data") {
      Some(value) => value
      None => return Err("archive candidate result has no data")
    }
    if object_field(data, "archive_ref") is Some(_) {
      continue
    }
    let sequence = match int_field(event, "seq") {
      Some(value) => value
      None => return Err("archive candidate result has no sequence")
    }
    sequences.push(sequence)
  }
  Ok(sequences)
}

///|
fn native_archive_plan_object(
  candidate : @api.HarnessApi,
  session : Json,
  plan : @engine.ToolResultArchivePlan,
) -> Result[NativeToolResultArchiveObject?, String] {
  let result = match
    native_archive_session_event(session, plan.result_sequence(), "tool/result") {
    Some(value) => value
    None => return Err("archive candidate has no original tool result")
  }
  let pruning = match
    native_archive_session_event(
      session,
      plan.pruned_sequence(),
      "tool/result/pruned",
    ) {
    Some(value) => value
    None => return Err("archive candidate has no direct pruning event")
  }
  let result_data = object_field(result, "data").unwrap_or(Json::null())
  let prune_data = object_field(pruning, "data").unwrap_or(Json::null())
  let content = match string_field(result_data, "content") {
    Some(value) => value
    None => return Err("archive candidate result has no text")
  }
  let projection = match string_field(prune_data, "content") {
    Some(value) => value
    None => return Err("archive candidate projection has no text")
  }
  let threshold = match int_field(prune_data, "threshold_chars") {
    Some(value) => value
    None => return Err("archive candidate prune threshold is missing")
  }
  let head = match int_field(prune_data, "head_chars") {
    Some(value) => value
    None => return Err("archive candidate prune head is missing")
  }
  let tail = match int_field(prune_data, "tail_chars") {
    Some(value) => value
    None => return Err("archive candidate prune tail is missing")
  }
  ignore(candidate)
  // The archive codec has a 64 KiB original-content bound. Keep larger but
  // otherwise valid pruned results inline; malformed provenance and digest
  // failures remain hard errors.
  if @utf8.encode(content).length() > 65536 ||
    @utf8.encode(projection).length() > 65536 {
    return Ok(None)
  }
  match
    NativeToolResultArchiveObject::from_unverified_plan_parts(
      plan, content, projection, threshold, head, tail,
    ) {
    Ok(value) => Ok(Some(value))
    Err(error) => Err(error)
  }
}

///|
fn native_archive_result_with_compact_session(
  prune_result : Json,
  compact_session : Json,
  references : Array[@engine.ToolResultArchiveRef],
) -> Json {
  let public_session = if references.is_empty() &&
    !native_session_has_archive_markers(compact_session) {
    compact_session
  } else {
    native_safe_session(compact_session)
  }
  match prune_result {
    Json::Object(fields) => {
      let result = fields.copy()
      result["session"] = public_session
      result["archive_refs"] = Json::array(
        references.map(reference => reference.json()),
      )
      Json::object(result)
    }
    _ =>
      {
        "session": public_session,
        "archive_refs": Json::array(
          references.map(reference => reference.json()),
        ),
      }
  }
}

///|
/// Stage a settled-session prune on an exact detached engine copy, publish each
/// eligible regular Read object, and checkpoint the compact v2 manifest in one
/// native-envelope CAS. The authoritative API is changed only after the CAS
/// returns KnownSuccess.
fn NativeRuntime::prune_and_archive_locked(
  self : NativeRuntime,
  input : Json,
  receipt~ : NativeArchiveCommandReceipt? = None,
) -> Result[(Json, Array[@engine.EngineEffect]), String] {
  self.prune_and_archive_locked_with_writer(input, receipt~, (store, state) => {
    store.save(state)
  })
}

///|
/// The writer parameter is an internal transaction seam for testing durable
/// before-write and after-write uncertainty. Production always supplies the
/// NativeStore CAS writer above.
fn NativeRuntime::prune_and_archive_locked_with_writer(
  self : NativeRuntime,
  input : Json,
  receipt~ : NativeArchiveCommandReceipt? = None,
  save : (NativeStore, NativeState) -> Result[Unit, String],
) -> Result[(Json, Array[@engine.EngineEffect]), String] {
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  let session_id = match string_field(input, "session_id") {
    Some(value) => value
    None => return Err("tool-result pruning requires a session id")
  }
  let session_id_typed = match @engine.SessionId::new(session_id) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let candidate = match self.api.detached_copy() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let prune_result = match
    candidate.invoke("session_prune_tool_results", input) {
    Ok(value) => value
    Err(error) => {
      candidate.close()
      return Err(error)
    }
  }
  let mut candidate_session = match
    candidate.invoke("session_get", { "session_id": Json::string(session_id) }) {
    Ok(value) => value
    Err(error) => {
      candidate.close()
      return Err(error)
    }
  }
  let commits : Array[NativeArchiveCommit] = []
  let added_sources : Array[@engine.ToolResultArchiveSource] = []
  let added_references : Array[@engine.ToolResultArchiveRef] = []
  match native_archive_unarchived_result_sequences(candidate_session) {
    Ok(result_sequences) =>
      for result_seq in result_sequences {
        let plan = match
          candidate.plan_tool_result_archive(session_id_typed, result_seq) {
          // Pruned results outside the regular Read archive boundary retain
          // the established inline history representation.
          Err(_) => continue
          Ok(value) => value
        }
        let object = match
          native_archive_plan_object(candidate, candidate_session, plan) {
          Err(error) => {
            candidate.close()
            return Err("eligible archive object failed validation: " + error)
          }
          Ok(None) => continue
          Ok(Some(value)) => value
        }
        let engine_reference = match
          @engine.ToolResultArchiveRef::from_json(object.reference().json()) {
          Ok(value) => value
          Err(error) => {
            candidate.close()
            return Err(error)
          }
        }
        let source = match
          @engine.ToolResultArchiveSource::from_object_text(
            engine_reference,
            object.encoded_object(),
          ) {
          Ok(value) => value
          Err(error) => {
            candidate.close()
            return Err(error)
          }
        }
        let staged_snapshot = match
          candidate.tool_result_archive_candidate(plan, source) {
          Ok(value) => value
          Err(error) => {
            candidate.close()
            return Err("archive candidate failed admission: " + error)
          }
        }
        match candidate.commit_tool_result_archive(plan, source) {
          Ok(_) => ()
          Err(error) => {
            candidate.close()
            return Err("archive candidate cannot be applied: " + error)
          }
        }
        if candidate.snapshot() != staged_snapshot {
          candidate.close()
          return Err("archive candidate differs from its admitted snapshot")
        }
        added_sources.push(source)
        added_references.push(source.reference())
        commits.push({ plan, source, object, })
        candidate_session = match
          candidate.invoke("session_get", {
            "session_id": Json::string(session_id),
          }) {
          Ok(value) => value
          Err(error) => {
            self.stopped = true
            candidate.close()
            return Err("staged archive session cannot be read: " + error)
          }
        }
      }
    Err(error) => {
      candidate.close()
      return Err(error)
    }
  }
  let candidate_snapshot = candidate.snapshot()
  let candidate_result = native_archive_result_with_compact_session(
    prune_result, candidate_session, added_references,
  )
  let next_revision = self.state.revision + 1
  let receipts = match receipt {
    Some(command) => {
      let completed = native_receipt(
        self.state.workspace_id,
        command.command_id,
        command.fingerprint,
        "completed",
        Some(next_revision),
        Some(candidate_result),
        None,
      )
      native_replace_receipt(
        self.state.receipts,
        command.command_id,
        command.identity_key,
        native_receipt_with_owner(completed, command.identity_key),
      )
    }
    None => self.state.receipts
  }
  let planned_locators : Array[NativeArchiveLocator] = []
  for commit in commits {
    let file_name = match random_hex(24) {
      Ok(value) => value + ".json"
      Err(error) => {
        candidate.close()
        return Err(error)
      }
    }
    planned_locators.push({
      object_id: commit.object.reference().object_id(),
      file_name,
    })
  }
  let next = {
    engine: candidate_snapshot,
    archive_objects: [..self.state.archive_objects, ..planned_locators],
    archive_sources: [..self.state.archive_sources, ..added_sources],
    receipts,
    acp_sessions: self.state.acp_sessions,
    server_id: self.state.server_id,
    workspace_id: self.state.workspace_id,
    identity_key: self.state.identity_key,
    epoch: self.state.epoch,
    revision: next_revision,
    auth_revision: self.state.auth_revision,
    external_mcp_catalog_hash: self.external_mcp.catalog_hash,
    lsp_catalog_hash: self.lsp.catalog_hash,
  }
  // Run aggregate engine and protected storage admission for the full batch,
  // then serialize the exact final envelope (including receipts and locators)
  // before publishing the first immutable object.
  match
    self.store.check_archive_batch_reservation(
      commits.map(commit => commit.object),
    ) {
    Ok(_) => ()
    Err(error) => {
      candidate.close()
      return Err(error)
    }
  }
  match self.store.admit_state(next) {
    Ok(_) => ()
    Err(error) => {
      candidate.close()
      return Err(error)
    }
  }
  for index, commit in commits {
    let expected_locator = planned_locators[index]
    let locator = match
      self.store.publish_archive_object(
        commit.object,
        expected_locator.file_name,
      ) {
      Ok(value) => value
      Err(error) => {
        self.stopped = true
        candidate.close()
        return Err(error)
      }
    }
    if locator.object_id != expected_locator.object_id ||
      locator.file_name != expected_locator.file_name {
      self.stopped = true
      candidate.close()
      return Err("published archive locator differs from the admitted manifest")
    }
  }
  match save(self.store, next) {
    Ok(_) => self.state = next
    Err(error) => {
      self.stopped = true
      candidate.close()
      return Err(error)
    }
  }
  let live_prune = match self.api.invoke("session_prune_tool_results", input) {
    Ok(value) => value
    Err(error) => {
      self.stopped = true
      candidate.close()
      return Err(
        "durable archive could not be adopted into live engine: " + error,
      )
    }
  }
  for commit in commits {
    match self.api.commit_tool_result_archive(commit.plan, commit.source) {
      Ok(_) => ()
      Err(error) => {
        self.stopped = true
        candidate.close()
        return Err("durable archive commit could not be adopted: " + error)
      }
    }
  }
  if self.api.snapshot() != candidate_snapshot {
    self.stopped = true
    candidate.close()
    return Err("live engine differs from the durable archive candidate")
  }
  let compact_session = match
    self.api.invoke("session_get", { "session_id": Json::string(session_id) }) {
    Ok(value) => value
    Err(error) => {
      self.stopped = true
      candidate.close()
      return Err("committed archive session cannot be read: " + error)
    }
  }
  ignore(live_prune)
  if compact_session != candidate_session {
    self.stopped = true
    candidate.close()
    return Err("committed transcript differs from the durable archive result")
  }
  candidate.close()
  Ok((candidate_result, self.api.take_typed_effects()))
}
