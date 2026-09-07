# TodoCrew working agreements

## Current product

- Product/wordmark: **TodoCrew**; package/future CLI: `todocrew`.
- A local-first todo companion shared by a user and their agents. Initial V1 delivery/validation is macOS, one OS user, one local store.
- Desktop pet with a Todo speech bubble is the primary interface.
- Personal and logical Projects are flat scopes. Projects bind zero or more folders; `All` is a view.
- Todo is a coarse independent commitment; optional one-level Steps are internal milestones; Notes are context.
- Todo status is exactly `open | in_progress | done`. Step checks do not complete the parent. Soft deletion/Trash are separate.
- Row UI: checkbox + title, hover/focus `>` to start, `…` for in-progress. No live agent/needs-you/blocked states.
- Hybrid policy: agent capture/start/Step maintenance can be automatic; important existing Todo changes require owner approval in the app. Explicit user status choices remain protected after rereading.
- No TodoCrew feature code exists yet. IDE/Git GUI, agent launch/supervision, automatic Git discovery, cloud/mobile/team features and other desktop OS releases are deferred.

## Source of truth

Read in order:

1. `docs/product-spec.md` — V1 product contract.
2. `docs/architecture.md` — ownership, revision, approval, permissions and interface contracts.
3. `docs/vertical-slice-1.md` — current Todo/Step backlog and acceptance evidence.

`docs/decisions/0002-todocrew-v1.md` records the latest decisions and chosen defaults. ADR 0001 records the historical pivot and former working name, not current behavior. User's newer explicit instructions take precedence; reconcile contradictions rather than silently restoring old ideas.

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
- Documentation must distinguish accepted design, chosen implementation defaults, unimplemented features and verified evidence.
