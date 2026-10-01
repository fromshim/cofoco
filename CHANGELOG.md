# Changelog

## 2026-10-01 — native pet app connected

Added `packages/cofoco-app/`: SwiftUI/AppKit pet and speech bubbles using the shared authenticated owner service. List/detail/Step/Note controls, proposal review, history, Project/folder/grant settings, Trash, local custom PNG/WebP pets, quiet/reduced-motion behavior and opt-in macOS notifications are connected. The bundled default is original code-drawn art; Usagi reference assets are not shipped.

- Added owner event/grant reads and detail/child/review/settings routes; corrected legacy Project event-source decoding without weakening owner/MCP isolation.
- Added automatic helper lifecycle, nonblocking Quit, parent-loss monitoring, app/store locks, unread queue persistence and identical-key pending-request recovery. [ADR 0005](docs/decisions/0005-desktop-owner-channel.md) records owner HTTP/cursor polling instead of the spike's planned pipe.
- Automated suites: core 27/27, service 3/3, CLI 7/7, app 11/11. Native smoke verified capture/Step/Note, Project creation, MCP proposal preview/owner acceptance, status/interaction deferral, Step/Trash restoration, custom import, hide/restore, app restart and forced-helper-loss recovery. Optimized bundle/local signature verification passed.
- Lifecycle regression passed three rapid helper restart/clean-exit cycles and wrapper-parent loss; actual native app force-quit also cleaned its helper and recovered saved UI data on relaunch. Fixed socket reuse and background callback actor isolation exposed by these checks.
- [Evidence and limits](docs/native-app.md) keep full accessibility/platform checks, OS notification delivery, second-provider/setup, dogfooding and public signing/notarization open. Step 4 implementation does not declare V1 launch acceptance.

## 2026-09-29 — first local CLI/MCP integration

Added a minimal Swift `cofoco` owner CLI and a loopback Swift service hosting the existing core with separate Keychain-backed owner/integration credentials. The authenticated MCP adapter exposes the first Todo/Step/Note tool surface without an approval bypass or direct SQLite access by agents.

- Verified a real isolated Claude Code 2.1.284 session creating, listing, starting and rereading a Personal Todo through MCP; an independent owner CLI read confirmed `in_progress` at revision 2. A separate Claude session reread it after another initialize without a service restart.
- Fixed repeat-initialize and concurrent JSON-RPC ID handling with per-grant serialized SDK contexts. Service tests 2/2 and CLI tests 7/7 passed; core test verification and remaining gates are recorded in [the integration note](docs/local-integration.md).
- Provider registration is manual, Codex CLI is untested, and the service is not yet app-managed or release-packaged. No V1 acceptance row or product release is claimed. This entry does not imply a commit or push.

## 2026-09-29 — standalone Cofoco core

Added `packages/cofoco-core/`: a Swift/SQLite Todo, Step, Note and Project store behind a shared application service. It implements revision conflicts, scoped integration grants, durable events and idempotency receipts, protected-change proposals with atomic owner review, soft deletion, folder bindings and a tested v1→v2 backup migration.

- Verified 26/26 core tests for retry/no-op, rollback, scope/revocation, status pinning, stale/group approval, restart and backup restoration; independently reran 26/26 preserved Git-engine tests and typecheck.
- [Core implementation notes](docs/core-service.md) distinguish tested policy from the unbuilt MCP/CLI transport, hosted helper, pet UI and real-provider validation. No V1 end-to-end acceptance row is claimed.
- The approved UI/runtime experiment files from the prior step remain in the working tree; this entry does not imply a commit or release.

## 2026-09-28 — UI approval and native macOS runtime decision

The owner approved the Cofoco UI baseline. A parallel window/service/packaging experiment selected SwiftUI/AppKit, a bundled Swift service helper and system SQLite3; [ADR 0004](docs/decisions/0004-macos-runtime.md) records defaults, evidence and limits.

- Added reproducible, isolated [experiment build/verification scripts](experiments/macos-runtime/README.md) and [window](docs/experiments/window-spike.md), [service](docs/experiments/service-spike.md), and [packaging](docs/experiments/packaging-spike.md) reports.
- Verified an optimized, locally ad-hoc-signed arm64 app, native window/helper health and clean shutdown, SQLite atomic state/event/receipt, revision/retry behavior, WAL-aware migration backup and single-service ownership. Fixed an AppKit termination wait and missing standard Edit shortcuts during integration.
- The coordinator independently reran PKG-01–09 successfully and exercised final-app focus, Korean paste and pet hide/restore on macOS 26.5.2. Geometry uses synthetic screen cases; macOS 14 is a deployment target, not a tested older-OS claim.
- Marked UI Todo 2 done and the runtime Step of Todo 3 done. Production Todo/MCP/CLI/pet features and all V1 acceptance rows remain unimplemented/unverified. Native experiments do not replace the preserved Git-engine tests.

## 2026-09-25 — Cofoco product name

Renamed the active product identity from TodoCrew to Cofoco in the product contract, architecture, backlog, UI direction, design guidance, handoff, and wireframe wordmark. The local checkout and existing documentation/design asset paths are preserved. No feature code was implemented.

- Set the planned app package/CLI identity to `cofoco` and the MCP tool prefix to `cofoco_`; the preserved Git-engine workspace metadata remains unchanged.
- Recorded the name decision and preserved the earlier TodoCrew decision as historical context in [ADR 0003](docs/decisions/0003-product-name-cofoco.md).
- User-supplied Usagi assets remain wireframe references only and are not approved as distributable Cofoco app artwork.

See [product specification](docs/product-spec.md), [architecture](docs/architecture.md), and [V1 backlog](docs/vertical-slice-1.md). The rename changes no V1 behavior contract.

## 2026-09-07 — TodoCrew V1 contract

Specification/package identity update; no TodoCrew feature implementation.

- Finalized TodoCrew / `todocrew`; updated active docs, agent guidance and handoff.
- Reduced Todo status to open/in_progress/done; added one-level Steps, authored Notes and soft deletion/Trash.
- Defined logical flat Projects with optional folder bindings and Personal independent of agent execution.
- Recorded the user-selected hybrid mutation policy: automatic capture/start/Steps, reviewed important Todo changes.
- Defined stale-write/proposal handling, atomic reviewed change sets and global credential scope semantics.
- Specified stable pet list behavior and Todo-level feedback without Step notification noise.
- Set initial macOS validation scope and documented the remaining runtime/wireframe decisions.
- Recast V1 work as coarse Todos/Steps with 32 acceptance scenarios.

See [ADR 0002](docs/decisions/0002-todocrew-v1.md) for decisions and [V1 backlog](docs/vertical-slice-1.md) for remaining work. Existing engine tests are preservation checks only.

Verification on 2026-09-07: 26/26 legacy tests and typecheck passed; all 12 relocated source/test files match the tagged original byte-for-byte; the tag still resolves to `974ca87`. Active-document relative links and current-name references were checked. No TodoCrew acceptance scenario has been executed yet.

## 2026-09-04 — Omija → AgenTODO product pivot

Historical working name; current identity and product contract are superseded by the 2026-09-07 entry.

This entry records a repository/specification transition, not an AgenTODO feature release.

- Preserved original Omija Phase 0 at `974ca87`, annotated tag `omija-phase0`.
- Renamed product/package identity to AgenTODO/`agentodo`; removed the root legacy CLI bin registration.
- Defined the pet-with-todo-speech-bubble product, shared Todo ownership, flat scopes, provenance, and notification behavior.
- Established [current product spec](docs/product-spec.md), [architecture](docs/architecture.md), [active slice/backlog](docs/vertical-slice-1.md), and agent context guidance.
- Parked unchanged Git source/tests in `packages/git-engine`; archived original ADE docs and the old orchestration skill.
- Added [pivot decision](docs/decisions/0001-pivot-omija-to-agentodo.md) and [session handoff](docs/handoffs/omija-to-todocrew.md) (handoff since updated for TodoCrew).

Verification: original and relocated Git tests/typecheck; no claim of new Todo/UI/MCP implementation. Follow-up is the runtime spike and all unchecked implementation/acceptance items in [vertical slice 1](docs/vertical-slice-1.md).

The local checkout path and any external app/project/skill installations remain unchanged. No remote rename, push, or session message was sent.
