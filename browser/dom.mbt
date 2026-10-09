///|
extern "js" fn dom_element_exists(id : String) -> Bool =
  #| (id) => !!document.getElementById(id)

///|
/// Look up a shell element after MoonBit has checked its presence.
extern "js" fn dom_element(id : String) -> BrowserValue =
  #| (id) => document.getElementById(id)

///|
extern "js" fn dom_set_text(id : String, value : String) -> Unit =
  #| (id, value) => { const element = document.getElementById(id); if (element) element.textContent = value; }

///|
extern "js" fn dom_set_html(id : String, safe_html : String) -> Unit =
  #| (id, html) => { const element = document.getElementById(id); if (element) element.innerHTML = html; }

///|
extern "js" fn dom_text(id : String) -> String =
  #| (id) => document.getElementById(id)?.textContent || ""

///|
extern "js" fn dom_value(id : String) -> String =
  #| (id) => document.getElementById(id)?.value || ""

///|
extern "js" fn dom_set_value(id : String, value : String) -> Unit =
  #| (id, value) => { const element = document.getElementById(id); if (element) element.value = value; }

///|
extern "js" fn dom_set_boolean_property(
  id : String,
  property : String,
  value : Bool,
) -> Unit =
  #| (id, property, value) => { const element = document.getElementById(id); if (element) element[property] = value; }

///|
extern "js" fn dom_set_numeric_property(
  id : String,
  property : String,
  value : Double,
) -> Unit =
  #| (id, property, value) => { const element = document.getElementById(id); if (element) element[property] = value; }

///|
extern "js" fn dom_boolean_property(id : String, property : String) -> Bool =
  #| (id, property) => !!document.getElementById(id)?.[property]

///|
extern "js" fn dom_set_attribute(
  id : String,
  name : String,
  value : String,
) -> Unit =
  #| (id, name, value) => document.getElementById(id)?.setAttribute(name, value)

///|
extern "js" fn dom_remove_attribute(id : String, name : String) -> Unit =
  #| (id, name) => document.getElementById(id)?.removeAttribute(name)

///|
extern "js" fn dom_toggle_class(
  id : String,
  name : String,
  enabled : Bool,
) -> Unit =
  #| (id, name, enabled) => document.getElementById(id)?.classList.toggle(name, enabled)

///|
extern "js" fn dom_set_root_style(name : String, value : String) -> Unit =
  #| (name, value) => document.documentElement.style.setProperty(name, value)

///|
extern "js" fn dom_set_element_style(
  id : String,
  name : String,
  value : String,
) -> Unit =
  #| (id, name, value) => { const element = document.getElementById(id); if (element) element.style[name] = value; }

///|
extern "js" fn dom_measure(id : String, property : String) -> Double =
  #| (id, property) => document.getElementById(id)?.[property] || 0

///|
extern "js" fn dom_focus(id : String) -> Unit =
  #| (id) => document.getElementById(id)?.focus()

///|
extern "js" fn dom_move_element(id : String, parent_id : String) -> Unit =
  #| (id, parentId) => { const node = document.getElementById(id); const parent = document.getElementById(parentId); if (node && parent) parent.appendChild(node); }

///|
extern "js" fn dom_prevent_default(event : BrowserValue) -> Unit =
  #| (event) => event.preventDefault()

///|
extern "js" fn dom_event_string(
  event : BrowserValue,
  property : String,
) -> String =
  #| (event, property) => String(event?.[property] ?? "")

///|
extern "js" fn dom_event_target_id(event : BrowserValue) -> String =
  #| (event) => String(event?.target?.id ?? "")

///|
extern "js" fn dom_event_boolean(
  event : BrowserValue,
  property : String,
) -> Bool =
  #| (event, property) => !!event?.[property]

///|
extern "js" fn dom_event_closest(
  event : BrowserValue,
  selector : String,
) -> BrowserValue =
  #| (event, selector) => event?.target instanceof Element ? event.target.closest(selector) : null

///|
extern "js" fn dom_value_is_null(value : BrowserValue) -> Bool =
  #| (value) => value === null || value === undefined

///|
extern "js" fn dom_node_attribute(node : BrowserValue, name : String) -> String =
  #| (node, name) => node?.getAttribute(name) || ""

///|
fn dom_event_action(event : BrowserValue) -> String {
  let action_node = dom_event_closest(event, "[data-action]")
  if !dom_value_is_null(action_node) {
    let action = dom_node_attribute(action_node, "data-action")
    if action != "" {
      return action
    }
  }
  if !dom_value_is_null(dom_event_closest(event, ".yk-sidebar-scrim")) {
    return "sidebar-scrim"
  }
  if !dom_value_is_null(dom_event_closest(event, ".yk-context-panel-scrim")) {
    return "context-scrim"
  }
  ""
}

///|
fn dom_event_attribute(event : BrowserValue, name : String) -> String {
  dom_node_attribute(dom_event_closest(event, "[data-action]"), name)
}

///|
extern "js" fn dom_on(
  element : BrowserValue,
  event_name : String,
  callback : (BrowserValue) -> Unit,
  passive : Bool,
) -> Unit =
  #| (element, eventName, callback, passive) => element.addEventListener(eventName, callback, { passive })

///|
extern "js" fn dom_on_window(
  event_name : String,
  callback : (BrowserValue) -> Unit,
  passive : Bool,
) -> Unit =
  #| (eventName, callback, passive) => window.addEventListener(eventName, callback, { passive })

///|
extern "js" fn dom_on_document(
  event_name : String,
  callback : (BrowserValue) -> Unit,
) -> Unit =
  #| (eventName, callback) => document.addEventListener(eventName, callback)

///|
extern "js" fn dom_on_id(
  id : String,
  event_name : String,
  callback : (BrowserValue) -> Unit,
  passive : Bool,
) -> Unit =
  #| (id, eventName, callback, passive) => document.getElementById(id)?.addEventListener(eventName, callback, { passive })

///|
extern "js" fn dom_request_submit(id : String) -> Unit =
  #| (id) => document.getElementById(id)?.requestSubmit()

///|
extern "js" fn dom_on_media(query : String, callback : () -> Unit) -> Unit =
  #| (query, callback) => window.matchMedia(query).addEventListener("change", callback)

///|
extern "js" fn dom_scroll_top(id : String) -> Double =
  #| (id) => document.getElementById(id)?.scrollTop || 0

///|
extern "js" fn dom_scroll_height(id : String) -> Double =
  #| (id) => document.getElementById(id)?.scrollHeight || 0

///|
extern "js" fn dom_scroll_to_bottom(id : String) -> Unit =
  #| (id) => { const element = document.getElementById(id); if (element) element.scrollTop = element.scrollHeight; }

///|
extern "js" fn dom_resize_observer(
  element : BrowserValue,
  callback : () -> Unit,
) -> Unit =
  #| (element, callback) => new ResizeObserver(callback).observe(element)

///|
extern "js" fn dom_request_frame(callback : () -> Unit) -> Int =
  #| (callback) => requestAnimationFrame(callback)

///|
extern "js" fn dom_interval(callback : () -> Unit, milliseconds : Int) -> Int =
  #| (callback, milliseconds) => setInterval(callback, milliseconds)

///|
extern "js" fn browser_has_window() -> Bool =
  #| () => typeof window !== "undefined" && typeof document?.addEventListener === "function"

///|
extern "js" fn browser_location_protocol() -> String =
  #| () => window.location.protocol

///|
extern "js" fn browser_location_hostname() -> String =
  #| () => window.location.hostname

///|
fn browser_is_local_origin() -> Bool {
  let hostname = browser_location_hostname()
  browser_location_protocol() == "http:" &&
  (hostname == "127.0.0.1" || hostname == "localhost")
}

///|
extern "js" fn browser_device_scale() -> Double =
  #| () => window.devicePixelRatio || 1

///|
extern "js" fn browser_viewport_height() -> Double =
  #| () => window.visualViewport?.height || window.innerHeight

///|
extern "js" fn browser_document_hidden() -> Bool =
  #| () => document.hidden

///|
extern "js" fn browser_now_epoch() -> Double =
  #| () => Date.now()

///|
extern "js" fn browser_set_shell_data(
  selector : String,
  name : String,
  value : String,
) -> Unit =
  #| (selector, name, value) => { const shell = document.querySelector(selector); if (shell) shell.dataset[name] = value; }

///|
extern "js" fn browser_canvas_context_available(id : String) -> Bool =
  #| (id) => !!document.getElementById(id)?.getContext("2d")

///|
extern "js" fn browser_canvas_context(id : String) -> BrowserValue =
  #| (id) => document.getElementById(id).getContext("2d")

///|
extern "js" fn browser_service_worker_available() -> Bool =
  #| () => !!navigator.serviceWorker

///|
extern "js" fn browser_media_matches(query : String) -> Bool =
  #| (query) => window.matchMedia(query).matches

///|
extern "js" fn browser_open_tab(url : String, target : String) -> BrowserValue =
  #| (url, target) => window.open(url, target)

///|
extern "js" fn browser_disown_tab(tab : BrowserValue) -> Unit =
  #| (tab) => { if (tab) tab.opener = null; }

///|
extern "js" fn browser_navigate_tab(tab : BrowserValue, url : String) -> Unit =
  #| (tab, url) => tab.location.replace(url)

///|
extern "js" fn browser_close_tab(tab : BrowserValue) -> Unit =
  #| (tab) => tab.close()

///|
extern "js" fn browser_event_prevent_default(event : BrowserValue) -> Unit =
  #| (event) => event.preventDefault()

///|
extern "js" fn browser_event_prompt(event : BrowserValue) -> BrowserValue =
  #| (event) => event

///|
extern "js" fn browser_install_prompt(
  event : BrowserValue,
) -> @js_async.Promise[BrowserValue] =
  #| async (event) => { await event.prompt(); return await event.userChoice; }

///|
extern "js" fn browser_service_worker_register(
  url : String,
  scope : String,
  worker_type : String,
) -> @js_async.Promise[BrowserValue] =
  #| (url, scope, workerType) => navigator.serviceWorker.register(url, { scope, type: workerType })

///|
extern "js" fn browser_query_nodes(
  panel_id : String,
  selector : String,
) -> FixedArray[BrowserValue] =
  #| (panelId, selector) => { const panel = document.getElementById(panelId); return panel ? Array.from(panel.querySelectorAll(selector)) : []; }

///|
extern "js" fn browser_query_selector_all(
  selector : String,
) -> FixedArray[BrowserValue] =
  #| (selector) => Array.from(document.querySelectorAll(selector))

///|
extern "js" fn browser_node_has_visible_rect(node : BrowserValue) -> Bool =
  #| (node) => node.getClientRects().length > 0

///|
extern "js" fn browser_node_has_attribute(
  node : BrowserValue,
  name : String,
) -> Bool =
  #| (node, name) => node.hasAttribute(name)

///|
extern "js" fn browser_node_is_active(node : BrowserValue) -> Bool =
  #| (node) => document.activeElement === node

///|
extern "js" fn browser_node_id(node : BrowserValue) -> String =
  #| (node) => node.id || ""

///|
extern "js" fn browser_node_focus(node : BrowserValue) -> Unit =
  #| (node) => node.focus()

///|
extern "js" fn browser_set_node_attribute(
  node : BrowserValue,
  name : String,
  value : String,
) -> Unit =
  #| (node, name, value) => node.setAttribute(name, value)

///|
extern "js" fn browser_remove_node_attribute(
  node : BrowserValue,
  name : String,
) -> Unit =
  #| (node, name) => node.removeAttribute(name)

///|
extern "js" fn browser_on_visual_resize(callback : () -> Unit) -> Unit =
  #| (callback) => window.visualViewport?.addEventListener("resize", callback)

///|
