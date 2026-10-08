# Third-party notices

## DeepSeek Harness

This project ports selected behavior from
[deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness),
commit `5badb15009ae1756c3afe0ae0cef1faafc290ccc` (0.2.1-alpha.1).

Copyright (c) 2026 DeepSeek. Licensed under the MIT License. The original notice
is retained in [LICENSE](LICENSE). Source provenance appears in the provider
package and extracted test fixtures, including the 25 JSONL archives under
upstream `snapshots/session/`. Per-fixture source paths and SHA-256 digests are
recorded beside the files. The original TypeScript runtime is not shipped or
invoked.

## gpui.mbt

The `vendor/gpui` Git submodule pins
[gpui-mbt/gpui.mbt](https://github.com/gpui-mbt/gpui.mbt) at
`7335e13abe85c65d2a0f60571adc68faa8e64cdd`. Its MoonBit module name is
`f4ah6o/gpui`. Licensed under Apache License 2.0; see
[`vendor/gpui/LICENSE`](vendor/gpui/LICENSE).

## Yami-kumo and Cloudflare Kumo

The browser package consumes Mooncakes module `f4ah6o/yami_kumo` version
`0.1.0`, published from
[f4ah6o/Yami-kumo](https://github.com/f4ah6o/Yami-kumo) at merged revision
`0f6828647864930ef1c3022604beac36dcbd0781`. Its MoonBit shell, DOM adapter,
and CSS are installed from `.mooncakes/f4ah6o/yami_kumo`. This project does not
claim the package source under its own MIT license; see the copied upstream
license at [`licenses/yami-kumo-LICENSE`](licenses/yami-kumo-LICENSE).

The distributed `web/kumo-standalone.css` and
`web/yami-kumo-components.css` come from that package. The Kumo-derived
stylesheet and generated component contracts come from
`@cloudflare/kumo` 2.14.0 and are licensed under MIT; the upstream license is
reproduced at
[`licenses/yami-kumo-cloudflare-kumo-LICENSE`](licenses/yami-kumo-cloudflare-kumo-LICENSE).
`web/kumo-standalone.css` also identifies Tailwind CSS 4.1.17 and its MIT
license in its header. `web/yami-kumo-shell.css` is this project's stylesheet,
assembled from `ui/yami-kumo/styles.css` and `ui/dsh.css`.

## hotpath.mbt

The `vendor/hotpath` submodule pins
[gpui-mbt/hotpath.mbt](https://github.com/gpui-mbt/hotpath.mbt) at
`be4cb98a3eb61bd5ab176c9e5e6bd921b74d1dce`. Its module name is
`f4ah6o/hotpath`. The pinned revision does not declare a license in its module
manifest and does not contain a standalone LICENSE file. Its source remains a
separate upstream submodule; this project's MIT declaration does not relicense
it. License metadata clarification is tracked in
[the remaining port work](issues/open/0001-upstream-parity.md).

## turtles.mbt

The development-only `tools/turtles` submodule pins
[gpui-mbt/turtles.mbt](https://github.com/gpui-mbt/turtles.mbt) at
`4d9baaa258c695e803a487283076e979e2c260ba` (module `f4ah6o/turtles`, version
0.3.0). It is used to execute mutation tests and is not bundled in the
application. Licensed under MIT; see [`tools/turtles/LICENSE`](tools/turtles/LICENSE).

## Runtime and development tooling

The native product runtime is a MoonBit executable. Browser and service-worker
JavaScript are generated from MoonBit packages and use standard browser APIs.
No Node.js package is loaded by the native or browser product at runtime.
`playwright-core` is a pinned test-only dependency used by the real-browser
smoke fixture; other Node scripts are build and verification tooling.
