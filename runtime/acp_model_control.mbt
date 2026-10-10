///|
const NATIVE_ACP_MODEL_CONFIG_ID : String = "model"

///|
const NATIVE_ACP_MODEL_ENV_BYTE_LIMIT : Int = 16384

///|
const NATIVE_ACP_MODEL_LIMIT : Int = 32

///|
const NATIVE_ACP_MODEL_NAME_LIMIT : Int = 256

///|
// JSON may escape every model-name character as a six-character \uXXXX form.
const NATIVE_ACP_MODEL_SELECTOR_VALUE_LIMIT : Int = NATIVE_ACP_MODEL_NAME_LIMIT *
  6 +
  128

///|
fn native_acp_parse_model_allowlist(
  raw : String?,
) -> Result[Array[String], String] {
  let raw = match raw {
    Some(value) => value
    None => return Ok([])
  }
  if @utf8.encode(raw).length() > NATIVE_ACP_MODEL_ENV_BYTE_LIMIT {
    return Err("DSH_ACP_MODELS exceeds the 16 KiB limit")
  }
  let value = @json.parse(raw) catch {
    _ => return Err("DSH_ACP_MODELS must be a JSON array of model names")
  }
  let values = match value {
    Json::Array(entries) if entries.length() <= NATIVE_ACP_MODEL_LIMIT =>
      entries
    Json::Array(_) =>
      return Err("DSH_ACP_MODELS may contain at most 32 model names")
    _ => return Err("DSH_ACP_MODELS must be a JSON array of model names")
  }
  let result : Array[String] = []
  for entry in values {
    let model = match entry {
      Json::String(value) if !value.trim().is_empty() &&
        value.length() <= NATIVE_ACP_MODEL_NAME_LIMIT => value
      Json::String(_) =>
        return Err(
          "each DSH_ACP_MODELS entry must be nonempty and at most 256 characters",
        )
      _ => return Err("each DSH_ACP_MODELS entry must be a string")
    }
    if result.contains(model) {
      return Err("DSH_ACP_MODELS contains a duplicate model name")
    }
    result.push(model)
  }
  Ok(result)
}

///|
fn native_acp_model_provider_id(protocol : NativeProtocol) -> String {
  match protocol {
    NativeProtocol::DeepSeekMessages => "deepseek"
    NativeProtocol::OpenAIChatCompletions => "openai"
    NativeProtocol::OpenAIResponses => "openai-responses"
  }
}

///|
fn native_acp_model_provider_name(protocol : NativeProtocol) -> String {
  match protocol {
    NativeProtocol::DeepSeekMessages => "DeepSeek"
    NativeProtocol::OpenAIChatCompletions => "OpenAI-compatible"
    NativeProtocol::OpenAIResponses => "OpenAI Responses"
  }
}

///|
/// Persist a non-reversible route fingerprint beside each ACP model selection.
/// It binds protocol, auth mode, demo routing, and the resolved API root
/// without persisting provider credentials or the raw URL.
fn native_acp_route_fingerprint(
  protocol : NativeProtocol,
  auth : String,
  base_url : String,
  demo : Bool,
) -> Result[String, String] {
  let (origin, prefix) = match native_provider_base_url(base_url) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let descriptor = Json::array([
    Json::string(native_acp_model_provider_id(protocol)),
    Json::string(auth),
    Json::string(origin),
    Json::string(prefix),
    Json::boolean(demo),
  ]).stringify()
  native_mcp_sha256_hex(descriptor)
}

///|
fn NativeRuntime::acp_route_id(self : NativeRuntime) -> Result[String, String] {
  let auth = match self.provider_config.auth_mode {
    NativeAuthMode::ApiKey => "api-key"
    NativeAuthMode::ChatGPT => "chatgpt"
  }
  let base_url = if self.provider_config.auth_mode == NativeAuthMode::ChatGPT {
    "https://api.openai.com"
  } else {
    self.provider_config.base_url.unwrap_or(
      if self.provider_config.protocol == NativeProtocol::DeepSeekMessages {
        "https://api.deepseek.com/anthropic"
      } else {
        "https://api.openai.com"
      },
    )
  }
  native_acp_route_fingerprint(
    self.provider_config.protocol,
    auth,
    base_url,
    self.provider_config.demo_provider,
  )
}

///|
fn native_acp_model_value(protocol : NativeProtocol, model : String) -> String {
  Json::array([
    Json::string(native_acp_model_provider_id(protocol)),
    Json::string(model),
  ]).stringify()
}

///|
fn native_acp_append_unique(models : Array[String], model : String) -> Unit {
  if !models.contains(model) {
    models.push(model)
  }
}

///|
fn NativeRuntime::acp_default_model(self : NativeRuntime) -> String? {
  if self.provider_config.auth_mode == NativeAuthMode::ChatGPT {
    self.auth.visible_selected_model()
  } else {
    Some(self.provider_config.model)
  }
}

///|
fn NativeRuntime::acp_model_choices(
  self : NativeRuntime,
  allowlist : Array[String],
) -> Result[Array[String], String] {
  if self.provider_config.demo_provider {
    if allowlist.length() > 0 {
      return Err("DSH_ACP_MODELS cannot add models to the offline demo route")
    }
    return Ok([self.provider_config.model])
  }
  if self.provider_config.auth_mode == NativeAuthMode::ChatGPT {
    let visible = self.auth.visible_model_slugs()
    let models : Array[String] = []
    if allowlist.length() == 0 {
      for model in visible {
        native_acp_append_unique(models, model)
      }
    } else {
      for model in allowlist {
        if visible.contains(model) {
          native_acp_append_unique(models, model)
        }
      }
    }
    match self.auth.visible_selected_model() {
      Some(model) => native_acp_append_unique(models, model)
      None => ()
    }
    Ok(models)
  } else {
    let models : Array[String] = []
    native_acp_append_unique(models, self.provider_config.model)
    for model in allowlist {
      native_acp_append_unique(models, model)
    }
    Ok(models)
  }
}

///|
fn NativeRuntime::acp_model_options(
  self : NativeRuntime,
  current_model : String?,
  allowlist : Array[String],
) -> Result[Json, String] {
  let current_model = match current_model {
    Some(value) => value
    None => return Ok(Json::array([]))
  }
  let models = match self.acp_model_choices(allowlist) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if !models.contains(current_model) {
    return Err("stored ACP model is not available in the current model catalog")
  }
  let provider = native_acp_model_provider_id(self.provider_config.protocol)
  let options : Array[Json] = []
  for model in models {
    options.push({
      "value": native_acp_model_value(self.provider_config.protocol, model),
      "name": model,
    })
  }
  Ok(
    Json::array([
      Json::object({
        "id": Json::string(NATIVE_ACP_MODEL_CONFIG_ID),
        "name": Json::string("Model"),
        "category": Json::string("model"),
        "type": Json::string("select"),
        "currentValue": Json::string(
          native_acp_model_value(self.provider_config.protocol, current_model),
        ),
        "options": Json::array([
          Json::object({
            "group": Json::string(provider),
            "name": Json::string(
              native_acp_model_provider_name(self.provider_config.protocol),
            ),
            "options": Json::array(options),
          }),
        ]),
      }),
    ]),
  )
}

///|
fn NativeRuntime::acp_model_from_value(
  self : NativeRuntime,
  value : Json,
  allowlist : Array[String],
) -> Result[String, String] {
  let selected = match value {
    Json::String(text) if !text.is_empty() &&
      text.length() <= NATIVE_ACP_MODEL_SELECTOR_VALUE_LIMIT => text
    _ => return Err("model requires a select value")
  }
  let models = match self.acp_model_choices(allowlist) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  for model in models {
    if selected == native_acp_model_value(self.provider_config.protocol, model) {
      return Ok(model)
    }
  }
  Err("unknown model option: " + selected)
}
