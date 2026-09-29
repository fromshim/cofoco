# Cofoco working agreements

## Current product

- Product/wordmark: **Cofoco**; planned app package/current Swift CLI: `cofoco`. The current root package remains the preserved Git-engine workspace.
- A local-first todo companion shared by a user and their agents. Initial V1 delivery/validation is macOS, one OS user, one local store.
- Desktop pet with a Todo speech bubble is the primary interface.
- Personal and logical Projects are flat scopes. Projects bind zero or more folders; `All` is a view.
- Todo is a coarse independent commitment; optional one-level Steps are internal milestones; Notes are context.
- Todo status is exactly `open | in_progress | done`. Step checks do not complete the parent. Soft deletion/Trash are separate.
- List header uses one `Todo ▾` scope control; a selected scope name replaces `Todo`. The main list has no internal separators or meta footer. At rest, capture is a circular `+`; it opens a borderless natural-language composer with a Project selector above and Personal selected by default. Row UI: checkbox + one-character project mark + title, hover/focus play action to start, animated `…` for in-progress. The animation communicates Todo status only and becomes static under Reduce Motion. The mark is colored text without a chip; hover/focus exposes only the Project name. Todo detail shows the full Project name above the title. Bound directories stay in Project settings. No live agent/needs-you/blocked states.
- The wireframe may use user-supplied character references for flow review, but distributable defaults require confirmed rights or original art. V1 custom pets are local image imports, not an in-app generation service: idle is required; working (in-progress dance), noticed (alert-present alternating arm circle with a subtle head bob), and resting poses are optional fallbacks. Do not upload or moderate imported pet files through a Cofoco server.
- Hybrid policy: agent capture/start/Step maintenance can be automatic; important existing Todo changes require owner approval in the app. Explicit user status choices remain protected after rereading.
- The standalone Swift core exists in `packages/cofoco-core/`; initial authenticated local MCP service and minimal CLI exist in `packages/cofoco-service/` and `packages/cofoco-cli/`. One isolated Claude Code integration has been verified. Provider setup remains manual; the pet app and second-provider integration do not yet exist. IDE/Git GUI, agent launch/supervision, automatic Git discovery, cloud/mobile/team features and other desktop OS releases are deferred.
- The UI baseline is owner-approved. [ADR 0004](docs/decisions/0004-macos-runtime.md) selects SwiftUI/AppKit + bundled Swift service + system SQLite3. `experiments/macos-runtime/` is an isolated feasibility probe, not production feature code; do not promote its fixture schema, raw health HTTP parser or synchronous shutdown unchanged.

## Source of truth

Read in order:

1. `docs/product-spec.md` — V1 product contract.
2. `docs/architecture.md` — ownership, revision, approval, permissions and interface contracts.
3. `docs/vertical-slice-1.md` — current Todo/Step backlog and acceptance evidence.

`docs/decisions/0002-todocrew-v1.md` records the V1 behavior contract; [ADR 0003](docs/decisions/0003-product-name-cofoco.md) records the current product name. ADR 0001 records the historical pivot and former working name, not current behavior. User's newer explicit instructions take precedence; reconcile contradictions rather than silently restoring old ideas.

## Historical boundaries

- `docs/archive/omija-ade/` is historical. Consult only for historical/Git-engine work.
- `packages/git-engine/` is parked. Do not extend or import it into the Todo core without an explicit Git integration request.
- The archived orchestration skill is ordinary Markdown, not an active/default workflow.
- Preserve `refs/omija/*`, preview paths, error names, and legacy CLI contract until a separate migration decision.
- Original baseline: tag `omija-phase0` at `974ca87`; never move the tag.
- Preserve the checkout path and saved-project/session context unless explicitly asked to rename them.

## Implementation and validation

- UI, CLI and MCP use one application service. Agents do not write SQLite directly.
- Todo/Step IDs are application identities; optional provider session references are provenance, never live execution state.
- An agent ending, all Steps being checked, or a process disappearing does not prove Todo completion.
- Every committed semantic change has provenance and a durable event. State/event/receipt commit atomically. Retries/no-ops do not duplicate changes or alerts.
- A Todo and its children share one revision. Stale writes and stale proposal approvals conflict.
- No silent semantic upsert/merge. Use candidate search, explicit IDs, and proposals for ambiguity.
- MCP cannot approve its own proposals or impersonate owner authority. A global credential grants every session using it the same scopes; cwd is routing metadata, not isolation.
- Personal access is explicit opt-in. Scope filtering covers search, history, proposals and receipt replay.
- Todo/proposal changes have visible feedback; Step/Note changes only update details/history.
- Add meaningful feature tests as implementation lands. Existing `pnpm test` and `pnpm typecheck` validate only the preserved Git engine.
- Run `swift test --package-path packages/cofoco-core` for the actual Cofoco core; keep its SQLite tests separate from the isolated runtime experiment and legacy Git engine.
- Run `swift test --package-path packages/cofoco-service` and `swift test --package-path packages/cofoco-cli` for the transport and CLI. See `docs/local-integration.md` for the first-provider smoke evidence and limits.
- Documentation must distinguish accepted design, chosen implementation defaults, unimplemented features and verified evidence.
