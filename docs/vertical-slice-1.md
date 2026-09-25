# Cofoco V1 — backlog and acceptance

Status: **V1 contract finalized; feature implementation not started**
Updated: 2026-09-25

## Outcome and current evidence

A user manages coarse personal/project Todos and optional Steps through a pet bubble. Local Claude Code and Codex CLI sessions share the same permitted durable records. Important agent changes receive user review; routine progress does not overwhelm the main list.

The original Omija baseline is commit `974ca87`, tag `omija-phase0`. Git source/tests are preserved under `packages/git-engine`; ADE documents and the inactive skill are archived. These are preservation work, not Cofoco features.

Current executable code is only the Git engine. Todo core, SQLite, daemon, MCP, CLI and desktop pet remain unimplemented. The existing 26 tests/typecheck validate the engine only.

## Coarse Todos for building V1

This is a documentation backlog using the intended Todo/Step structure, not data already stored in an app. Parent completion is a deliberate decision, not a checkbox rollup.

### Todo 0 — Cofoco 제품명 확정 · done

- [x] Select Cofoco; package/future executable `cofoco`.
- [x] Update active product identity and current context while preserving the local checkout and existing documentation paths.
- [x] Record the rename from TodoCrew in [ADR 0003](decisions/0003-product-name-cofoco.md).
- Note: historical names/ref namespaces stay identifiable; domain registration/trademark clearance are not claimed.

### Todo 1 — Cofoco V1 설계 확정 · done

- [x] Reconcile current docs against user decisions in [ADR 0002](decisions/0002-todocrew-v1.md) and update the name under [ADR 0003](decisions/0003-product-name-cofoco.md).
- [x] Define Todo/Step/Note, flat scopes, three statuses, and deletion.
- [x] Record the user-selected hybrid mutation policy and review/conflict behavior.
- [x] Define service ownership, MCP contract, notifications, V1 limits, and acceptance evidence.
- Note: runtime/toolkit validation remains a separate engineering gate; no feature completion implied.

### Todo 2 — Cofoco UI 방향 및 와이어프레임 완성 · in_progress

- [x] Wireframe the dense main Todo bubble and Todo detail with Steps/Notes; remove the separate expanded list.
- [x] Specify checkbox/play/animated `…`, project marks, keyboard/focus behavior, ordering and scope navigation.
- [x] Reduce the main list to borderless rows plus a floating `+`; reveal a Personal-default Project selector and natural-language composer only on demand.
- [x] Wireframe one-at-a-time change/proposal bubbles, history, Trash, project/folder settings, and integration grants.
- [x] Validate proposal/conflict/error/empty/reconnect states with the examples below.
- [x] Select a review-candidate pet visual direction and reduced-motion/quiet presentation.
- [x] Generate and wire four smooth outlined motion groups with two real frames each, a shared action/rest rhythm, and single-image source swapping; specify multi-frame local custom-pet import and external prompt handoff without an in-app generation API.
- [ ] Review the [UI direction](ui-direction.md) and [interactive wireframe](wireframes/todocrew-v1.html) with the owner; incorporate feedback and deliberately mark this Todo done.
- Note: wireframes can be static; full pet asset production is not required to validate the flow.

### Todo 3 — 로컬 코어와 MCP 연결 완성 · open

- [ ] Run the macOS shell/service/SQLite compatibility spike; record runtime and distribution choices.
- [ ] Implement logical projects/folder bindings, Todo/Step/Note aggregates, events, revisions, receipts and soft deletion.
- [ ] Implement hybrid policy, protected user status, proposals and atomic acceptance.
- [ ] Implement shared application API and the minimal CLI.
- [ ] Implement authenticated MCP with one provider first, then the second.
- [ ] Provide idempotent user-scope setup/removal and connection diagnostics.
- [ ] Add meaningful core/MCP tests for permission, retry, conflicts, proposals and restart.
- Note: use a developer-level trusted approval test harness until the pet review UI exists. It must not ship as an MCP approval bypass.

### Todo 4 — 데스크톱 펫 V1 완성 · open

- [ ] Implement the approved pet/bubble/list/detail wireframes against the same core.
- [ ] Implement user CRUD, Step/Note editing, proposal acceptance/rejection, project settings, and Trash.
- [ ] Subscribe to committed events with snapshot/reconnect recovery.
- [ ] Implement stable ordering, history, quiet/reduced-motion settings and optional OS notifications.
- [ ] Implement menu-bar restore, service lifecycle and a locally installable macOS build.
- Note: no agent status badge, process launching, Git GUI or cloud dependency.

### Todo 5 — 실제 두 에이전트 사용 검증 및 V1 판정 · open

- [ ] Configure real local Claude Code and Codex CLI sessions across two projects.
- [ ] Start managing the remaining Cofoco build Todos in Cofoco itself.
- [ ] Execute the acceptance matrix and link automated/manual evidence.
- [ ] Use it on at least three ordinary workdays; record capture omissions, false captures, duplicates, stale state and notification burden.
- [ ] Resolve critical data loss, permission, approval-bypass, false-success and stale-overwrite issues; record remaining limitations.
- Note: three days is the initial observation window, not a claim of statistical validation.

## Acceptance matrix

All rows require passing evidence before declaring V1 complete. Use isolated fixture data for destructive/concurrency checks.

| ID | Scenario | Required observable result |
|---|---|---|
| A01 | Personal capture and All | Personal Todo appears in Personal/All, not a project; opening capture from any list visibly defaults to Personal and allows an explicit Project choice |
| A02 | Logical project | Two explicitly bound repositories resolve to one Project; a folderless project also works |
| A03 | Unknown directory/worktree | Known subdirectory resolves; unknown root remains unresolved; explicitly bound worktree resolves without Git engine |
| A04 | AI working on personal task | Authorized agent keeps recruitment Todo in Personal regardless of cwd; no Personal grant means denied |
| A05 | Row status controls | Checkbox completes/reopens; hover/focus play starts; `…` rises/settles sequentially with a long rest, is static under Reduce Motion, and can return to open; it never claims live-agent presence; no fourth state |
| A06 | Step boundary | Steps appear only in details, cannot nest or own scope; all checked leaves parent status unchanged |
| A07 | Independent completion | Completing parent leaves unfinished Step checks intact; reopen preserves child state |
| A08 | Routine agent changes | Explicitly agreed create, eligible start and active-parent Step edits commit automatically with source/history |
| A09 | Important agent changes | Rename/move/done/reopen/delete/restore produce proposals; current Todo stays unchanged until owner accepts |
| A10 | Pinned user status | Agent cannot auto-start an explicitly user-reset open Todo, even after rereading; proposal is required |
| A11 | Human authority | MCP provider/user_approved fields cannot accept proposals or impersonate owner |
| A12 | Proposal review | Accept commits exact preview; reject changes no Todo; repeated review creates no duplicate mutation |
| A13 | Stale/group proposal | Change one target before approval; whole group fails with refreshed-review feedback, no partial new Todos |
| A14 | Recruitment semantics | Two found links cannot complete “apply twice”; candidates stay Notes until actual application commitments |
| A15 | User-authored Note | Agent append succeeds; replacement/deletion of user's text requires approval |
| A16 | Completed/deleted parent | Agent child edit fails visibly until approved reopen/restore; no hidden writes under a closed item |
| A17 | Trash | Delete preserves prior status/Steps/Notes, hides normal rows; restore recovers them; child restoration works |
| A18 | Restart/crash | Committed content/events/proposals survive restart; retry after lost response returns original receipt |
| A19 | Two providers same Todo | Both read one ID; stale second write conflicts without overwriting first, including competing Step edits |
| A20 | Retries/no-ops | Same actor/key/payload has one result/event; different payload with same key errors; no-op does not notify |
| A21 | Similar titles | Search returns candidates, ambiguous identity is reviewed; no silent merge/update/reopen |
| A22 | Permission filtering | ID/path/search/All/history/proposal/receipt calls cannot expose ungranted scopes; revocation applies to cached results |
| A23 | Global registration | Setup clearly explains shared grant across sessions; separate grants enforce configured isolation |
| A24 | Move | ID/children/history preserved; source and destination access checked; old source-only grant loses access |
| A25 | Feedback burden | Todo/proposal notifications appear; Step/Note changes only update detail/history; rapid events coalesce without losing history |
| A26 | OS denial/quiet | OS delivery denied or disabled leaves usable history; quiet suppresses transient reactions, not records |
| A27 | Stable list/focus | Agent events do not sort/navigate/steal focus; completed row does not disappear under pointer/focus |
| A28 | Pet visibility and custom poses | Hide/restore changes no Todo; keyboard operation and reduced motion work; one imported idle image covers every slot, while optional working/noticed/resting ordered frames swap without layout shift and never leave the device; pose priority is closed/resting > open with visible alert/noticed > in-progress/working > idle |
| A29 | Lifecycle/outage | App starts one service; hiding keeps it; Quit causes visible MCP unavailability, never false success |
| A30 | Setup and removal | Reinstall is idempotent; unrelated config preserved; removal affects only app entries; configured/connected distinct |
| A31 | Source-only sessions | Agent exit/silence changes no Todo; no live status tracking or assumed completion |
| A32 | Normal human use | Required add/edit/move/status/Steps/Notes/review/Trash/settings flows work without CLI |

## Completion evidence format

For each ID, record build/commit, automated test or manual steps, expected/actual result and date. Record which installed provider versions were used. No acceptance row is currently verified for Cofoco.

The dogfood note should include at least one real missed/false capture review (or an explicit observation of none), notification burden, and whether coarse Todos stayed understandable without opening every Step. A high Todo count is not a success metric.

## Explicitly deferred

Windows/Linux releases, mobile/cloud sync, teams, calendar/recurrence, agent supervision/launching, session presence/heartbeat, IDE/Git UI, automatic worktree discovery, nested task trees, semantic merge services, arbitrary undo and transcript observers.

## References

- [Product specification](product-spec.md)
- [Architecture](architecture.md)
- [V1 behavior contract](decisions/0002-todocrew-v1.md)
- [Current product name](decisions/0003-product-name-cofoco.md)
- [Current handoff](handoffs/omija-to-todocrew.md)
- [Changelog](../CHANGELOG.md)
