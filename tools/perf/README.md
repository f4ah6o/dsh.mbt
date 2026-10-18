# Development performance checks

This is a separate, optional MoonBit module. Only this module imports hotpath;
the normal dsh module and workspace do not resolve it. Its nested workspace
uses the checked-out dsh module, the Mooncakes gpui.mbt package, and the
existing pinned `vendor/hotpath` submodule. Nothing here is needed to build,
test or run dsh. The root publication archive excludes this directory and
`vendor/hotpath`.

From the repository root, explicitly initialize the optional source and run:

```sh
git submodule update --init --recursive -- vendor/hotpath
moon -C tools/perf install
moon -C tools/perf test trace --target native
moon -C tools/perf run cmd/profile --target native --release
```

The fixed, keyless fixture uses the real `HarnessApi` to create and send a
session, project a provider stream, complete the effect and read the completed
session. It performs no network requests, tool execution or user-store access.
The harness records caller-side timings for those five operations. It does not
restore the removed runtime `profile_stats` capability, retain production
timings or measure allocations. The pinned hotpath source has existing
deprecation warnings; the normal product check no longer exempts warnings.

The existing uninstrumented engine benchmarks remain in the main module:

```sh
moon bench benchmarks/engine_core --target native --release
```

They retain the typed-command and compatibility-JSON one-turn traces and their
snapshot equality assertion. Compare runs on the same compiler, hardware and
fixtures; report samples and uncertainty rather than treating instrumentation
removal as evidence of a speedup. Historical results in `docs/verification.md`
and `docs/implementation-status.md` remain historical evidence.

The separation follows MoonBit's [module dependency configuration](https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html#dependency-management)
and [workspace support](https://docs.moonbitlang.com/en/latest/toolchain/moon/workspace.html).
It does not assume an undocumented MoonBit `devDependencies` field or treat a
test-only package import as removal of a module dependency.
