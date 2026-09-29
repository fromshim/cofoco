# ADR 0004 — Native macOS runtime for Cofoco V1

Date: 2026-09-28
Status: **Accepted runtime direction; feasibility verified on the development Mac; production implementation pending**

## Context and decision

The owner approved the existing UI baseline and requested a small window/service/SQLite/packaging experiment before feature implementation. V1 targets one Mac and prioritizes native materials, input, an accessory window and a menu-bar recovery path. The HTML wireframe remains a design reference.

Choose the following implementation defaults:

| Boundary | Choice |
|---|---|
| Desktop UI | SwiftUI content hosted in AppKit `NSPanel`; AppKit owns activation, positioning, dragging, screen changes and `NSStatusItem` |
| Material/accessibility | System `NSVisualEffectView` material with an opaque semantic-color fallback; system appearance and accessibility preferences. This does not promise an exact Liquid Glass rendering on every OS |
| Application service | A bundled native Swift helper launched by the app with `Process`; one logical writer, explicit readiness/version handshake and an advisory lifetime lock for the store |
| Storage | System SQLite3 through the Swift C module; prepared statements, serialized mutations, WAL, foreign keys and `synchronous=FULL`. State/event/receipt share a transaction |
| App/service IPC | An inherited private pipe for owner bootstrap and the planned versioned owner channel; the experiment validates readiness delivery, not production owner commands or subscriptions |
| External API | Authenticated loopback HTTP for CLI/MCP with distinct owner and integration authority. Use the official Swift MCP SDK and a maintained HTTP host when implementing MCP; pin and test their versions then |
| Credentials | Keychain-backed persistent credentials, separate integration grants and owner capability. The experiment uses an ephemeral health token supplied only through the private pipe; Keychain integration remains unimplemented |
| Packaging | A self-contained `.app` with its helper in `Contents/Helpers`, `LSUIElement=true`, helper-first signing. Local development uses ad-hoc signing; public distribution will need Developer ID signing/notarization |
| Compatibility | Deployment target macOS 14.0; current verification is arm64 on macOS 26.5.2. Older macOS and Intel support must not be advertised from compiler compatibility alone |

No installed Node, Python, Homebrew runtime or browser engine is required by the built app/helper. Python is used only by the developer's experiment verification scripts. Production source should be organized as shared Swift domain/service modules plus app/CLI/MCP adapters; the preserved Git-engine workspace remains independent.

Tauri and Electron were reviewed from their official documentation but not built or benchmarked. Both can support desktop products. SwiftUI/AppKit fits the approved macOS-only delivery and gives direct ownership of the window and system material behavior demonstrated here. This decision makes no comparative memory or performance claim. See the [experiment README](../../experiments/macos-runtime/README.md) for alternative references.

## Lifecycle and storage contracts

The app starts or deliberately reconnects its single service. Hiding the bubble leaves both processes alive. Explicit Quit stops accepting new writes, drains the current transaction and stops the service; a stopped service must report unavailability to clients. A parent-process loss must not leave an unintended service/store owner. The prototype proves single-instance rejection, SIGTERM handling and parent-exit detection; production crash/restart supervision still needs implementation and tests.

The production store belongs in macOS Application Support outside repositories. Versioned migrations reject newer unknown schemas, take a consistent SQLite online backup before upgrading existing data, and commit schema/version changes atomically. Backup restoration must be rehearsed before feature completion. The prototype validates WAL-aware backup contents and migration, not a complete recovery product.

Protocol versions must be checked before enabling clients. The private owner capability must never be granted by MCP fields or provider configuration. Integration permissions, scope filtering, proposal approval and durable snapshot/event replay remain the existing [architecture contract](../architecture.md); a successful health probe proves none of those features.

## Evidence and limits

The coordinator independently reran `scripts/verify.sh` on the final optimized bundle after the workers' runs. PKG-01 through PKG-09 passed with exit 0: bundle metadata, nested code signature, load commands, system-only dependencies, four geometry checks, SQLite self-test, process-boundary checks and bounded GUI smoke. The smoke reported `panel_visible=true`, `panel_key=false`, `helper_ready=true`, one screen and `termination=helper_exited`.

A separate coordinator negative test copied only the final window executable into an isolated temporary directory. With its bundled helper absent, the bounded smoke reported `helper_ready=false` and exited 1, confirming that missing service readiness is not reported as success.

The coordinator also operated the final app through desktop automation: `+` focused the field; ASCII typing, Command-A and Korean paste worked; hiding left the exact app/helper processes running; clicking the pet restored the bubble and entered text. A drag gesture was exercised, but screen displacement was not independently measured. This is tool-observed evidence, not a new owner visual-approval session.

Detailed evidence:

- [Window and input](../experiments/window-spike.md)
- [Service and SQLite](../experiments/service-spike.md)
- [Bundle and signing](../experiments/packaging-spike.md)
- [Reproduction commands](../../experiments/macos-runtime/README.md)

Two integration defects were fixed: the asynchronous AppKit termination reply hung in a nested event loop, and standard Edit shortcuts needed responder-chain menu items. The disposable probe uses a bounded synchronous child stop. Production shutdown must avoid blocking the UI and explicitly handle drain timeouts. Its hand-written health HTTP parser is also disposable and must not become the production MCP server.

Remaining validation belongs to the implementation/release gates: actual macOS 14/Intel execution; physical multi-display disconnect/repositioning and Spaces/full-screen; pointer pass-through around transparent regions; menu-bar recovery through desktop interaction; VoiceOver and real Reduce Motion/Transparency toggles; forced process crash/backup restoration; Keychain with signed binaries; real provider interoperability; and Developer ID/notarization. No V1 acceptance-matrix row is completed by this experiment alone.

## Consequence

The runtime selection gate is complete. Next implement the Swift local domain/application service and durable store, then CLI/MCP and the approved native UI. Keep these experiment sources under `experiments/`; do not promote the fixture schema, raw HTTP parser or debug window into production unchanged.

## Primary references

- [Apple SwiftUI/AppKit integration](https://developer.apple.com/documentation/swiftui/appkit-integration)
- [Apple NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview)
- [SQLite Online Backup API](https://www.sqlite.org/backup.html)
- [Official MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) — documented transport availability, not a dependency built in this experiment
- [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
