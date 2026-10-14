///|
/// Resolve the explicit persisted choice over immutable startup settings.
/// Demo mode remains an intentional host-level boundary.
fn NativeRuntime::effective_provider_config(
  self : NativeRuntime,
) -> NativeProviderConfig {
  if !self.provider_config.demo_provider &&
    self.auth.provider_choice == "chatgpt" {
    {
      ..self.provider_config,
      protocol: OpenAIResponses,
      auth_mode: ChatGPT,
      base_url: None,
    }
  } else {
    self.provider_config
  }
}

///|
async fn NativeRuntime::select_chatgpt_model(
  self : NativeRuntime,
  model : String,
  expected_profile~ : String? = None,
) -> Result[Json, String] {
  if self.provider_config.demo_provider {
    return Err("DEMO_PROVIDER: restart without --demo-provider to use ChatGPT")
  }
  self.auth.select_model_for_profile(model, expected_profile)
}

///|
/// An explicit return to startup configuration retains the cached account and
/// model, but fences every selection captured before this transition.
async fn NativeAuth::use_configured_provider(
  self : NativeAuth,
) -> Result[Json, String] {
  self.gate.acquire()
  defer self.gate.release()
  if self.closed {
    return Err("AUTH_CLOSED: authentication manager is closed")
  }
  if self.provider_choice == "configured" {
    return Ok(self.status())
  }
  let generation = match native_auth_random_id() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let old_choice = self.provider_choice
  let old_route = self.route_generation
  let old_generation = self.generation
  self.provider_choice = "configured"
  self.route_generation = generation
  self.generation = generation
  match self.persist_locked() {
    Ok(_) => Ok(self.status())
    Err(error) => {
      self.provider_choice = old_choice
      self.route_generation = old_route
      self.generation = old_generation
      Err(error)
    }
  }
}

///|
fn NativeRuntime::capture_provider_selection(
  self : NativeRuntime,
  model : String?,
) -> Result[NativeProviderSelection, String] {
  let config = self.effective_provider_config()
  if config.demo_provider {
    NativeProviderSelection::api_key(
      OpenAIChatCompletions,
      "offline-demo",
      None,
      config.generation,
    )
  } else if config.auth_mode == ChatGPT {
    match model {
      Some(value) => self.auth.provider_selection_for_model(value)
      None => self.auth.provider_selection()
    }
  } else {
    NativeProviderSelection::api_key(
      config.protocol,
      model.unwrap_or(config.model),
      config.base_url,
      config.generation + ":" + self.auth.route_generation,
    )
  }
}

///|
fn NativeRuntime::validate_provider_selection(
  self : NativeRuntime,
  selection : NativeProviderSelection,
) -> Result[Unit, String] {
  let config = self.effective_provider_config()
  if config.demo_provider {
    if selection.generation() == config.generation {
      Ok(())
    } else {
      Err("PROVIDER_CHANGED: provider selection is no longer active")
    }
  } else if config.auth_mode != selection.auth_mode() {
    Err("PROVIDER_CHANGED: provider changed while the request was in flight")
  } else if selection.auth_mode() == ChatGPT {
    self.auth.validate_generation(selection)
  } else if selection.generation() !=
    config.generation + ":" + self.auth.route_generation {
    Err("PROVIDER_CHANGED: provider changed while the request was in flight")
  } else {
    Ok(())
  }
}

///|
fn NativeRuntime::provider_result(
  self : NativeRuntime,
  selection : NativeProviderSelection,
  result : Json,
) -> Json {
  match self.validate_provider_selection(selection) {
    Ok(_) => result
    Err(error) => native_provider_failure(error)
  }
}
