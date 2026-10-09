///|
/// Host-wide effect scheduler. It bounds concurrent provider and process work
/// across sessions and fences a job that starts after its cancellation was
/// durably accepted.
priv struct NativeScheduler {
  gate : @async.Mutex
  active : Map[String, NativeJobControl]
  cancelled_through : Map[String, Int]
  slots : @async.Semaphore
}

///|
priv struct NativeJobControl {
  session_id : String
  command_id : String
  accepted_revision : Int
  cancelled : Ref[Bool]
  task : Ref[@async.Task[Result[Unit, String]]?]
}

///|
priv struct NativeReadGroup {
  queue : @aqueue.Queue[NativeEffectWork]
  gate : @async.Mutex
  pending : Ref[Int]
  deferred : Ref[Array[@engine.EngineEffect]]
}

///|
priv enum NativeEffectWork {
  Run(@engine.EngineEffect)
  Stop
}

///|
priv suberror NativeSchedulerFailure {
  NativeSchedulerFailure(String)
}

///|
const NATIVE_EFFECT_WORKERS : Int = 4

///|
fn NativeScheduler::new() -> NativeScheduler {
  {
    gate: @async.Mutex::Mutex(),
    active: Map([]),
    cancelled_through: Map([]),
    slots: @async.Semaphore::Semaphore(NATIVE_EFFECT_WORKERS),
  }
}

///|
async fn NativeScheduler::begin(
  self : NativeScheduler,
  session_id : String,
  command_id : String,
  accepted_revision : Int,
) -> Result[NativeJobControl, String] {
  for ;; {
    self.gate.acquire()
    match self.active.get(session_id) {
      Some(previous) if previous.cancelled.val =>
        match previous.task.val {
          None => {
            self.active.remove(session_id)
            let control = self.new_control(
              session_id, command_id, accepted_revision,
            )
            self.active.set(session_id, control)
            self.gate.release()
            return Ok(control)
          }
          Some(task) => {
            self.gate.release()
            ignore(task.wait()) catch {
              @async.WaitedTaskAlreadyCancelled => ()
              _ => ()
            }
            self.gate.acquire()
            match self.active.get(session_id) {
              Some(current) if current.command_id == previous.command_id =>
                self.active.remove(session_id)
              _ => ()
            }
            self.gate.release()
          }
        }
      Some(_) => {
        self.gate.release()
        return Err("a native effect job is already active for this session")
      }
      None => {
        let control = self.new_control(
          session_id, command_id, accepted_revision,
        )
        self.active.set(session_id, control)
        self.gate.release()
        return Ok(control)
      }
    }
  }
}

///|
fn NativeScheduler::new_control(
  self : NativeScheduler,
  session_id : String,
  command_id : String,
  accepted_revision : Int,
) -> NativeJobControl {
  let cancelled_through = self.cancelled_through.get(session_id).unwrap_or(-1)
  {
    session_id,
    command_id,
    accepted_revision,
    cancelled: Ref(accepted_revision <= cancelled_through),
    task: Ref(None),
  }
}

///|
/// Wait out a cancelled job before a new command mutates the same session.
/// Uncancelled jobs are rejected here before the runtime takes its state gate.
async fn NativeScheduler::await_idle(
  self : NativeScheduler,
  session_id : String,
) -> Result[Unit, String] {
  for ;; {
    self.gate.acquire()
    match self.active.get(session_id) {
      None => {
        self.gate.release()
        return Ok(())
      }
      Some(control) if !control.cancelled.val => {
        self.gate.release()
        return Err("a native effect job is still active for this session")
      }
      Some(control) =>
        match control.task.val {
          None => {
            self.active.remove(session_id)
            self.gate.release()
            return Ok(())
          }
          Some(task) => {
            self.gate.release()
            ignore(task.wait()) catch {
              @async.WaitedTaskAlreadyCancelled => ()
              _ => ()
            }
            self.gate.acquire()
            match self.active.get(session_id) {
              Some(current) if current.command_id == control.command_id =>
                self.active.remove(session_id)
              _ => ()
            }
            self.gate.release()
          }
        }
    }
  }
}

///|
async fn NativeScheduler::attach_task(
  self : NativeScheduler,
  control : NativeJobControl,
  task : @async.Task[Result[Unit, String]],
) -> Unit {
  self.gate.acquire()
  defer self.gate.release()
  match self.active.get(control.session_id) {
    Some(current) if current.command_id == control.command_id => {
      control.task.val = Some(task)
      if control.cancelled.val {
        task.cancel()
      }
    }
    _ => task.cancel()
  }
}

///|
/// A cancellation revision fences older command jobs even if the host task
/// has not started yet. Newer commands for the same session remain runnable.
async fn NativeScheduler::cancel_through(
  self : NativeScheduler,
  session_id : String,
  accepted_revision : Int,
) -> Unit {
  self.gate.acquire()
  defer self.gate.release()
  let previous = self.cancelled_through.get(session_id).unwrap_or(-1)
  if accepted_revision > previous {
    self.cancelled_through.set(session_id, accepted_revision)
  }
  match self.active.get(session_id) {
    Some(control) if control.accepted_revision < accepted_revision => {
      control.cancelled.val = true
      match control.task.val {
        Some(task) => task.cancel()
        None => ()
      }
    }
    _ => ()
  }
}

///|
async fn NativeScheduler::finish(
  self : NativeScheduler,
  control : NativeJobControl,
) -> Unit {
  self.gate.acquire()
  defer self.gate.release()
  match self.active.get(control.session_id) {
    Some(current) if current.command_id == control.command_id =>
      self.active.remove(control.session_id)
    _ => ()
  }
}

///|
async fn[T] NativeScheduler::with_slot(
  self : NativeScheduler,
  run : async () -> T,
) -> T {
  self.slots.acquire()
  defer self.slots.release()
  run()
}

///|
fn native_effect_is_parallel_read(effect : @engine.EngineEffect) -> Bool {
  if effect.kind() != @engine.EffectType::Tool {
    return false
  }
  match object_field(effect.request(), "name") {
    Some(Json::String(name)) => ["read", "glob", "grep"].contains(name)
    _ => false
  }
}

///|
async fn NativeScheduler::run_read_group(
  self : NativeScheduler,
  initial : Array[@engine.EngineEffect],
  control : NativeJobControl,
  run : async (@engine.EngineEffect) -> Result[
    (Json, Array[@engine.EngineEffect]),
    String,
  ],
) -> Result[Array[@engine.EngineEffect], String] {
  if initial.is_empty() {
    return Ok([])
  }
  for effect in initial {
    if !native_effect_is_parallel_read(effect) {
      return Err("read group contains a non-read effect")
    }
  }
  let queue = @aqueue.Queue::Queue(kind=@aqueue.Unbounded)
  for effect in initial {
    queue.put(NativeEffectWork::Run(effect))
  }
  let group : NativeReadGroup = {
    queue,
    gate: @async.Mutex::Mutex(),
    pending: Ref(initial.length()),
    deferred: Ref([]),
  }
  let result = try {
    @async.with_task_group() <| workers => {
      for _ in 0..<NATIVE_EFFECT_WORKERS {
        workers.spawn_bg() <| () => {
          native_read_group_worker(group, self, control, run)
        }
      }
    }
    Ok(())
  } catch {
    NativeSchedulerFailure(message) => Err(message)
    _ => Err("native read group was cancelled")
  }
  match result {
    Ok(_) => Ok(group.deferred.val)
    Err(error) => Err(error)
  }
}

///|
async fn native_read_group_worker(
  group : NativeReadGroup,
  scheduler : NativeScheduler,
  control : NativeJobControl,
  run : async (@engine.EngineEffect) -> Result[
    (Json, Array[@engine.EngineEffect]),
    String,
  ],
) -> Unit raise NativeSchedulerFailure {
  for ;; {
    let work = group.queue.get() catch {
      error => raise NativeSchedulerFailure(error.to_string())
    }
    match work {
      NativeEffectWork::Stop => return
      NativeEffectWork::Run(effect) => {
        if control.cancelled.val {
          raise NativeSchedulerFailure("native command was cancelled")
        }
        let result = scheduler.with_slot(async fn() {
          if control.cancelled.val {
            return Err("native command was cancelled")
          }
          run(effect)
        }) catch {
          error => raise NativeSchedulerFailure(error.to_string())
        }
        let trailing = match result {
          Ok((_, next)) => next
          Err(error) => raise NativeSchedulerFailure(error)
        }
        group.gate.acquire()
        for next in trailing {
          if native_effect_is_parallel_read(next) {
            group.pending.val += 1
            group.queue.put(NativeEffectWork::Run(next)) catch {
              error => raise NativeSchedulerFailure(error.to_string())
            }
          } else {
            group.deferred.val.push(next)
          }
        }
        group.pending.val -= 1
        if group.pending.val == 0 {
          for _ in 0..<NATIVE_EFFECT_WORKERS {
            group.queue.put(NativeEffectWork::Stop) catch {
              error => raise NativeSchedulerFailure(error.to_string())
            }
          }
        }
        group.gate.release()
      }
    }
  }
}

///|
fn native_effect_suffix(
  effects : Array[@engine.EngineEffect],
  start : Int,
) -> Array[@engine.EngineEffect] {
  let output : Array[@engine.EngineEffect] = []
  for index = start; index < effects.length(); index = index + 1 {
    output.push(effects[index])
  }
  output
}

///|
fn native_prepend_effects(
  prefix : Array[@engine.EngineEffect],
  suffix : Array[@engine.EngineEffect],
) -> Array[@engine.EngineEffect] {
  let output : Array[@engine.EngineEffect] = []
  for effect in prefix {
    output.push(effect)
  }
  for effect in suffix {
    output.push(effect)
  }
  output
}

///|
/// Drive engine work while preserving ordered side-effect barriers. Only
/// consecutive filesystem reads share the rolling pool; provider calls,
/// writes, edits, and shell effects each run as a single barrier.
async fn native_drive_effects(
  scheduler : NativeScheduler,
  initial : Array[@engine.EngineEffect],
  control : NativeJobControl,
  run : async (@engine.EngineEffect) -> Result[
    (Json, Array[@engine.EngineEffect]),
    String,
  ],
) -> Result[Unit, String] {
  let mut pending = initial
  while !pending.is_empty() {
    if control.cancelled.val {
      return Err("native command was cancelled")
    }
    let first = pending[0]
    if native_effect_is_parallel_read(first) {
      let reads : Array[@engine.EngineEffect] = []
      let mut consumed = 0
      while consumed < pending.length() &&
            native_effect_is_parallel_read(pending[consumed]) {
        reads.push(pending[consumed])
        consumed += 1
      }
      let rest = native_effect_suffix(pending, consumed)
      let trailing = match scheduler.run_read_group(reads, control, run) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      pending = native_prepend_effects(trailing, rest)
    } else {
      let rest = native_effect_suffix(pending, 1)
      let result = scheduler.with_slot(async fn() {
        if control.cancelled.val {
          return Err("native command was cancelled")
        }
        run(first)
      })
      match result {
        Ok((_, trailing)) => pending = native_prepend_effects(trailing, rest)
        Err(error) => return Err(error)
      }
    }
  }
  Ok(())
}

///|
async test "native scheduler cancellation fences old jobs and waits before reuse" {
  let scheduler = NativeScheduler::new()
  let old_control = match scheduler.begin("session-A", "command-old", 7) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let did_cancel = Ref(false)
  @async.with_task_group() <| group => {
    let task = group.spawn(no_wait=true, async fn() {
      match @async.handle_cancellation(async fn() { @async.sleep(5000) }) {
        None => did_cancel.val = true
        Some(_) => ()
      }
      Ok(())
    })
    scheduler.attach_task(old_control, task)
    scheduler.cancel_through("session-A", 8)
    let fresh = match scheduler.begin("session-A", "command-new", 9) {
      Ok(value) => value
      Err(error) => fail(error)
    }
    assert_true(!fresh.cancelled.val)
    assert_true(did_cancel.val)
    scheduler.finish(fresh)
  }
}
