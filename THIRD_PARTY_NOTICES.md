# Third-party notices

## DeepSeek Harness

This project ports selected behavior from
[deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness),
commit `5badb15009ae1756c3afe0ae0cef1faafc290ccc` (0.2.1-alpha.1).

Copyright (c) 2026 DeepSeek. Licensed under the MIT License. The original notice
is retained in [LICENSE](LICENSE). Source provenance appears in the provider
package and in the extracted test fixtures, including the 25 JSONL archives
under upstream `snapshots/session/`. Per-fixture source paths and SHA-256
digests are recorded beside the files. The original TypeScript runtime is not
shipped or invoked by this project.

## gpui.mbt

The `vendor/gpui` Git submodule pins
[gpui-mbt/gpui.mbt](https://github.com/gpui-mbt/gpui.mbt) at
`7335e13abe85c65d2a0f60571adc68faa8e64cdd`. Its MoonBit module name is
`f4ah6o/gpui`.

Licensed under Apache License 2.0; see [vendor/gpui/LICENSE](vendor/gpui/LICENSE).
[web/canvas-renderer.js](web/canvas-renderer.js) is copied from
`examples/browser/site/canvas-renderer.js` at that revision. Only its provenance
header is added here; it remains covered by the upstream Apache license.

## Yami-kumo application shell

`ui/yami-kumo/AppShell.tsx` and `ui/yami-kumo/styles.css` are adapted from
[f4ah6o/Yami-kumo](https://github.com/f4ah6o/Yami-kumo/tree/de8e3a3e167df2d721273f6a8f12c5df961d636d),
commit `de8e3a3e167df2d721273f6a8f12c5df961d636d`. The source repository is
owned by the project author; the pinned revision has no LICENSE file. The
application-shell code is retained here at the author's request and its source
revision is recorded alongside the files.

The browser bundle includes React and React DOM 19.1.1. Both are licensed under
the MIT License:

```text
MIT License

Copyright (c) Meta Platforms, Inc. and affiliates.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

esbuild 0.28.2 is a development-only build dependency and is licensed under
MIT. Copyright (c) 2020 Evan Wallace. Its license text is available in the
locked npm package and is not included in the browser bundle.

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
`4d9baaa258c695e803a487283076e979e2c260ba` (module `f4ah6o/turtles`, version 0.3.0).
It is used to execute mutation tests and is not bundled in the application.
Licensed under MIT; see [tools/turtles/LICENSE](tools/turtles/LICENSE).

## Runtime dependencies

MoonBit core is supplied by the pinned MoonBit toolchain, and Node.js supplies
the HTTP, filesystem, subprocess, and UTF-8 transport primitives. The browser
uses React for Yami-kumo's shell, plus standard Canvas 2D and DOM APIs. React is
bundled into the committed browser shell; npm packages are not loaded by the
Node or native host at runtime.
