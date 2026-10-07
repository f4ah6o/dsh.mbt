///|
/// `approval_revision` is -1 for non-approval commands. The host supplies only
/// a secure random command ID; payload identity and serialization are shared.
#warnings("-deprecated")
#export_name("client_queue_command")
pub fn client_queue_command(
  handle : Int,
  command_id : String,
  operation : String,
  session_id : String,
  input_raw : String,
  approval_revision : Int,
) -> String {
  match get_client(handle) {
    None =>
      client_result(None, false, "disposed", Some("client handle is disposed"))
    Some(state) => {
      let input = @json.parse(input_raw, max_nesting_depth=32) catch {
        _ =>
          return client_result(
            Some(state),
            false,
            "invalid_command",
            Some("command input is not valid JSON"),
          )
      }
      let approval_revision = if approval_revision < 0 {
        None
      } else {
        Some(approval_revision)
      }
      let session_id = if session_id == "" { None } else { Some(session_id) }
      match
        state.queue_command(
          command_id, operation, session_id, input, approval_revision,
        ) {
        Ok(command) =>
          Json::object({
            "ok": Json::boolean(true),
            "status": Json::string("prepared"),
            "command": command.json(),
            "canonical_payload": Json::string(
              @protocol.canonical_command_payload(command),
            ),
            "state": client_state_json(state),
          }).stringify()
        Err(error) =>
          client_result(Some(state), false, "invalid_command", Some(error))
      }
    }
  }
}

///|
#export_name("client_mark_command_sent")
pub fn client_mark_command_sent(handle : Int, command_id : String) -> String {
  match get_client(handle) {
    Some(state) => {
      let marked = state.mark_command_sent(command_id)
      client_result(
        Some(state),
        marked,
        if marked {
          "submitted"
        } else {
          "unknown_command"
        },
        None,
      )
    }
    None =>
      client_result(None, false, "disposed", Some("client handle is disposed"))
  }
}

///|
#export_name("client_mark_command_uncertain")
pub fn client_mark_command_uncertain(
  handle : Int,
  command_id : String,
) -> String {
  match get_client(handle) {
    Some(state) => {
      let marked = state.mark_command_uncertain(command_id)
      client_result(
        Some(state),
        marked,
        if marked {
          "uncertain"
        } else {
          "unknown_command"
        },
        None,
      )
    }
    None =>
      client_result(None, false, "disposed", Some("client handle is disposed"))
  }
}

///|
#export_name("client_apply_receipt")
pub fn client_apply_receipt(handle : Int, raw : String) -> String {
  match get_client(handle) {
    None =>
      client_result(None, false, "disposed", Some("client handle is disposed"))
    Some(state) =>
      match @protocol.CommandReceipt::parse(raw) {
        Err(error) =>
          client_result(Some(state), false, "invalid_receipt", Some(error))
        Ok(receipt) =>
          match state.apply_receipt(receipt) {
            Ok(_) => client_result(Some(state), true, "receipt_applied", None)
            Err(error) =>
              client_result(Some(state), false, "receipt_rejected", Some(error))
          }
      }
  }
}

///|
#export_name("client_mark_receipt_missing")
pub fn client_mark_receipt_missing(handle : Int, command_id : String) -> String {
  match get_client(handle) {
    Some(state) => {
      let marked = state.mark_receipt_missing(command_id)
      client_result(
        Some(state),
        marked,
        if marked {
          "unconfirmed"
        } else {
          "unknown_command"
        },
        None,
      )
    }
    None =>
      client_result(None, false, "disposed", Some("client handle is disposed"))
  }
}

///|
#export_name("client_pending_ids")
pub fn client_pending_ids(handle : Int) -> String {
  match get_client(handle) {
    Some(state) =>
      Json::array(state.pending_command_ids().map(Json::string)).stringify()
    None => "[]"
  }
}
