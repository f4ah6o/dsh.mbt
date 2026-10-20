# Opt-in Wayland composer IME (0028)

The Wayland desktop adapter uses gpui's bounded composition host API and the
ordinary platform event queue. Enable it with `DSH_DESKTOP_IME=1`. X11 keeps its
existing typed unsupported composition callbacks. This is a text-input-v1
integration; it does not add XIM, text-input-v2/v3, or a full editor.

## Dependency and validation

This integration uses the published `f4ah6o/gpui@0.10.2` dependency, including
the native cancel/rearm fix that preserves raw typing during the leave fence.
The dsh package remains 0.1.28. No workspace override or vendored core is needed.

```sh
moon update
moon check desktop/linux --target native --deny-warn
moon test desktop --target native --deny-warn
sh scripts/build-desktop-linux.sh --build
```

## Ownership and terminal behavior

- Only the focused composer, outside Settings, enables composition through the
  shared desktop gate. The E2E flag also enables it for synthetic tests.
- Composition arming disarms direct keyboard text. Focus callbacks cannot
  re-enable direct text while composition is enabled. Disabling composition
  restores direct typing for the focused window after the native leave fence.
- The Wayland adapter declares exclusive ownership of `TextInput` while
  composition is enabled. The app ignores direct text for this adapter, including
  after a commit clears the visible preedit. Ordinary compositor commits still
  insert text without a preceding preedit. Explicit clipboard paste is separate.
  Windows and macOS do not declare exclusive text ownership: ordinary Windows
  `WM_CHAR`/`TextInput` remains accepted outside visible preedit, preserving the
  Windows integration already merged in PR #73.
- The shared event pump filters foreign windows. Native session generations and
  event ordering fence stale transactions; the app does not independently poll
  the editor event queue.
- Enter commits without sending; Escape cancels. Send waits for the terminal
  commit before submitting. Native finish preserves opt-in for the next
  transaction. Settings, focus loss and other cancellation paths discard preedit.

## Qualification

The offline composition smoke exercises injected update/commit/cancel, then
app-requested finish-commit and finish-cancel without a focus toggle. It checks
exact draft contents and that finishing does not itself send a message. Native
unit coverage rejects direct insertion while opt-in owns input and restores the
direct path when opt-in is disabled.

The packaged Linux harness uses an owned Weston desktop-shell with panels and
animations disabled. It requires the app's protocol trace to show the compositor
advertising `zwp_text_input_manager_v1` and the demo receipt to report
`ime_composition: true`; unsupported capability is a failure, never a skip.
The first PR #74 CI attempt used kiosk-shell, which did not advertise that global
on either Linux runner and timed out before composition could start. Those
failure artifacts are retained on the original run. The desktop-shell profile passed ARM64 acceptance and x86-64 composition/input
smoke, but the x86-64 active-worker case exposed lost initial `Cr` keystrokes
during the native cancellation fence. gpui 0.10.2 fixes that production ingress
path. These are historical failures, retained in
[the kiosk-shell run](https://github.com/f4ah6o/dsh.mbt/actions/runs/39333896007)
and [the cancel/rearm run](https://github.com/f4ah6o/dsh.mbt/actions/runs/39335731870).

On 2026-10-20, [PR #74](https://github.com/f4ah6o/dsh.mbt/pull/74) merged as
`a56c1bbe6e940673c8997e44ccf7836a28eae377` after final head
`7201a050a63f14129b12ebefde7697db7342ad67` passed all three hosted workflows:
[native assets](https://github.com/f4ah6o/dsh.mbt/actions/runs/39369670556),
[runtime/browser](https://github.com/f4ah6o/dsh.mbt/actions/runs/39369670751),
and [Windows runtime](https://github.com/f4ah6o/dsh.mbt/actions/runs/39369670578).
The native-assets run passed Linux x86-64 and ARM64 Wayland synthetic
composition/finish-rearm and X11 baseline acceptance (composition remains false
on X11). Both architectures passed the unchanged exact-text active-worker
oracle with the full `Create and verify a durable file. via Linux keyboard`
prompt, including the repaired initial `Cr`. The actual Wayland registry traces
advertised text-input-v1; these results use published gpui 0.10.2, not a local
override. Post-merge [runtime/browser](https://github.com/f4ah6o/dsh.mbt/actions/runs/39371351921)
and [Windows runtime](https://github.com/f4ah6o/dsh.mbt/actions/runs/39371351814)
also passed; these runs are separate from packaged Linux acceptance.

Synthetic headless transport evidence is not physical IME qualification. Real
IBus/Mozc candidate popup placement, conversion and candidate selection remain
NOT RUN until tested on the bounded Weston 14 desktop-shell + stock IBus 1.5.32
synchronous adapter profile. Follow gpui's `docs/ubuntu-ime.md` for that profile.
Check Japanese conversion, Escape, Enter, Send, focus loss, Settings and session
switching on a physical display, recording results separately from test hooks.

Application-requested finish commits the host's cached preedit; text-input-v1
has no application-side request to accept the current IME candidate. This may
differ from the candidate selected in the input method. Surrounding deletion,
postinsert selection and full-editor operations are not supported here.
