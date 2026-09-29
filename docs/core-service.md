# Cofoco standalone core — implementation evidence

Status: **implemented and SQLite-tested as a Swift package; now hosted by the initial local service, not yet by the pet app**
Updated: 2026-09-29

`packages/cofoco-core/` is the first production Todo feature code. `CoreService(path:)` is the public application boundary for Todo, Step, Note, Project, folder binding, grant and proposal operations. The initial [local service](local-integration.md) now authenticates owner and integration callers before invoking core; CLI/MCP do not write SQLite or decode an owner principal from tool input. The pet app's trusted UI channel, lifecycle and approval presentation remain to be built.

The core uses one SQLite connection with a transaction-wide lock and a process lock, WAL, full synchronous mode and foreign keys. Schema version 2 includes Projects/bindings/grants, revisioned Todo aggregates, child tombstones, events, idempotency receipts, grouped proposals and notification-delivery records. A v1→v2 upgrade takes a consistent online backup before migration; the test restores the backup into a new database. The owner supplies the eventual application-data path when constructing the service; the package does not choose or create a production app container.

Policy implemented here:

- Every committed semantic Todo/Step/Note or Project change, including review decisions, persists an event and receipt in the same transaction. Same actor/key/payload replays its original result; key reuse with changed input conflicts. No-ops make no semantic event.
- A Todo and its children share one revision. Agent create (when explicitly agreed), eligible start, Step maintenance and unprotected own-Note edits commit directly. Owner status choices, including a same-value open choice, pin status against automatic agent start. Protected changes become reviewable proposals.
- Proposal previews reserve IDs. Owner acceptance rechecks original revisions, proposer grant and source/destination scopes, then applies an entire group or none. Reject and stale states are durable and repeated review is idempotent. A group can combine changes to existing Todos with multiple new Todos. Referencing a newly reserved Todo from a later operation in that same group is not exposed by the current typed API; decide the client reference syntax before promising that narrower capability to MCP.
- Reads, search, history, proposals and receipt replay check current grants. Personal is opt-in. Explicit folder bindings resolve by canonical longest containing root; cwd is not authority. A move keeps Todo identity and history while removing access from a former source-only grant.

## Verification

On 2026-09-29, `swift test --package-path packages/cofoco-core` passed **26/26** macOS tests (in the restricted workspace, run with `--disable-sandbox` and writable scratch/module-cache paths). Tests cover retry/mismatch/no-op, event+receipt rollback, stale Todo/Step writes, Project revisions, owner status pinning, Note protection, proposal accept/reject/stale atomicity, grant revocation and cross-scope filtering, Trash/restore, realpath routing, single-writer lock, restart/lost-response replay, v1→v2 backup restoration and review-provenance spoof rejection. `pnpm test` passed **26/26** preserved Git-engine tests and `pnpm typecheck` passed; those are separate evidence.

This core-only checkpoint does **not** establish a shipping app or full V1 acceptance. The subsequent [local integration](local-integration.md) adds CLI/MCP adapters, a live service, Keychain-backed credentials and one isolated Claude Code smoke. Event subscription/notification delivery, UI approval channel, forced-kill recovery, cross-process stress, persistent provider setup and Codex CLI verification are still missing. The native-window experiment proves feasibility, not an integrated pet app.
