# Cofoco V1 architecture

Status: **V1 behavioral/ownership contract; runtime selection pending; not implemented**
Updated: 2026-09-25
Product contract: [product spec](product-spec.md)

## 1. Boundary and local lifecycle

```text
Pet + bubble / trusted owner UI ─┐
cofoco CLI ─────────────────────┼─ Local application service ─ SQLite
Claude / Codex ─ MCP adapter ───┘           │
                               Durable events + proposals
                                          │
                                Snapshot/event subscription
```

One local service owns policy and mutations. UI, CLI, and MCP cannot independently write the store. MCP is an adapter, not an additional database or embedded reasoning model.

The app starts/reconnects its service automatically. Closing a bubble/hiding the pet keeps the service running. Explicit Quit stops the service after committed writes finish; MCP then reports retryable unavailability. A CLI or MCP bridge must not silently initialize a competing store. A single-instance lock prevents simultaneous owners of the same database.

Initial target is macOS. The later runtime spike chooses desktop framework, IPC, SQLite driver, service packaging/startup, credential storage, and installer/distribution details. This specification does not claim a tested toolkit or provider configuration format.

## 2. Domain records

| Record | Required fields and behavior |
|---|---|
| Project | Stable ID, name, timestamps, revision; zero or more folder bindings. Personal is null project_id; All has no stored record |
| FolderBinding | Project ID, canonical real root; one root cannot map to multiple projects. Longest containing root wins |
| Todo | Stable ID, title, project_id, status, revision, order_key, timestamps, deleted_at, status_authority, source |
| Step | ID, todo_id, title, is_done, order_key, deleted_at, source/timestamps; exactly one parent |
| Note | ID, todo_id, text, deleted_at, author/source, timestamps; no status |
| IntegrationGrant | Authenticated integration ID, credential reference, explicit allowed scopes, read/write permissions, revocation |
| ChangeProposal | ID, proposed operations/preview, target revisions, source/reason, state, timestamps, review result |
| ChangeEvent | Monotonic cursor/ID, aggregate ID, actor/source, operation, before/after, reason, resulting revision, timestamp |
| OperationReceipt | Actor + idempotency key, request fingerprint, stable result |
| NotificationDelivery | Event/proposal reference, channel, coalescing reference, delivery state |

IDs are application-generated opaque identifiers. No path, title, provider session ID, or legacy Git task ID is a primary Todo identity.

Todo `status` is only `open | in_progress | done`. Soft deletion is separate. `status_authority` distinguishes default/agent/user decisions. Explicit user status writes (including approved proposals) protect the status against subsequent automatic agent start. An unchanged default-open creation is not an explicit status decision.

A Todo and its Steps/Notes form one revisioned aggregate. Every committed child write increments the parent revision. This deliberately causes some conflicts between independent Step edits in V1, but makes proposals and stale-write protection predictable. Step/Note fields have stable IDs; arrays are not replaced wholesale. Reorder supplies the complete current live Step ID order, checked against the aggregate revision.

Notes edited by a user become protected from later automatic agent replacement, including originally agent-authored Notes. Author and last editor are retained. Step edits may be automatic after rereading; current revision and change history apply to both user- and agent-created Steps.

Todo deletion masks all children without destroying them. Restore clears its deletion marker, retaining status and child checks/tombstones. Child deletes are also reversible. No cascading permanent purge or arbitrary historical rollback in V1.

Provider/session references are optional event metadata only. There is no live SessionObservation entity, process watcher, lease, heartbeat, or exclusive agent assignment.

## 3. Scope and authorization

- Project identity is logical; registered roots are explicit aliases. Moving a folder requires a binding update. No automatic project creation, remote-URL merge, or Git worktree discovery.
- Resolve normalized real paths and containing roots, then intersect with the authenticated grant. Unknown/unpermitted context returns unresolved/denied without leaking other scope details.
- All/list/search/history endpoints apply the same scope filtering as item reads. Child and proposal endpoints inherit parent/destination permissions.
- Moving a Todo needs source and destination access. Its history follows the Todo into the destination; explain this with the move preview. Existing source-only credentials lose access after the move.
- Credentials represent integrations/grants, not model-supplied provider names or working directories.
- A global registration shared by multiple sessions gives those sessions its full grant. Directory routing cannot isolate those sessions from each other. Separately scoped registrations are needed for separation.
- Personal access is off until explicitly granted. Denied and unknown IDs should not disclose private titles, revisions, or event payloads.
- Local credentials constrain supported app API access, not arbitrary shell/file access by processes already running as the same OS user.
- Trusted owner approval uses a separate capability from MCP. No MCP approval endpoint or payload flag can impersonate a human.

## 4. Mutation protocol

All writes, including approvals and project settings, use the application service:

1. Authenticate the actor and check current permission before returning data, including cached results.
2. Look up actor/key receipt; same fingerprint returns the original result. Different input with the same key returns `idempotency_mismatch`.
3. Validate IDs/payload/parents/scopes. Existing Todo mutations require `expected_revision`.
4. Apply the product mutation policy; either commit an allowed change, store a proposal, or return an explicit error/conflict.
5. Commit state, revision, durable event(s), and receipt in one SQLite transaction.
6. Publish committed events; delivery is independently retryable.

Reject stale writes before applying any part. Clients may reread, reconcile, and submit a fresh key. User-pinned status cannot be overwritten just by rereading. Check authorization before revealing current state with a conflict response.

No-ops after revision/policy validation return `noop` without advancing the aggregate or emitting a semantic event. Receipt replay keeps its original result/event IDs. After revocation, cached receipts cannot disclose inaccessible content.

A successful creation assigns ID/order once with `status=open` and default status authority. No agent create payload bypasses review by initializing a completed Todo. New/reopened Todos append to stable active order; other edits do not reorder. Deleted and completed records are filtered into separate UI sections without changing Step checks.

Use SQLite transactions/constraints and a single logical writer. Crash after commit but before response recovers through the receipt; crash before commit leaves no partial state. Migrations must be versioned and backup/recovery behavior documented in the runtime spike. Storage lives in the OS application-data directory, outside the repo.

## 5. Proposals and approvals

An agent's protected mutation returns `proposed` with a proposal ID, not mutation success. Todo state/revision does not change until acceptance. Proposals have `pending | accepted | rejected | stale` lifecycle; these values are not Todo statuses.

A proposal contains typed operations, exact IDs/revisions, human-readable before/after, actor, and reason. A reviewed change set may atomically rename/complete a Todo and create follow-up Todos. Proposed new IDs are reserved for that set. References must resolve within the set or to accessible existing records.

The owner UI is the approval surface for V1:

- Show the complete proposed change set and scope effects.
- Acceptance rechecks all expected revisions, current grant, parent state, and destination permissions in one transaction.
- Any revision conflict, unexpected parent/deletion state, or revoked permission prevents every operation; mark the proposal stale and show refresh/review feedback. A restore operation expects a deleted target and is validated against that state.
- A refreshed proposal is a new reviewable record; an agent cannot silently alter an existing preview.
- Reject records review history and changes no Todo. Repeated delivery/review is idempotent.
- Rejected identical proposals are not automatically resubmitted; integration guidance requires new evidence/user intent.
- Approval events identify the owner as reviewer and preserve the proposing integration as source.
- Partial acceptance of an atomic group is unavailable; individual independent proposals can be accepted separately.

Agents can auto-create explicitly agreed commitments, start eligible open Todos, maintain Steps, and append/edit their own Notes. All other Todo mutations require proposals. Core policy is deterministic; the agent's claim that a new commitment was agreed remains a semantic judgment, observable through provenance, not something SQLite can prove.

Agent child writes require an active, non-deleted parent. A completed parent returns `parent_closed`; deleted returns `parent_deleted`. An approved reopen/restore must precede child writes. Users may edit completed details directly.

## 6. Identity and duplicate handling

Search is explicit and separate from mutation. Read/search returns IDs and revisions. Create never silently becomes update. Similar titles identify candidates only.

When identity is uncertain, request a proposal referring to the candidates; do not merge, reopen old work, or create speculative commitments automatically. Concurrent same-meaning creations with different keys can still coexist. There is no semantic uniqueness constraint. User reconciliation is ordinary editing/deletion, or an explicitly reviewed change set.

Cross-scope candidate disclosure is limited to the grant. Closed/deleted items never silently reappear because of a title match.

## 7. MCP V1 surface

All responses carry a schema version; lists are bounded/paginated. Mutations take an actor-scoped idempotency key and a reason. Existing Todo/child changes take the aggregate `expected_revision`.

| Tool | Required input / result |
|---|---|
| `cofoco_get_context` | Optional cwd → resolved permitted scope or unresolved, permitted choices, capture policy; no agent states |
| `cofoco_list_todos` | Explicit scope or permitted All, optional query/status, cursor/limit → summary IDs/titles/revisions |
| `cofoco_get_todo` | Todo ID → permitted Todo, Steps, Notes, revision and bounded recent changes |
| `cofoco_create_todo` | Explicit scope, title, source/reason, key → created Todo or proposed creation |
| `cofoco_update_todo` | ID, revision, explicit title/scope/status changes, key → policy-selected committed/proposed result |
| `cofoco_delete_todo` | ID, revision, reason/key → soft-delete proposal |
| `cofoco_restore_todo` | Deleted ID, revision, reason/key → restore proposal |
| `cofoco_update_step` | Todo ID/revision; tagged add/edit/check/reorder/delete/restore operation → new revision/event |
| `cofoco_update_note` | Todo ID/revision; tagged append/edit/delete/restore operation → committed or proposed result |
| `cofoco_propose_changes` | Typed atomic change set, expected revisions, optional duplicate candidates, reason/key → proposal |
| `cofoco_get_proposal` | Proposal ID → permitted review state/result, including accepted target IDs |

`create_todo` accepts an explicit proposal mode for uncertain commitments; `update_todo` automatically routes protected fields to review. A mixed patch requiring any protected change proposes the whole patch. Agent Note restore requires review; append/edit/delete of its own unprotected Note is automatic.

Stable outcomes: `created | updated | deleted | restored | noop | proposed`. Reads of proposal state distinguish approved changes from pending suggestions. Errors: `unavailable | permission_denied | unresolved_scope | not_found | conflict | invalid_input | idempotency_mismatch | parent_closed | parent_deleted`. Error responses never claim durable success.

Tools cannot register scopes, grant access, approve proposals, hard-delete records, launch agents, or write SQLite. Source metadata contains optional provider/session references but never changes actor authority.

## 8. CLI and provider setup

Minimal human CLI command families:

- `cofoco add`, `list`, `show`, `status` (open/in_progress/done).
- `cofoco open`.
- `cofoco integration install|status|remove`, `doctor`.

Capture/query/status support JSON. `status` denotes a Todo state edit, not agent supervision. Full Step/Note CRUD, approvals, or project-settings CLI parity is deferred; the app handles those. Owner CLI authentication is distinct from the MCP grant. The CLI is not advertised as a way for an agent to bypass review.

Intended MCP transport is one authenticated loopback Streamable HTTP endpoint. Bind locally, validate host/origin, and keep credentials out of logs. A stdio bridge, if needed by an installed provider version, forwards to the same service/store. Exact client setup must be verified against installed Claude/Codex versions and their current official documentation during implementation.

Setup is initiated by the owner, previews grants/config changes, preserves unrelated configuration, backs up changed files, installs idempotently, and removes only Cofoco-owned entries. Distinguish configured from actually connected. Supply short global capture instructions; do not promise a lifecycle hook or guaranteed reconciliation.

Neither a provider marketplace plugin nor a separate model service/API key is required by the contract. Remote/cloud/container sessions outside the service's local reach are deferred.

## 9. Events and presentation

Desktop loads a snapshot with event cursor and subscribes from that cursor without a race gap. On cursor expiry/gap, refetch. Events filtered by grant still allow opaque cursor progression without revealing inaccessible payloads.

Todo changes and new proposals produce transient feedback according to the product policy. Step/Note changes remain in history/details without separate alerts. Idempotent retries and no-ops do not create events. A single atomic change set may yield multiple inspectable semantic events and one notification presentation.

Durable notification records prevent duplicate app-level presentations on retry/reconnect. OS notification delivery is best effort, opt-in, and cannot guarantee exactly-once display; in-app history remains authoritative. Quiet/hide settings do not delete events.

## 10. Deferred implementation choices

Before feature code, produce a small runtime decision covering:

- macOS transparent window, input/focus, menu bar, positioning/multiple displays, accessibility;
- desktop framework and SQLite runtime compatibility;
- service single-instance/start/quit/recovery and protocol version compatibility;
- credential storage, grants, local IPC/HTTP and provider setup;
- database schema/migrations/backups and event subscription;
- app packaging and local installation.

These are engineering validation gates, not unsettled product behaviors. No new package forest or toolkit dependencies are introduced by this specification. Only the preserved `packages/git-engine/{src,test}` currently executes.
