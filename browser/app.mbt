///|
extern "js" fn browser_has_document() -> Bool =
  #| () => typeof document !== "undefined"

///|
/// The shell string is produced only by `shell_html` and Yami-kumo's safe HTML renderer.
extern "js" fn browser_mount_shell(html : String) -> Bool =
  #| (html) => {
  #|   const root = document.getElementById("root");
  #|   if (!root) return false;
  #|   root.innerHTML = html;
  #|   return true;
  #| }

///|
#export_name("start")
pub fn start() -> Bool {
  if !browser_has_document() {
    return false
  }
  match current_browser_app() {
    Some(_) => true
    None => {
      let mounted = browser_mount_shell(shell_html())
      if mounted {
        @dom.enhance()
        if browser_has_window() {
          let app = BrowserApp::new()
          browser_app.val = Some(app)
          initialize_browser(app)
        }
      }
      mounted
    }
  }
}

///|
fn init {
  if browser_has_document() {
    ignore(start())
  }
}
