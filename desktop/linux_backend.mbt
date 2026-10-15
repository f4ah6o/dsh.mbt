///|
/// Resolve a Linux session without hiding connection errors behind a fallback.
/// Empty display variables do not identify a usable session.
pub fn select_linux_backend(
  requested : String?,
  wayland_display : String?,
  wayland_socket : String?,
  x11_display : String?,
) -> Result[String, String] {
  let wayland = (wayland_display is Some(value) && value != "") ||
    (wayland_socket is Some(value) && value != "")
  let x11 = x11_display is Some(value) && value != ""
  match requested.unwrap_or("auto") {
    "auto" =>
      if wayland {
        Ok("wayland")
      } else if x11 {
        Ok("x11")
      } else {
        Err(
          "Linux desktop needs a graphical session: set WAYLAND_DISPLAY (or WAYLAND_SOCKET) for Wayland, or DISPLAY for X11",
        )
      }
    "wayland" =>
      if wayland {
        Ok("wayland")
      } else {
        Err(
          "DSH_DESKTOP_BACKEND=wayland requires WAYLAND_DISPLAY or WAYLAND_SOCKET",
        )
      }
    "x11" =>
      if x11 {
        Ok("x11")
      } else {
        Err("DSH_DESKTOP_BACKEND=x11 requires DISPLAY")
      }
    value =>
      Err(
        "Invalid DSH_DESKTOP_BACKEND='" +
        value +
        "'; choose auto, wayland, or x11",
      )
  }
}
