# Changelog

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
