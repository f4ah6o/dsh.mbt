# iOS shared-client embedding spike

This sample hosts the portable MoonBit client inside a small SwiftUI app. It
connects to a dsh service over HTTPS, renders authorized session projections,
and sends revision-anchored commands. The Swift layer owns URLSession, secure
entropy, local preference storage, and scene lifecycle; command validation,
scope handling, draft/selection state, and receipt reconciliation live in the
shared MoonBit client.

The sample does not embed the dsh engine or the gpui.mbt UI. Its auth display
uses the service's credential-free projection and never reads OAuth secrets.

## Build and smoke checks

The repository pins MoonBit `0.10.14+7d59c7ec9`. The C bridge compiles the
matching runtime sources from `$MOON_HOME/lib/runtime` with the system
allocator. On iOS, the small `include/sys/random.h` compatibility header maps
the runtime's `getentropy` call to Apple's `arc4random_buf` API.

Run the host ABI lifecycle and UTF-8 smoke test:

```sh
sh ios/ClientEmbedding/verify-abi.sh
```

Generate the Xcode project and build for an installed simulator destination:

```sh
xcodegen generate \
  --spec ios/ClientEmbedding/project.yml \
  --project ios/ClientEmbedding
xcodebuild \
  -project ios/ClientEmbedding/DshClientEmbedding.xcodeproj \
  -scheme DshClientEmbedding \
  -destination 'platform=iOS Simulator,id=<simulator-udid>' \
  -derivedDataPath _build/ios-client-derived \
  build
```

The build phase always emits fresh client C in an isolated temporary target
directory, then compiles the generated source and pinned MoonBit runtime for
the selected Xcode SDK and architecture. It does not reuse host-compiled
objects.

## Validation record

On 2026-10-07, the host ABI smoke passed, and Xcode built, installed, and
launched the arm64 iOS Simulator sample with the iOS 18.5 runtime and Xcode
26.5 SDK. The simulator showed the initial connection screen with its
safe-area layout, and the source at that point included scene-phase reconnect
and explicit-button-only prompt submission. The later Swift follow-up that
removes persisted preferences after a verified authorization-scope change
and the unused-binding cleanup have not been rebuilt yet.

This is not physical-device acceptance. A connected iPhone, Japanese IME
composition, VoiceOver, real tailnet TLS/API behavior, and a native gpui.mbt
mobile host remain separate validation gates.
