# Cofoco V1 UI direction and wireframe specification

Status: **Owner-approved baseline; native implementation connected; full UX/platform acceptance pending**
Updated: 2026-10-01
Prototype: [interactive wireframe](wireframes/todocrew-v1.html)
Design tokens: [Cofoco design system](../design-system/todocrew/MASTER.md)

The owner explicitly approved this UI baseline on 2026-09-28 for the macOS runtime experiment and subsequent implementation. This approves the interaction and visual direction, not production acceptance or distribution rights for the reference character assets.

Step 4 now implements the primary surfaces in `packages/cofoco-app/`; [native app notes](native-app.md) distinguish observed desktop behavior from remaining accessibility/platform/release gates. Capture stores literal text, provider setup remains manual, and the bundled default is original code-drawn art. Local pet frames import in filename order rather than in-app generation.

## Direction

Cofoco is a native-feeling macOS desktop companion: a small borderless accessory window appears above a pet at the edge of the desktop. The HTML prototype is only a wireframe; the production app must behave like a macOS app and use system appearance, materials, focus, accessibility, and window conventions.

The chosen visual direction is **system monochrome + restrained glass**:

- no Cofoco key color; follow macOS light/dark appearance and the user's system accent;
- translucent blur/material around the bubble, with a quieter content layer for readable rows;
- compact system typography, SF Symbols in production, and desktop-density controls;
- project identity is the only recurring chroma, shown as one colored character with no chip container;
- no pet-care mechanics, streaks, confetti, live agent avatars, card dashboard, or constant motion.

The existing CSS crewmate has been replaced in the wireframe by a user-supplied Chiikawa Usagi reference set solely to validate pose swapping and scale. It is not an approved distributable default: Cofoco must not ship that character or generated derivatives without confirmed usage rights. Production therefore needs either a license or a clearly original mascot. Final illustration work follows asset-rights and flow approval.

The wireframe now uses a smooth outlined illustration set for all four motions. Its ten transparent reference frames share a normalized 768×512 canvas: idle stands and makes a neutral blink; noticed plays three separately drawn short-arm poses as `1-2-3-2-1`, with both arms overlapping and circling in front while the head subtly moves forward and back; working uses three images to play `A-B-A-C-A` while the yellow-suited lower body sways and the same left hand points without changing the face or ear angle; and resting lies down and breathes at a comparable visual mass. The renderer shows only one `<img>` and changes its source after every asset is preloaded, so drawings can never overlap; it does not create action by translating or rotating the frame. Idle and resting use a six-second loop with frame 2 from 450–1150ms. Noticed keeps every frame change and loop boundary 320ms apart, runs its 1.28-second sequence four times, and then rests on frame 1 for four seconds. Working uses the same four-loop-plus-rest condition at 160ms intervals, producing a 0.64-second sequence before the same four-second rest. Reduce Motion shows only the primary frame. This is still a flow prototype; production art needs final frame cleanup and rights approval.

## Window model

Cofoco has one anchored stack per active display:

1. **Pet only:** bubble hidden; click pet restores the Todo bubble. A menu-bar item can restore, move, open settings, or quit.
2. **Main Todo bubble:** about 324px wide. This is the complete list, not a compact preview. It scrolls when more Todos exist.
3. **Todo detail:** replaces the main bubble's content and can widen modestly for Steps and Notes.
4. **Change bubble:** an independent transient bubble directly above the Todo bubble. Only one queued change is presented at a time.

There is no separate expanded list or Changes tab. The stack grows upward from the pet anchor and clamps inside the visible screen. Pet and bubbles move as a unit. V1 does not require free-floating subwindows.

“Native on the desktop” is a product constraint. [ADR 0004](decisions/0004-macos-runtime.md) selects SwiftUI content with AppKit window/menu control after the runtime experiment. Production verification still includes transparent-region pointer behavior, menu-bar recovery, accessibility and physical multi-display placement; the experiment does not complete the shipping UI.

## Information architecture

```text
Change bubble (zero or one visible; queue may contain more)
└─ event receipt, or proposal review with Reject / Accept

Todo bubble
├─ Todo list: All / Personal / Project
│  └─ Todo detail: status, Steps, Notes, history
├─ Trash
└─ Settings
   ├─ Projects and folder bindings
   ├─ Integrations and scope grants
   └─ Appearance, quiet mode and notifications

Pet
```

Back from detail returns to the remembered list scope and scroll position. Escape closes a menu, then detail, then the Todo bubble; it never quits or changes a Todo.

## Pet poses and custom import

The pet renderer exposes four semantic slots:

| Slot | Used when | Required |
|---|---|---|
| `idle` | No current Todo activity needs emphasis | Yes |
| `working` | The visible context contains or shows an in-progress Todo | No; falls back to idle |
| `noticed` | The bubble is open and at least one Todo change or proposal remains visible | No; falls back to idle |
| `resting` | The Todo bubble is closed and only the pet remains | No; falls back to idle |

V1 imports local PNG or WebP files with transparency preferred. The app copies them into its Application Support data, normalizes display bounds without altering the originals, and never uploads them. Each semantic slot accepts one or more ordered frames. `idle` needs at least one image; a missing optional slot falls back to idle, while a one-frame slot remains static. The setup guide requests two frames for idle and resting plus three for noticed and working, so neutral blink, an alert-present `1-2-3-2-1` arm circle with a slight head bob, an `A-B-A-C-A` in-progress dance, and subtle breathing can be expressed. Arbitrary user-selected imagery is accepted; Cofoco does not perform automated character/licensing detection. Import copy states that the owner is responsible for usage rights, and sharing a pet pack/gallery is deferred.

Image generation remains outside the app in V1, so no developer API key or user API key is required. Pet settings show the four motion groups and provide a provider-neutral copyable prompt. They may optionally link to supported external tools such as Codex desktop or Gemini, but the workflow remains: generate/export elsewhere, then drag files into `idle`, `working`, `noticed`, and `resting`. A single idle image is still sufficient; adding the recommended second frame or the three optional groups progressively enables motion.

The V1 copyable prompt should be short and tool-neutral:

> 첨부한 캐릭터를 같은 외형과 선 스타일로 유지해 데스크톱 펫용 실제 투명 배경 PNG/WebP를 만들어주세요. 1) `idle` 서기 2장: 눈 뜸 / 웃는 눈이 아닌 중립적인 눈 감기, 2) `noticed` 알림용 팔 돌리기 3장: 매우 짧은 두 팔이 몸 앞에 붙어 서로 겹친 채 번갈아 위아래로 도는 자세. 1·3번은 고개가 조금 앞으로, 2번은 조금 뒤로 움직이며 `1-2-3-2-1` 순서로 이어져야 합니다, 3) `working` 진행용 춤추기 3장: A는 정면 중립 자세, B·C는 얼굴과 귀의 각도를 A와 같게 유지한 채 아래 몸통이 서로 반대 방향으로 쏠리고 캐릭터의 같은 왼손만 화면 오른쪽으로 뻗는 자세. `A-B-A-C-A` 순서로 재생할 수 있어야 합니다, 4) `resting` 눕기 2장: 내쉬기 / 몸통이 약간 들썩이는 들이쉬기. 모든 프레임은 같은 캔버스, 캐릭터 몸집, 얼굴 대 몸 비율, 기준선과 투명 알파를 유지하고 배경·체커보드·그림자·글자·말풍선·워터마크는 넣지 마세요. 이미지 생성 도구가 한 번에 여러 파일을 만들지 못하면 프레임별로 생성하세요.

The app labels the action “프롬프트 복사” rather than “Codex/Gemini에서 생성” so the core flow is not tied to a vendor. Provider shortcuts can be secondary conveniences when a stable launch link exists.

## Main Todo bubble

- Header begins with one `Todo ▾` filter and a small overflow menu. Choosing Personal or a Project replaces `Todo` with that scope name; choosing All restores `Todo`.
- Show active Todos in stable manual order inside one scrollable list. Completed is available from the menu; there is no footer or `+N more` expansion state.
- Row order is: status checkbox, project mark, one-line Todo title, start/more action.
- Open uses an empty checkbox and a hover/focus play action (`play.fill` in SF Symbols). In-progress uses an empty checkbox and visible `…`; its three dots briefly rise and settle in sequence, followed by a deliberately long quiet interval. Under Reduce Motion the `…` remains static. Done uses a checked checkbox and leaves the active list after pointer/focus leaves.
- The `…` motion communicates the persisted Todo status only. It must not claim that an agent is currently connected, running, paused, or touching the Todo.
- Clicking the title opens Todo detail. Status and right action are separate targets.
- The main surface has no internal separator lines. Spacing, alignment and a transient hover/focus fill provide hierarchy.
- Quick add is progressively disclosed: the resting list shows only a floating circular `+`. Activating it reveals a borderless natural-language composer with a Project selector above the input. Personal is the visible default regardless of the current list filter.
- A background Todo-level change updates the row and creates a receipt change bubble. It never reorders the list, navigates, or steals keyboard focus.

### Project mark

- Show exactly one colored character between checkbox and title, without a chip, pill, or filled background.
- Derive its hue from the stable Project ID, not the mutable name.
- Use a curated light/dark-safe palette. Hover or keyboard focus reveals only the full Project name; the accessibility label exposes the same name. Bound directories appear only in Project settings.
- Personal uses a neutral `P` mark. Color is redundant; the initial remains present for color-vision and monochrome contexts.
- Duplicate initials are acceptable because full labels remain available. A custom owner-selected mark is deferred.

## Todo detail

- Detail replaces the same bubble instead of opening an expanded shell or separate window.
- Header: Back and overflow menu. In the content, the full Project name sits above the Todo title; the list's one-character mark is not repeated. The title can be edited by the user inline.
- Status uses the same checkbox/start language as the list.
- Steps are an ordered checklist. “Add step” is quiet and secondary. Step actions include edit, move, delete/restore and produce no change bubble.
- Notes are timestamped/source-labeled blocks. User edits protect a Note from later automatic replacement.
- “3/3 steps” is supporting text only. Completion remains an explicit Todo action.
- History opens a chronological secondary surface. Agent provenance is available there and beside Notes, not as a live badge.

## Deferred agent presence

V1 records who made each committed change and may retain an optional provider conversation reference, but it does not observe whether Claude Code, Codex CLI, or another process is currently running. An MCP call proves only that a call occurred; it does not prove continued activity or distinguish running from paused.

A future presence experiment may add explicit short-lived activity leases (`begin` / heartbeat / `end`) and show one or more provider symbols near an in-progress row. Prefer individually recognizable symbols with accessible labels over a provider-color gradient: a gradient is harder to decode, depends on color alone, and cannot explain whether a missing provider stopped or merely lost its lease. Presence must remain ephemeral and must never alter the Todo's persisted `open | in_progress | done` state.

## Change bubbles and approval

- Todo-level creation/edit/status/move/delete/restore and proposal arrival can create a small bubble above the Todo list. User actions receive inline feedback and do not echo a second bubble.
- Present one queued event at a time with a queue position such as `1 of 3`; resolving/dismissing it advances to the next.
- A receipt bubble states the committed outcome and source, then can auto-dismiss after it has been seen. It remains available in history.
- A proposal bubble leads with the semantic outcome, then source/reason. It expands in place to show the exact current → proposed diff when needed.
- Atomic groups state that the changes apply together and list every rename/status/new Todo/scope effect.
- Reject is neutral; Accept uses the user's system-accent primary style. Destructive proposals use system warning semantics.
- If revisions changed, disable Accept, show “This Todo changed after the proposal,” and offer Refresh. No partial application.
- Change bubbles never become a fourth Todo status and do not imply that an agent is live.

## Trash, projects and integrations

- Trash and Settings are secondary screens reached from the bubble menu, not permanent tabs.
- Trash lists deleted title, scope, prior status and deletion time. Restore is per row; there is no permanent delete in V1.
- Project settings show logical project name followed by folder bindings. Add Folder uses a native chooser. Removing a binding does not delete Todos.
- Integration cards show provider, configured/connected distinction, and granted scopes.
- Personal access is a separate, initially-off grant. Grant copy says sessions sharing this configuration share all selected scopes; `cwd` only chooses context.

## Required exceptional states

| State | Presentation and recovery |
|---|---|
| Empty scope | Pet rests; “아직 할 일이 없어요” plus Add Todo |
| Service reconnecting | Non-blocking inline banner, controls temporarily disabled, automatic retry plus Retry now |
| Service unavailable | Persistent inline error with Open Cofoco/Retry; never show a write as saved |
| Unknown agent cwd | MCP returns choices; app shows an event only if a proposal/action needs review |
| Permission denied | Explain missing scope without exposing Todo title; Open integration settings |
| Proposal stale | Exact conflict message, disabled Accept, Refresh proposal |
| OS notification denied | In-app change/history works; settings explain how to enable system permission |
| Long title/large text | Main row truncates; detail wraps; actions and accessible description remain intact |
| Reduce Transparency | Use opaque semantic system backgrounds and stronger separators |

## Keyboard and accessibility

- Logical order: scope → menu → list rows (status, project mark/title, action) → add trigger. Opening the composer focuses the natural-language input; the Project selector is immediately before it and reachable with Shift-Tab.
- Enter opens the focused Todo/title; Space activates only the focused checkbox/button.
- `⌘N` opens the composer and focuses its input, `⌘,` opens Settings, `⌘⇧A` selects All. Do not override system text-editing shortcuts.
- Every icon-only control has a tooltip and accessible label. The project mark exposes the full Project name only.
- Hover is never the only route. Dense pointer targets remain keyboard reachable; important actions also exist in detail/menus.
- Text contrast targets 4.5:1. Status includes checkbox/ellipsis/text semantics. Errors use icon plus text.
- Respect reduced motion, Reduce Transparency, Increase Contrast, and text scaling.

## Motion and pet behavior

| Trigger | Pet/panel response | Reduced motion |
|---|---|---|
| Quiet idle | Stand, briefly close eyes, then hold | Static open-eye pose |
| New background Todo change/proposal | Gleeful short-arm circle with a subtle forward/back head bob, then hold; change bubble rises above list | Static first arm-circle pose and bubble |
| Visible in-progress Todo | `A-B-A-C-A` yellow-suit body-sway dance, then a long hold | Static dance-ready pose |
| Pet-only/service unavailable | Lie down, inhale once, then hold | Static resting pose |
| User completes Todo | Checkbox fills; brief inline confirmation | Instant checked state |
| Todo enters/stays in progress | Three dots rise and settle once per quiet cycle | Static `…` |
| Open/close/detail | 180/120ms fade and small move from tail anchor | Instant crossfade |
| Next queued change | Current bubble fades; next replaces it without moving list | Instant replace |
| Step/Note update | Detail updates quietly | Same |

Pet motion must express its current presentation state. Resolve the pose in strict order: a closed Todo bubble uses `resting`; otherwise any visible unacknowledged change/proposal uses `noticed` and the arm circle; otherwise a visible in-progress Todo uses `working` and the dance; otherwise use `idle`. Idle and resting use a six-second rhythm: 700ms of alternate-frame action followed by 4.85 seconds on the primary frame. Noticed uses three source images in the five-stage `1-2-3-2-1` order with 320ms between every adjacent frame, including the final frame-1-to-next-loop frame-2 boundary. It repeats the resulting 1.28-second loop four times, then rests on frame 1 for four seconds while an alert remains visible. The very short arms stay close to and overlap in front of the torso, while the head subtly moves forward on frames 1/3 and back on frame 2. Working keeps its three source images in the five-stage `A-B-A-C-A` order at 160ms between every adjacent frame and loop boundary: 0.64 seconds per loop, four repetitions, then four seconds resting on A while the Todo remains in progress. B and C keep the face and ears upright, point with the same left hand, and reverse only the lower-body sway. Both action poses remain round, minimally articulated, empty-headed, and cheerfully excited rather than fierce or heroic. One preloaded image source swaps at a time with no opacity crossfade or stacked frame, eliminating ghost silhouettes. No unrelated constant bounce, confetti, punishment, or sad state. All pet and dot animation stops under Reduce Motion.

## Review checklist

The prototype must demonstrate:

- one dense Todo bubble, Todo detail, Settings/permissions, empty, and offline states;
- a separate one-at-a-time change/proposal bubble above the Todo bubble;
- open/in-progress/done controls and independent Steps;
- All/Personal/Project context using accessible one-character marks plus stable project colors;
- light/dark material approximations and reduced transparency/motion considerations;
- a play start action, sequenced in-progress dots with a reduced-motion fallback, and the full Project name above the detail title;
- no expanded list, Changes tab, fourth Todo status, or live agent indicator.

Owner approval was recorded on 2026-09-28 and Todo 2 is done. Use this document as the behavioral input to the runtime/framework spike and production UI. The prototype is not implementation evidence for the V1 acceptance matrix.
