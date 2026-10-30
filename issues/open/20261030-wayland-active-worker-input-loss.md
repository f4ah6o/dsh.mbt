# Surface and investigate repeated Wayland active-worker smoke exits

Status: open
Model: gpt-6
Created: 2026-10-30
Updated: 2026-10-30
Branch: fix/20261030-wayland-smoke-diagnostics

## 概要

Seven first-attempt Linux GUI jobs across PRs #87, #89, #91, #94, #95 and #96
reported `GUI exited before active-worker TERM test`. Their retained desktop
logs show `desktop failed: real keyboard input did not produce the expected
prompt`. This issue tracks the input loss and the diagnostics needed to prove
its cause. The harness change only surfaces the existing failure.

## 背景

The harness completes a Wayland demo, then launches a second `--offline-e2e`
app with a blocking write hook. It sends real OS keyboard/pointer input and
checks the exact user prompt before approving the write. Only after approval
and publication of the owned hook-child PID does the harness send TERM and
verify the worker tree has exited. An earlier app exit fails this gate.

## 問題

The early-exit assertion hid the app's own error, process status and log path.
Reading only the CI summary could therefore suggest a shutdown failure even
though the exact-text assertion failed before approval and worker startup.

The evidence below establishes a missing initial `C`, not a worker-cleanup
regression. Each durable `wayland/active-term/data/sessions.json` contains
`reate and verify a durable file. via Linux keyboard`; the required prompt is
`Create and verify a durable file. via Linux keyboard`. Each failed job's
preceding Wayland demo completed, its X11 smoke passed, and its dependency log
records published `f4ah6o/gpui@0.10.2`.

| PR | Architecture | Completed first-attempt job | Retained artifact |
| --- | --- | --- | --- |
| #87 | ARM64 | [124296182756](https://github.com/f4ah6o/dsh.mbt/actions/runs/41123549025/job/124296182756) | [13009583076](https://github.com/f4ah6o/dsh.mbt/actions/runs/41123549025/artifacts/13009583076) |
| #89 | x86-64 | [124300570730](https://github.com/f4ah6o/dsh.mbt/actions/runs/41124884673/job/124300570730) | [13010293496](https://github.com/f4ah6o/dsh.mbt/actions/runs/41124884673/artifacts/13010293496) |
| #91 | ARM64 | [124307995315](https://github.com/f4ah6o/dsh.mbt/actions/runs/41126983626/job/124307995315) | [13012155654](https://github.com/f4ah6o/dsh.mbt/actions/runs/41126983626/artifacts/13012155654) |
| #94 | ARM64 | [124316802877](https://github.com/f4ah6o/dsh.mbt/actions/runs/41129567354/job/124316802877) | [13012443094](https://github.com/f4ah6o/dsh.mbt/actions/runs/41129567354/artifacts/13012443094) |
| #95 | x86-64 | [124319233198](https://github.com/f4ah6o/dsh.mbt/actions/runs/41130295936/job/124319233198) | [13012712921](https://github.com/f4ah6o/dsh.mbt/actions/runs/41130295936/artifacts/13012712921) |
| #95 | ARM64 | [124319233369](https://github.com/f4ah6o/dsh.mbt/actions/runs/41130295936/job/124319233369) | [13012364315](https://github.com/f4ah6o/dsh.mbt/actions/runs/41130295936/artifacts/13012364315) |
| #96 | ARM64 | [124327504606](https://github.com/f4ah6o/dsh.mbt/actions/runs/41132704806/job/124327504606) | [13014336571](https://github.com/f4ah6o/dsh.mbt/actions/runs/41132704806/artifacts/13014336571) |

The [checked-in extracts](../../docs/evidence/wayland/20261030-active-term-exits.json)
preserve each ZIP hash, source paths, line numbers, prompt and selected protocol
lines before the seven-day artifacts expire. All seven traces show a compositor
preedit after the input request and before Ctrl+A (`r`, except #94's `d`). They
show Ctrl+A and the initial `C` key press delivered to the Wayland client, then
`hide_input_panel` and `deactivate`. The key delivery alone does not establish
that the corresponding native composition commit reached the application.

## 目標

Make early exit summaries identify the backend, return code, app-log path and
bounded `desktop failed:` diagnostic. Establish the application's cancellation
and native queue behavior before choosing a production fix for the input loss.

## 対象外

Changing input timing, retrying failed input, weakening exact-text equality,
skipping the GUI gate, altering production composition behavior or claiming
physical IME qualification is outside this diagnostics increment.

## 提案する方針

Re-read the completed process log before raising the exit assertion, then append
the last `desktop failed:` line, bounded to 1,000 characters, with backend,
return code and log path. Preserve failure on every early active-worker exit,
including status zero. Do not dump protocol traces or durable session payloads
into CI output.

[gpui PR #178](https://github.com/gpui-mbt/gpui.mbt/pull/178) is a draft,
deliberately failing callback fixture: with an active preedit, Ctrl+A is consumed
after a later `C` commit has already been queued; application cancellation then
revokes that unread commit. The seven traces match its input sequence closely.
They did not record the app's `finish_text_composition(false)` call, app-visible
composition state, or the native queued commit/revocation. Accordingly that
fixture demonstrates a candidate mechanism and does not prove these CI failures
share its cause. The earlier cancel/rearm ingress failure documented in
[Wayland qualification](../../docs/wayland-ime-composition.md) remains separate
historical evidence.

For a production fix, capture the app's consumed event sequence and preedit,
the cancellation caller and sequence, and native commit admission/revocation
for the failing input sequence. Preserve the target-switch tests that
intentionally revoke unread input. Compare against gpui #178 before changing
the cancellation contract.

## 受け入れ条件

- [x] Early exit output includes the inner failure, backend, return code and app log.
- [x] Regression tests reject early exit with either zero or nonzero status and cover final-log races and absent diagnostics.
- [x] Seven failure traces and durable missing-`C` prompts are recorded with source identifiers and hashes.
- [ ] Instrument a failing GUI run to establish the cancellation/commit path.
- [ ] Review and implement a production fix with target-switch revocation preserved.
- [ ] Pass the strict packaged Wayland and X11 GUI acceptance on x86-64 and ARM64 after that fix.

## テスト計画

Run `python3 scripts/test-smoke-release-linux.py`, replay the retained failure
logs through the diagnostic path, validate this issue and run `git diff --check`.
The pure tests/replays do not constitute a new GUI acceptance run. Hosted CI
continues to run the complete packaged GUI gate on both Linux architectures.

## リスク

Matching protocol sequences can tempt an unsupported root-cause claim. Keep
the app/native cancellation gap explicit. A passing rerun does not demonstrate
that intermittent input loss was repaired. Artifact URLs expire; checked-in
extracts preserve only the described evidence, not the complete logs or frames.

## 変更履歴

`CHANGES.md` impact: no — CI diagnostics and investigation evidence only; no
production behavior change.

## 注記

This issue remains open after the diagnostics change because the production
input-loss cause and fix have not been qualified.
