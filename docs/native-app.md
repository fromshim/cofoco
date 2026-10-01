# Cofoco native app — Step 4

Status: **native implementation connected; isolated desktop smoke verified; full V1/release acceptance pending**
Updated: 2026-10-01

## Implementation

`packages/cofoco-app/` builds a macOS 14-target SwiftUI app hosted in a borderless AppKit `NSPanel`. The app uses the same authenticated local owner API as the CLI; it never opens SQLite. [ADR 0005](decisions/0005-desktop-owner-channel.md) records the change from the spike's proposed private owner pipe to the existing Keychain-backed HTTP capability.

The dense 324-point main bubble has scope selection, colored one-character Project marks, checkbox/play/dots controls, Personal-default capture and a collapsed Completed section. Completed rows stay under the pointer/focus until interaction ends. Detail replaces the list and exposes project/title/status, Step add/edit/check/reorder/delete/restore, Note append/edit/delete/restore and history. Trash restores the Todo with its former status and children. Settings exposes Project rename/folder bindings, scoped integration grant/revocation, local pet imports, quiet mode and opt-in macOS notifications. Provider registration remains manual: an app-created grant is not an installed or live provider connection.

Todo text is captured literally; there is no embedded model, natural-language parser, auto-splitting or image-generation service. The composer accepts ordinary language. Configured external agents supply semantic capture through MCP.

System material, colors, SF Symbols and accessibility preferences are used. Reduce Motion makes the progress dots and imported pet frames static; Reduce Transparency uses an opaque semantic background. The distributed default is an original code-drawn pebble, not the Usagi wireframe character. Local imports accept PNG/WebP without character/licensing detection and stay on-device. Idle is required; optional missing motion groups fall back to idle, including its motion timing. Frames are imported in filename order, so use `01`, `02`, `03` names. A single frame is static.

## Lifecycle and recovery

- App data: `~/Library/Application Support/Cofoco/`; new directories are private to the OS user. Preferences remember scope, quiet/notification settings and the pet anchor. Core data, events, proposals and receipts stay in `cofoco.sqlite3`.
- One advisory app lock and the existing core-store lifetime lock prevent competing app/store owners. The app probes schema version 1 and starts the bundled `Contents/Helpers/cofoco-service` when unavailable. It polls every two seconds rather than opening a push subscription.
- Startup captures an event cursor before reading the snapshot, then replays from it. Todo/proposal snapshots and history are paginated. The event cursor and unread Todo-event queue persist atomically in `event-inbox.json`; pending proposals are reread from the service. Step/Note events update detail/history only.
- A mutation is journaled before sending. Transport retry and restart replay retain the original method/path/payload/key; `pending-mutation.json` contains no bearer secret. Other writes wait while its outcome is unknown. Definitive rejection retains form content for correction; recovered captures clear matching drafts. Editing title/Step/Note/Project text uses the revision at editing start rather than silently adopting a later background revision.
- Hiding keeps the service alive. Quit asynchronously terminates an app-owned helper, with a three-second forced-stop fallback. The service stops accepting new work and drains tracked requests on SIGTERM/SIGINT. App-launched helpers monitor their actual parent PID so app process loss does not leave an unintended helper. A pre-existing manually launched service is reused, not terminated by app Quit.
- In-app queues/history are authoritative. OS notifications are off by default, ask macOS permission when enabled, and persist delivery-attempt IDs to avoid repeated attempts. OS delivery is best effort. Quiet mode suppresses transient reactions without deleting unread records or approval requests.

## Build and run

```bash
swift test --package-path packages/cofoco-app
bash packages/cofoco-app/scripts/build-local.sh
```

The build script prints a unique `Cofoco.app` path under the ignored `.build/local-bundles/` folder. Open that exact bundle. It contains the optimized app and helper, signed locally ad hoc; no installed Swift/Node/Python runtime is needed by the resulting app. This is not a notarized installer. Build scripts/tests require developer tooling.

For an isolated DEBUG smoke, build with `COFOCO_BUILD_CONFIGURATION=debug`, then launch the executable with all three overrides: `COFOCO_DATA_ROOT` (a new temporary directory), `COFOCO_KEYCHAIN_SERVICE` (`com.fromshim.cofoco.desktop-smoke.<unique-id>`) and `COFOCO_PREFERENCES_SUITE` (the same unique namespace). Release builds ignore these overrides. Do not run a debug fixture against production credentials or a competing service.

The script accepts `COFOCO_APP_SCRATCH` and `COFOCO_SERVICE_SCRATCH` for writable SwiftPM caches. In the sandbox, tests used `--disable-sandbox`, `/private/tmp/cofoco-*-build` scratch paths and `CLANG_MODULE_CACHE_PATH=/private/tmp/cofoco-clang-cache`.

Create `앱 UI 스모크 테스트` through the isolated app. `packages/cofoco-app/scripts/desktop-fixtures.py propose|capture|inspect|revoke --keychain-service <isolated-namespace>` supplies/revokes test-only MCP fixtures without printing credentials. It is a protocol test client, **not** second-provider evidence or an owner-approval bypass.

## Evidence on 2026-10-01

The working tree following checkpoint `69450dc` was tested on the development arm64 Mac. macOS 14 remains a deployment target, not an execution claim.

| Check | Observed result |
|---|---|
| Automated packages | Core 27/27; service 3/3; CLI 7/7; app 11/11. App tests cover lost-response identical-body/key replay, durable pending request/unread queue, local import/source removal, idle fallback, image validation, motion/rest and transparent hit-region geometry |
| Native capture/detail | Personal Todo created through the app; Step and Note entered and read back; Project created in Settings |
| Protected MCP change | Test MCP rename returned `proposed` with original unchanged; separate change bubble showed actor/reason/before→after; clicking app Approve changed the exact Todo title |
| Row status/focus | Play set in-progress; checkbox completed; completed row remained under interaction, then moved to Completed after pointer/focus moved to capture; unchecking reopened it |
| Deletion | Step soft-deleted and restored through detail; Todo moved to Trash and restored through the app |
| Custom pet | One user-selected Usagi **reference** image imported in the isolated store; idle became available and covered optional slots. No reference asset is included in the app bundle |
| Restart | Todo/title/Step/Note, unread MCP-created-Todo bubble and imported pet survived app Quit/relaunch. Hide/pet-click restore preserved the same unread bubble |
| Helper loss | SIGKILL of the exact isolated helper PID caused unavailable/disabled controls, followed by a new helper PID and healthy service with existing Todos/unread alert preserved |
| Parent loss/rapid restart | Three helper start→health traffic→SIGTERM cycles exited cleanly with the port closed. An isolated wrapper-parent SIGKILL removed its helper; actual native app SIGKILL also removed the helper/closed the port, then app relaunch recovered Todos/Step/Note, unread alert and imported pet |
| Quit/build | App Quit removed its app/helper processes and closed the service port. Optimized app/helper build and `codesign --verify --deep --strict` passed |

Isolated fixture data remains under `/private/tmp/cofoco-desktop-smoke.qec5RU`; credentials are revoked/cleaned after validation. No provider-global configuration was installed. The fixture protocol client does not replace the real Claude evidence in [local integration](local-integration.md).

`packages/cofoco-app/scripts/verify-lifecycle.py --help` describes the bounded helper regression check. Run it against an isolated namespace with no existing service. Rapid restart required `SO_REUSEADDR`; signal/parent-monitor and app termination/pipe callbacks explicitly use `@Sendable` to avoid inheriting main-actor isolation on background queues.

## Remaining validation and limits

Full VoiceOver/keyboard traversal, actual Reduce Motion/Transparency toggles, transparent pointer pass-through over another app, physical display disconnect/Spaces/full-screen, OS notification permission/denial/delivery and signed release Keychain access need human/environment verification. Forced helper/app loss, parent cleanup and ordinary restart passed; an actual in-flight crash/lost-response restart still requires process-boundary evidence in addition to unit tests.

The service's existing-Todo group approvals work in core, but grouped MCP proposal creation is still deferred. Provider install/remove, real Codex integration, two-provider conflicts across two projects, three-day dogfooding and public distribution signing/notarization remain V1/release gates. No whole acceptance-matrix row or complete V1 launch is claimed here.
