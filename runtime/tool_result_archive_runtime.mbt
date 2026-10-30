///|
priv struct NativeArchiveCommit {
  plan : @engine.ToolResultArchivePlan
  object : NativeToolResultArchiveObject
}

///|
priv struct NativeArchiveCommandReceipt {
  command_id : String
  fingerprint : String
  identity_key : String
}

///|
priv struct NativeSendCommandReceipt {
  command_id : String
  fingerprint : String
  identity_key : String
}

///|
priv struct NativeArchiveBatch {
  session : Json
  commits : Array[NativeArchiveCommit]
  sources : Array[@engine.ToolResultArchiveSource]
  references : Array[@engine.ToolResultArchiveRef]
  snapshot : Json
}

///|
priv struct NativeAutoSendCandidate {
  session_id : String
  candidate : @api.HarnessApi
  batch : NativeArchiveBatch
  result : Json
  snapshot : Json
  effects : Array[@engine.EngineEffect]
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
  let direct_prunes : Map[Int32, Bool] = Map([])
  for event in events {
    if string_field(event, "type") != Some("tool/result/pruned") {
      continue
    }
    let data = match object_field(event, "data") {
      Some(value) => value
      None => return Err("archive candidate prune event has no data")
    }
    let result_seq = match int_field(data, "result_seq") {
      Some(value) => value
      None => return Err("archive candidate prune event has no result sequence")
    }
    let source_seq = match int_field(data, "source_seq") {
      Some(value) => value
      None => return Err("archive candidate prune event has no source sequence")
    }
    if result_seq < 0 ||
      result_seq >= events.length() ||
      source_seq < 0 ||
      source_seq >= events.length() {
      return Err("archive candidate prune references an invalid sequence")
    }
    if source_seq == result_seq {
      if direct_prunes.get(result_seq) is Some(_) {
        return Err("archive candidate has duplicate direct prune events")
      }
      direct_prunes[result_seq] = true
    }
  }
  let sequences : Array[Int32] = []
  for event in events {
    if string_field(event, "type") != Some("tool/result") {
      continue
    }
    let sequence = match int_field(event, "seq") {
      Some(value) => value
      None => return Err("archive candidate result has no sequence")
    }
    if direct_prunes.get(sequence) is None {
      continue
    }
    let data = match object_field(event, "data") {
      Some(value) => value
      None => return Err("archive candidate result has no data")
    }
    if object_field(data, "archive_ref") is Some(_) {
      continue
    }
    sequences.push(sequence)
  }
  for result_seq, _ in direct_prunes {
    if string_field(events[result_seq], "type") != Some("tool/result") {
      return Err("archive candidate direct prune does not reference a result")
    }
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
/// Stage every supported direct-pruned Read result in one detached candidate.
/// Unsupported results remain inline; a supported result whose provenance or
/// object encoding is malformed fails the whole operation.
fn native_archive_stage_batch(
  candidate : @api.HarnessApi,
  session_id : String,
) -> Result[NativeArchiveBatch, String] {
  let session_id_typed = match @engine.SessionId::new(session_id) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let candidate_session = match
    candidate.invoke("session_get", { "session_id": Json::string(session_id) }) {
    Ok(value) => value
    Err(error) =>
      return Err("archive candidate session cannot be read: " + error)
  }
  let result_sequences = match
    native_archive_unarchived_result_sequences(candidate_session) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let commits : Array[NativeArchiveCommit] = []
  let sources : Array[@engine.ToolResultArchiveSource] = []
  let references : Array[@engine.ToolResultArchiveRef] = []
  for result_seq in result_sequences {
    let supported = match
      candidate.tool_result_archive_supported(session_id_typed, result_seq) {
      Ok(value) => value
      Err(error) => return Err("archive provenance validation failed: " + error)
    }
    if !supported {
      continue
    }
    let plan = match
      candidate.plan_tool_result_archive(session_id_typed, result_seq) {
      Ok(value) => value
      Err(error) =>
        return Err("eligible archive plan failed validation: " + error)
    }
    let object = match
      native_archive_plan_object(candidate, candidate_session, plan) {
      Err(error) =>
        return Err("eligible archive object failed validation: " + error)
      Ok(None) => continue
      Ok(Some(value)) => value
    }
    let engine_reference = match
      @engine.ToolResultArchiveRef::from_json(object.reference().json()) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let source = match
      @engine.ToolResultArchiveSource::from_object_text(
        engine_reference,
        object.encoded_object(),
      ) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    commits.push({ plan, object, })
    sources.push(source)
    references.push(source.reference())
  }
  let plans = commits.map(commit => commit.plan)
  let staged_snapshot = match
    candidate.tool_result_archives_candidate(plans, sources) {
    Ok(value) => value
    Err(error) => return Err("archive batch failed admission: " + error)
  }
  if !commits.is_empty() {
    match candidate.commit_tool_result_archives(plans, sources) {
      Ok(_) => ()
      Err(error) => return Err("archive batch cannot be applied: " + error)
    }
  }
  if candidate.snapshot() != staged_snapshot {
    return Err("archive batch differs from its admitted snapshot")
  }
  let compact_session = match
    candidate.invoke("session_get", { "session_id": Json::string(session_id) }) {
    Ok(value) => value
    Err(error) => return Err("staged archive session cannot be read: " + error)
  }
  Ok({
    session: compact_session,
    commits,
    sources,
    references,
    snapshot: candidate.snapshot(),
  })
}

///|
fn native_send_input_without_auto_pruning(input : Json) -> Result[Json, String] {
  match input {
    Json::Object(fields) => {
      let copy = fields.copy()
      copy["auto_prune_tool_results"] = Json::boolean(false)
      Ok(Json::object(copy))
    }
    _ => Err("session_send input must be an object")
  }
}

///|
/// Build the complete prune → archive → send candidate without changing the
/// live engine or running external hooks. The caller re-runs this after hooks
/// and cancellation checks, then admits the resulting single snapshot.
fn native_auto_send_candidate(
  api : @api.HarnessApi,
  input : Json,
  session_start_contexts : Array[String],
  prompt_contexts : Array[String],
  source_kind : String,
) -> Result[NativeAutoSendCandidate, String] {
  match @engine.EngineCommand::from_json("session_send", input) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let session_id = match string_field(input, "session_id") {
    Some(value) => value
    None => return Err("session_send requires a session id")
  }
  let typed_session_id = match @engine.SessionId::new(session_id) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let candidate = match api.detached_copy() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match candidate.prune_tool_results_for_send(typed_session_id) {
    Ok(_) => ()
    Err(error) => {
      candidate.close()
      return Err(error)
    }
  }
  let batch = match native_archive_stage_batch(candidate, session_id) {
    Ok(value) => value
    Err(error) => {
      candidate.close()
      return Err(error)
    }
  }
  let send_input = match native_send_input_without_auto_pruning(input) {
    Ok(value) => value
    Err(error) => {
      candidate.close()
      return Err(error)
    }
  }
  let result = match
    candidate.invoke_session_send_with_hook_contexts(
      send_input,
      session_start_contexts,
      prompt_contexts,
      source_kind~,
    ) {
    Ok(value) => value
    Err(error) => {
      candidate.close()
      return Err(error)
    }
  }
  let snapshot = candidate.snapshot()
  let public_result = if native_session_has_archive_markers(result) {
    native_safe_session(result)
  } else {
    result
  }
  let effects = candidate.take_typed_effects()
  Ok({ session_id, candidate, batch, result: public_result, snapshot, effects, })
}

///|
fn native_send_receipts(
  base : Array[Json],
  receipt : NativeSendCommandReceipt?,
  workspace_id : String,
  revision : Int32,
  result : Json,
) -> Array[Json] {
  match receipt {
    None => base
    Some(command) => {
      let accepted = native_receipt(
        workspace_id,
        command.command_id,
        command.fingerprint,
        "accepted",
        Some(revision),
        Some(result),
        None,
      )
      let owned = native_receipt_with_owner(accepted, command.identity_key)
      let exists = base.any(previous => {
        native_receipt_owner(previous) == command.identity_key &&
        string_field(previous, "command_id") == Some(command.command_id)
      })
      if exists {
        native_replace_receipt(
          base,
          command.command_id,
          command.identity_key,
          owned,
        )
      } else {
        [..base, owned]
      }
    }
  }
}

///|
fn NativeRuntime::auto_send_next_state(
  self : NativeRuntime,
  staged : NativeAutoSendCandidate,
  receipt : NativeSendCommandReceipt?,
  receipts_base : Array[Json],
  acp_activity_session_id : String,
  revision : Int32,
) -> Result[NativeState, String] {
  let locators : Array[NativeArchiveLocator] = []
  for commit in staged.batch.commits {
    let file_name = match random_hex(24) {
      Ok(value) => value + ".json"
      Err(error) => return Err(error)
    }
    locators.push({
      object_id: commit.object.reference().object_id(),
      file_name,
    })
  }
  let acp_sessions = if acp_activity_session_id.is_empty() {
    self.state.acp_sessions
  } else {
    match
      native_acp_move_session_to_front(
        self.state.acp_sessions,
        acp_activity_session_id,
        native_acp_timestamp(),
      ) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
  }
  let receipts = native_send_receipts(
    receipts_base,
    receipt,
    self.state.workspace_id,
    revision,
    staged.result,
  )
  Ok({
    engine: staged.snapshot,
    archive_objects: [..self.state.archive_objects, ..locators],
    archive_sources: [..self.state.archive_sources, ..staged.batch.sources],
    receipts,
    acp_sessions,
    server_id: self.state.server_id,
    workspace_id: self.state.workspace_id,
    identity_key: self.state.identity_key,
    epoch: self.state.epoch,
    revision,
    auth_revision: self.state.auth_revision,
    external_mcp_catalog_hash: self.external_mcp.catalog_hash,
    lsp_catalog_hash: self.lsp.catalog_hash,
  })
}

///|
/// Stage the complete send before hooks run, then validate its archive object
/// batch, native envelope, and storage quota without publishing anything.
fn NativeRuntime::preview_auto_send_locked(
  self : NativeRuntime,
  input : Json,
  source_kind : String,
  receipt : NativeSendCommandReceipt?,
  receipts_base : Array[Json],
  acp_activity_session_id : String,
  predicted_revision : Int32,
) -> Result[Unit, String] {
  let staged = match
    native_auto_send_candidate(self.api, input, [], [], source_kind) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let next = match
    self.auto_send_next_state(
      staged, receipt, receipts_base, acp_activity_session_id, predicted_revision,
    ) {
    Ok(value) => value
    Err(error) => {
      staged.candidate.close()
      return Err(error)
    }
  }
  match
    self.store.check_archive_batch_reservation(
      staged.batch.commits.map(commit => commit.object),
    ) {
    Ok(_) => ()
    Err(error) => {
      staged.candidate.close()
      return Err(error)
    }
  }
  match self.store.admit_state(next) {
    Ok(_) => {
      staged.candidate.close()
      Ok(())
    }
    Err(error) => {
      staged.candidate.close()
      Err(error)
    }
  }
}

///|
/// Publish and checkpoint one complete opt-in send candidate. No provider
/// effect is returned until the archive objects and final envelope are
/// durable. The live API adopts the same prune, archive, and hook inputs only
/// after KnownSuccess.
fn NativeRuntime::auto_send_and_archive_locked(
  self : NativeRuntime,
  input : Json,
  session_start_contexts : Array[String],
  prompt_contexts : Array[String],
  source_kind : String,
  receipt : NativeSendCommandReceipt?,
  acp_activity_session_id : String,
) -> Result[(Json, Array[@engine.EngineEffect]), String] {
  self.auto_send_and_archive_locked_with_io(
    input,
    session_start_contexts,
    prompt_contexts,
    source_kind,
    receipt,
    acp_activity_session_id,
    (store, object, file_name) => {
      store.publish_archive_object(object, file_name)
    },
    (store, state) => store.save(state),
  )
}

///|
/// Internal I/O seam lets transaction tests distinguish a failed publication,
/// a failed final CAS, and a lost acknowledgement after that CAS took effect.
/// Production always uses immutable publication and the NativeStore CAS.
fn NativeRuntime::auto_send_and_archive_locked_with_io(
  self : NativeRuntime,
  input : Json,
  session_start_contexts : Array[String],
  prompt_contexts : Array[String],
  source_kind : String,
  receipt : NativeSendCommandReceipt?,
  acp_activity_session_id : String,
  publish : (NativeStore, NativeToolResultArchiveObject, String) -> Result[
    NativeArchiveLocator,
    String,
  ],
  save : (NativeStore, NativeState) -> Result[Unit, String],
) -> Result[(Json, Array[@engine.EngineEffect]), String] {
  if self.stopped || self.closed {
    return Err("native runtime is stopped")
  }
  let staged = match
    native_auto_send_candidate(
      self.api,
      input,
      session_start_contexts,
      prompt_contexts,
      source_kind,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let next_revision = self.state.revision + 1
  let next = match
    self.auto_send_next_state(
      staged,
      receipt,
      self.state.receipts,
      acp_activity_session_id,
      next_revision,
    ) {
    Ok(value) => value
    Err(error) => {
      staged.candidate.close()
      return Err(error)
    }
  }
  match
    self.store.check_archive_batch_reservation(
      staged.batch.commits.map(commit => commit.object),
    ) {
    Ok(_) => ()
    Err(error) => {
      staged.candidate.close()
      return Err(error)
    }
  }
  match self.store.admit_state(next) {
    Ok(_) => ()
    Err(error) => {
      staged.candidate.close()
      return Err(error)
    }
  }
  let locators = next.archive_objects
  for index, commit in staged.batch.commits {
    let expected = locators[self.state.archive_objects.length() + index]
    let locator = match publish(self.store, commit.object, expected.file_name) {
      Ok(value) => value
      Err(error) => {
        self.stopped = true
        staged.candidate.close()
        return Err(error)
      }
    }
    if locator.object_id != expected.object_id ||
      locator.file_name != expected.file_name {
      self.stopped = true
      staged.candidate.close()
      return Err("published archive locator differs from the admitted manifest")
    }
  }
  match save(self.store, next) {
    Ok(_) => self.state = next
    Err(error) => {
      self.stopped = true
      staged.candidate.close()
      return Err(error)
    }
  }

  let typed_session_id = match @engine.SessionId::new(staged.session_id) {
    Ok(value) => value
    Err(error) => {
      self.stopped = true
      staged.candidate.close()
      return Err(error)
    }
  }
  match self.api.prune_tool_results_for_send(typed_session_id) {
    Ok(_) => ()
    Err(error) => {
      self.stopped = true
      staged.candidate.close()
      return Err("durable auto-prune could not be adopted: " + error)
    }
  }
  if !staged.batch.commits.is_empty() {
    let plans = staged.batch.commits.map(commit => commit.plan)
    match self.api.commit_tool_result_archives(plans, staged.batch.sources) {
      Ok(_) => ()
      Err(error) => {
        self.stopped = true
        staged.candidate.close()
        return Err("durable archive batch could not be adopted: " + error)
      }
    }
  }
  let send_input = match native_send_input_without_auto_pruning(input) {
    Ok(value) => value
    Err(error) => {
      self.stopped = true
      staged.candidate.close()
      return Err(error)
    }
  }
  let live_result = match
    self.api.invoke_session_send_with_hook_contexts(
      send_input,
      session_start_contexts,
      prompt_contexts,
      source_kind~,
    ) {
    Ok(value) => value
    Err(error) => {
      self.stopped = true
      staged.candidate.close()
      return Err("durable auto-send could not be adopted: " + error)
    }
  }
  let live_snapshot = self.api.snapshot()
  let public_live_result = if native_session_has_archive_markers(live_result) {
    native_safe_session(live_result)
  } else {
    live_result
  }
  if live_snapshot != staged.snapshot || public_live_result != staged.result {
    self.stopped = true
    staged.candidate.close()
    return Err("live auto-send differs from the durable candidate")
  }
  let effects = self.api.take_typed_effects()
  if effects.map(@engine.EngineEffect::json) !=
    staged.effects.map(@engine.EngineEffect::json) {
    self.stopped = true
    staged.candidate.close()
    return Err("live auto-send effects differ from the durable candidate")
  }
  staged.candidate.close()
  Ok((public_live_result, effects))
}

///|
/// Finish a remote auto-send after its already-recorded hook reservation. A
/// prepublication failure becomes a rejected receipt; an uncertain publication
/// leaves the accepted reservation in place for reopen to mark uncertain.
async fn NativeRuntime::finish_remote_auto_send_locked(
  self : NativeRuntime,
  control : NativeJobControl,
  session_id : String,
  command_id : String,
  identity_key : String,
  acp_activity_session_id : String,
  fingerprint : String,
  input : Json,
  session_start_contexts : Array[String],
  prompt_contexts : Array[String],
) -> Result[
  (Json, Array[@engine.EngineEffect], Bool, NativeJobControl?),
  String,
] {
  let send_receipt : NativeSendCommandReceipt = {
    command_id,
    fingerprint,
    identity_key,
  }
  let sent = self.auto_send_and_archive_locked(
    input,
    session_start_contexts,
    prompt_contexts,
    self.hooks.context_source_kind(),
    Some(send_receipt),
    acp_activity_session_id,
  )
  match sent {
    Err(error) => {
      self.scheduler.finish(control)
      if self.stopped {
        return Err(error)
      }
      let rejected = native_receipt(
        self.state.workspace_id,
        command_id,
        fingerprint,
        "rejected",
        None,
        None,
        Some(bounded_tool_text(error)),
      )
      self.state.receipts = native_replace_receipt(
        self.state.receipts,
        command_id,
        identity_key,
        native_receipt_with_owner(rejected, identity_key),
      )
      match self.checkpoint_locked() {
        Err(persistence_error) => Err(persistence_error)
        Ok(_) => Ok((rejected, [], false, None))
      }
    }
    Ok((result, effects)) => {
      for effect in effects {
        if effect.session_id().as_string() != session_id {
          self.stopped = true
          self.scheduler.finish(control)
          return Err("remote effect session does not match its reservation")
        }
      }
      let mut stored_receipt : Json? = None
      for receipt in self.state.receipts {
        if native_receipt_owner(receipt) == identity_key &&
          string_field(receipt, "command_id") == Some(command_id) {
          stored_receipt = Some(receipt)
        }
      }
      let receipt = match stored_receipt {
        Some(value) => native_public_receipt(value)
        None => {
          self.stopped = true
          self.scheduler.finish(control)
          return Err("durable auto-send receipt disappeared")
        }
      }
      ignore(result)
      Ok((receipt, effects, true, Some(control)))
    }
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
  let batch = match native_archive_stage_batch(candidate, session_id) {
    Ok(value) => value
    Err(error) => {
      candidate.close()
      return Err(error)
    }
  }
  let commits = batch.commits
  let added_sources = batch.sources
  let added_references = batch.references
  let candidate_session = batch.session
  let candidate_snapshot = batch.snapshot
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
  let plans = commits.map(commit => commit.plan)
  match self.api.commit_tool_result_archives(plans, added_sources) {
    Ok(_) => ()
    Err(error) => {
      self.stopped = true
      candidate.close()
      return Err("durable archive batch could not be adopted: " + error)
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
