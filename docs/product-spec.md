# Cofoco V1 product specification

Status: **V1 contract; implementation pending**
Updated: 2026-09-25
Decision records: [V1 behavior contract](decisions/0002-todocrew-v1.md); [current product name](decisions/0003-product-name-cofoco.md)

## 1. Product and audience

**Cofoco keeps your commitments visible while you and your AI agents work across projects.**

- Product and wordmark: `Cofoco`; planned app package/future CLI: `cofoco`.
- Category: a desktop todo companion shared by a person and their agents.
- Primary UI: a desktop pet with a todo speech bubble above it.
- First audience: individuals juggling local Claude Code/Codex CLI sessions and personal errands.
- V1 target: one computer, one OS user, local persistence. macOS is the initial delivery/validation target, selected from the owner's current environment; other desktop platforms follow separately.

The list is useful without an agent. Agent integration is the initial differentiator; the user sees ordinary commitments. ADHD informs low-friction, low-distraction design without medical claims. The pet requires no feeding, streak maintenance, or care chores.

## 2. Todo, Step, and Note

| Element | Meaning | Where it appears |
|---|---|---|
| Todo | An independently meaningful commitment/outcome the user wants to remember | Main list |
| Step | A milestone or useful checkpoint within one Todo | Todo detail only |
| Note | Context, decisions, links, or evidence; no completion state | Todo detail only |

A Todo need not take a particular amount of time. “영양제 사기” and “사내 위키 하네싱 설계” are both valid. A Step deserves a separate Todo when the user would want to remember it independently upon returning tomorrow.

- Exactly one level: Todo → ordered Steps. Steps cannot contain children, own scopes, or appear in All independently.
- A Step has a title and a done checkbox. No separate in-progress state, assignee, deadline, or dependency graph.
- Steps are optional, user-editable, and primarily help agents retain meaningful progress. Suggested working size is 3–7; this is guidance, not a schema limit.
- Do not mirror tool calls, temporary debugging plans, or every implementation action into Steps.
- All Steps done does not complete the Todo. Completing a Todo does not check remaining Steps. Reopening preserves their checks.
- Users may complete a Todo with unchecked Steps; show their count in details without blocking completion.
- Notes are appendable entries with author/source. Agents can append evidence and edit their own entries; replacing or deleting user-authored Notes requires confirmation.
- A user edit protects a Note from subsequent automatic agent replacement even when the Note was originally agent-authored.
- Step counts may appear in details, never masquerade as the Todo's completion percentage.

## 3. Personal and flat projects

Each Todo belongs to exactly one storage scope: **Personal / 내 할 일**, or a named **Project / 프로젝트**. **All / 전체** is an aggregate view. Projects are flat siblings with zero, one, or several explicit folder bindings. A project has a stable ID; a directory is a context hint, not its identity.

- Classification follows the commitment's purpose, not who executes it or which program/folder produced it.
- A recruitment agent can work on a Personal Todo with explicit Personal access. This does not move it into the agent's code project.
- Cross-repository outcomes can live in one logical project (for example Rescoop with server and FE folders), with Steps for each repository.
- Projects without folders can represent “취업 준비” or “2주년” if desired; V1 does not force these groupings.
- Users create/rename projects and bind folders in the UI. Agents do not silently create projects.
- Context resolution uses the longest registered containing real path. Non-Git folders work. Explicit aliases attach sibling folders/worktrees; automatic Git worktree discovery is deferred.
- Unrecognized `cwd` returns unresolved context and permitted choices. It never silently assigns an agent write to Personal.
- UI capture opens from a circular `+` and uses a borderless natural-language composer with a visible Project selector above it. Personal is always the default; the user may choose a Project before submitting.
- Moving a Todo preserves its ID, Steps, Notes, and history, and requires access to both scopes.

### Actual-list examples

These are classification examples, not imported user data or new commitments.

| Todo | Suggested scope | Possible Steps/Notes |
|---|---|---|
| rescoop-server last_inbound_at 컬럼 신설 및 기준 변경 | Rescoop | 컬럼/이관, 기준 변경, 검증 |
| rescoop server, rescoop fe 백로그 형식 수정 | Rescoop | server 적용, FE 적용, 일관성 확인 |
| 사내 wiki 훅 및 스킬 설계 | 사내 Wiki | 비개발자 PR 흐름, 훅, 스킬 계약 |
| 사내 위키 하네싱 고려 | 사내 Wiki | 영역 인덱싱, 최신성, Confluence 연계 검토 |
| Cofoco 설계 | Cofoco | 핵심 모델, 권한/알림, V1 범위 |
| 2주년 웹페이지 사진선정 및 이벤트 추출 | 2주년 웹페이지 | 사진 선정, 이벤트 추출 |
| 2주년 꽃 사기 | Personal | 꽃/수령 정보는 Note |
| 영양제 사기 | Personal | 구매 후보/링크는 Note |
| 취준 공고 2개 이상 | Personal | 탐색 기준과 지원 의도를 먼저 명확히 하기 |

“취준 공고 2개 이상” is ambiguous between finding and applying. Clarify intent before declaring it achieved. For discovery, propose “지원할 공고 2개 이상 선정하기”; for applications, keep submission as the completion criterion. Two links do not fulfill the latter.

Store unselected opportunities as Notes. Create “A사 지원하기” and “B사 지원하기” only when the user commits to those applications. If transforming the original commitment, present its title/status changes and proposed new Todos together. Accepting that group applies all changes atomically. V1 supports proposed change sets, not automatic semantic splitting/merging.

## 4. Status and row behavior

Only three Todo statuses exist:

| Value | Label | Row |
|---|---|---|
| `open` | 안 함 | Unchecked checkbox + title; hover/focus reveals `>` on the right |
| `in_progress` | 하는 중 | Unchecked checkbox + title + `…` on the right |
| `done` | 완료 | Checked checkbox + title |

- Checking open/in-progress completes it. Unchecking done reopens to `open`.
- Pressing `>` sets `in_progress`; it records intent to work without launching an agent.
- The `…` indicator exposes actions including returning to `open`. It is not an agent-alive signal or mandatory animated spinner.
- Start is accessible on keyboard focus with a readable label. Status is not conveyed only by color.
- Users can deliberately set any state. MCP requests the same transitions under the mutation policy.
- New Todos start as `open`; agent creation cannot bundle an unreviewed completion.
- There is no blocked, needs-you, dismissed, or agent-running Todo state. Blockers can be Notes.
- Delete is reversible soft deletion, separate from status. Trash preserves pre-deletion status and child content; restore recovers them. V1 has no automatic permanent purge.
- Agent silence, session ending, all Steps checked, or process exit never completes a Todo.

## 5. Human and agent changes

V1 uses the **hybrid policy selected by the user on 2026-09-07**. Automatic writes still require integration authentication, scope permission, revisions where applicable, and source/reason.

| Operation | User in app | Agent through MCP |
|---|---|---|
| Create an explicitly agreed Todo | Immediate | Automatic; uncertain/newly suggested commitments become proposals |
| Start `open → in_progress` | Immediate | Automatic unless that status was explicitly set by a user |
| Rename/change outcome, move, complete, reopen, return to open, delete, restore Todo | Immediate | Proposal requiring app confirmation |
| Add/edit/check/reorder/delete/restore Steps in an active Todo | Immediate | Automatic with revision checks |
| Append Note; edit/delete own Note | Immediate | Automatic with revision checks |
| Edit/delete another author's Note | Immediate | Proposal requiring app confirmation |
| Restore a deleted Note | Immediate | Proposal requiring app confirmation |

An explicit user status change pins that value against automatic agent transitions, even after rereading the latest revision. Confirming a proposed status change is also user action. Creating an item with default open status does not itself pin the status.

- Human authority comes from the trusted app/owner interface. MCP payloads such as `user_approved=true` cannot bypass confirmation.
- Proposals leave current Todo content/status intact. Pending proposals queue into one-at-a-time change bubbles above the Todo bubble, not a fourth Todo state or agent badge.
- Show before/after values, reason, and newly proposed Todos. Accept/reject individually or as an explicitly presented atomic group. Rejection leaves originals unchanged.
- Approval rechecks revisions and permissions. Changed targets invalidate the preview and require refreshed review.
- Agent Step/Note writes on completed/deleted Todos are rejected. An approved reopen/restore is required first. Users can edit completed details directly; deleted content must first be restored.
- Users reverse changes through ordinary edits/status controls, Step restoration, and Trash. History remains durable. Arbitrary historical rollback is deferred.

## 6. Capture, identity, and concurrent edits

Configured agents resolve permitted context, search existing Todos, read IDs/revisions, maintain durable commitments/Steps, and record meaningful outcomes. Integration instructions describe when to do this. MCP availability does not force tool invocation; unconfigured sessions and missed captures remain possible.

- Stable Todo IDs persist across sessions. Several sessions may contribute; no exclusive session ownership.
- Search same-scope active Todos before creation. Similar/equal titles return candidates, never prove identity.
- Updates target an explicit ID and revision. No semantic upsert or silent merge.
- Ambiguous matches become a proposal referencing candidates. The user chooses an existing item or approves separate creation.
- Concurrent creations can still produce semantic duplicates with different keys. V1 guarantees operational idempotency, not perfect semantic uniqueness.
- Same actor/key/payload returns its original result, including proposals. Reusing a key with different input is an error. No-ops emit no new semantic event or notification.
- Stale writes conflict. Rereading permits a fresh operation, not overriding protected user decisions.
- Source metadata identifies an integration and optional conversation reference. No live session state, heartbeat, or agent dashboard.

## 7. Pet, list, and notifications

- The dense Todo bubble is the complete, scrollable list in the selected scope; there is no separate expanded list. Its header is a single `Todo ▾` scope control, and a selected Personal/Project scope name replaces `Todo`. Todo detail replaces the bubble content and is usable without CLI.
- Active rows have stable manual order. New/reopened Todos append. Agent activity never sorts the list.
- Completed items enter a collapsed Completed section after interaction ends, not while the row retains pointer/focus.
- Remember scope; another project's event never navigates or steals focus. The main list uses no internal separator lines or persistent meta footer. Each row places one colored character between status and title; hover/focus reveals only the full Project name. Bound directories remain in Project settings. Color derives from stable Project ID. Hover/focus reveals a play action for `open`; `in_progress` shows a gently sequenced `…` animation with a long rest between cycles and a static reduced-motion fallback. This animation means only that the Todo status is `in_progress`, never that an agent session is live. Todo detail shows the full Project name above the title. There is no live agent badge.
- Required surfaces: main Todo bubble, Todo details/Steps/Notes, one-at-a-time change/proposal bubble, history and approvals, Trash, project/folder settings, integration setup.
- All routine Todo/Step/Note operations and proposal reviews are possible in the app.
- Every committed Todo creation/edit/status/move/delete/restore has history and visible feedback. Background Todo changes create a change bubble; while any change/proposal remains visible, the open pet uses its noticed pose. User changes receive inline feedback without a second popup.
- Step/Note changes update details/history without separate popups or pet animations. A new proposal triggers one review notification.
- Rapid related Todo changes may share presentation; their events remain individually inspectable. Retries/no-ops do not notify.
- OS notifications are off by default, opt-in for Todo changes/proposals. Quiet mode suppresses transient reactions, not history/unread changes. Denied OS permission does not prevent use.
- Menu-bar restore, movable pet, keyboard operation, and reduced motion are required. Hiding changes no data; no focus stealing or inactivity punishment.
- V1 supports a local custom pet image set grouped into `idle`, `working`, `noticed`, and `resting` motions. Idle requires at least one image; each group accepts one or more ordered frames, a one-frame group remains static, and missing optional groups fall back to idle. The setup guide asks for a stand/neutral-blink pair, a three-image alert-present arm circle (`1-2-3-2-1`) whose very short arms overlap in front of the torso while the head subtly bobs forward/back, a three-image in-progress dance (`A-B-A-C-A`) whose face and ears stay upright while the lower body sways and the same left hand points, and a lie/exhale-inhale pair on a consistent transparent canvas. Frames within a motion preserve character size and face-to-body proportion; the renderer swaps complete assets rather than manufacturing motion by translating or rotating one frame. Pose selection is strict: closed bubble uses resting; an open bubble with any visible alert uses the noticed arm circle; otherwise a visible in-progress Todo uses the working dance; otherwise idle. Imported assets stay on-device and are not uploaded for generation or moderation. Setup may provide a downloadable template and copyable prompt for use in an external image tool, but Cofoco does not bundle an image-generation API or require a particular provider. The importer accepts user-selected images without attempting to determine their licensing; the UI reminds the owner that they are responsible for usage rights. A distributable built-in pet still requires original or licensed art.

The [V1 UI direction and wireframe](ui-direction.md) settle review-candidate dimensions, placement, assets, and animation within this behavior contract.

## 8. Local integration and privacy

UI, small CLI, and MCP use one local application service and SQLite store. Existing local Claude Code/Codex CLI sessions report updates. No separate model API key is needed for this reporting. V1 uses MCP plus setup/instruction adapters; a marketplace plugin and lifecycle hooks are not prerequisites.

Installation grants explicit scopes to an integration. Personal is opt-in. **A global credential can access all of its granted scopes from any session using it.** `cwd` only routes context, not security between those sessions. Finer separation requires separately scoped credentials. Setup must explain this.

No cloud sync, mobile app, remote bridge, transcripts, shell history scraping, or screen monitoring in V1. Store data outside repositories. Agents can send permitted Todo data to their model provider in ordinary use; local storage does not mean that provider never sees it.

The CLI covers capture/query/status and app/integration diagnostics. Routine use and approvals remain possible in the app. [Architecture](architecture.md) specifies interfaces.

## 9. Delivery and non-goals

V1 requires the pet plus two real local providers sharing a durable list across at least two project contexts, with permissions, visible changes, restart recovery, and no stale overwrite. [Vertical slice 1](vertical-slice-1.md) defines acceptance evidence.

Deferred: other desktop OS releases, mobile/cloud/team features, IDE/Git GUI/worktree orchestration, agent launching/live supervision, session presence/heartbeat, automatic Git discovery, scheduling/recurrence/calendar sync, nested Steps, execution DAGs, semantic merge/embedding services, universal undo, and guaranteed capture. Preserved Git code is not a V1 dependency.

## Change history

- 2026-09-08: Dense borderless list, project marks, play/in-progress motion, detail hierarchy, and deferred live-session presence clarified in [UI direction](ui-direction.md).
- 2026-09-07: V1 behavior contract (then named TodoCrew); [decision](decisions/0002-todocrew-v1.md).
- 2026-09-25: Product/wordmark renamed to Cofoco; [decision](decisions/0003-product-name-cofoco.md).
- 2026-09-04: Original Omija-to-AgenTODO direction in [ADR 0001](decisions/0001-pivot-omija-to-agentodo.md); superseded details are historical.
