# Phase 0: integration engine + orchestration skill

> Status: **Superseded** on 2026-09-04. Current scope: [TodoCrew V1](../../vertical-slice-1.md).
> Historical context only. The old two-worker integration run is no longer the next product milestone.
> Original snapshot: Git tag `omija-phase0` (commit `974ca87`).
> Last updated: 2026-08-24
> 상위 문서: [Architecture overview](architecture-overview.md)

## 1. 이 문서가 상위 문서에서 바꾸는 것

Architecture overview 는 "핵심 개념이나 책임 경계를 바꿀 때는 변경 이유를 함께 기록한다"고 정했다. 이 슬라이스는 책임 경계를 하나 바꾼다.

**바뀐 것**: Run, Task, Lane, Session, Attempt, Gate 의 실행과 상태 관리를 Omija 가 직접 구현하지 않는다. Phase 0 에서는 Orca 가 소유한다.

**이유**: `orca --help` 를 실측한 결과, Architecture overview 6절 도메인 모델의 대부분이 이미 Orca 에 있다.

| Omija 개념 | Orca 명령 |
|---|---|
| `Lane` | `worktree create` / `list` / `rm` |
| `Run` | `orchestration run-create` / `run-show` |
| `Task` | `orchestration task-create` / `task-list` / `task-update` |
| `Attempt` | `orchestration dispatch` |
| `Session` | `orchestration worker-start` / `worker-read` / `worker-stop` / `worker-release` |
| 승인 gate | `orchestration gate-create` / `gate-resolve` |
| 질문과 escalation | `orchestration send` / `ask` / `reply` / `inbox` |

Orca 에 **없는 것**은 Architecture overview 13절 전체다. staging ref, 통합 preview, 순서 rebase, `--ff-only` apply, `write_scope` 위반 검사.

그러니까 Omija 의 신규 가치는 **integration engine 하나**다. 나머지를 지금 만드는 것은 Orca 를 다시 만드는 일이다.

이 결정은 Phase 4 (`runtime-native`) 에서 되돌린다. 그때 Orca 없이 도는 제품이 필요해지고, 그 시점에는 이 슬라이스를 굴려본 경험이 상태 머신의 실제 요구사항을 알려준다.

## 2. 두 조각

| 조각 | 담당 | 형태 | 이유 |
|---|---|---|---|
| 오케스트레이션 | 일을 몇 갈래로 쪼갤지, 누구에게 줄지, orca 명령을 어떤 순서로 엮을지 | Claude Code skill (`SKILL.md`) | 판단이 필요하고 설계가 아직 안 굳었다. TypeScript 로 얼리면 매번 코드를 고쳐야 한다. |
| git 조작 | staging, preview, rebase, apply, scope 검사 | 실행 파일 (`omija` 명령) | 판단이 없고 틀리면 되돌리기 어렵다. 산문으로 쓴 지시는 모델이 건너뛸 수 있다. |

경계 기준은 하나다. **판단이 필요하면 스킬, 틀리면 위험하면 명령.**

`git rebase` 와 `--ff-only` 를 프롬프트에 맡기지 않는다. 반대로 "이 작업을 두 갈래로 쪼갤까 셋으로 쪼갤까"를 TypeScript 에 넣지 않는다.

## 3. 완료 조건

실제 저장소에서 진짜 Claude 와 Codex 로 다음이 돈다.

1. 스킬이 목표를 받아 독립 task 두 개로 쪼갠다
2. `orca worktree create` 로 Lane 두 개를 같은 base 에서 만든다
3. `orca orchestration dispatch` 로 Claude 와 Codex 에 각각 지시서를 보낸다
4. 두 worker 가 끝나면 스킬이 `omija scope-check` 와 verify 명령을 돌린다
5. `omija stage` 로 각 결과를 staging ref 에 복사한다
6. `omija preview` 가 폐기용 branch 에서 실제 rebase 를 수행하고 예상 graph 를 출력한다
7. 사용자가 승인하면 `omija apply` 가 base 를 `--ff-only` 로 전진시킨다

가짜 에이전트는 쓰지 않는다. 처음부터 진짜 worker 로 돈다.

## 4. 상태 저장

**SQLite 를 쓰지 않는다.** 이 슬라이스의 상태는 전부 git ref 다.

```text
refs/omija/base/<run-id>                고정된 base SHA
refs/omija/staging/<run-id>/<task-id>   task branch head 복사본
refs/omija/integration/<run-id>         통합 후보
refs/omija/archive/<run-id>/<task-id>   apply 이후 보관
refs/omija/lane/<run-id>/<task-id>      task 계약 (agent, write scope, verify)
```

base SHA 는 git object 다. 이걸 DB 에 복사해 두면 두 곳이 어긋날 수 있다. ref 로 두면 Architecture overview 8절의 "Git 이 commit 과 ref 의 source of truth" 가 자동으로 지켜진다.

Run 과 Task 의 **진행 상태**는 Orca 가 이미 들고 있다. 두 벌로 만들지 않는다.

`lane` ref 는 그 예외가 아니라 다른 물건이다. 여기 담는 것은 Omija 가 스스로 정한 task
계약(9절의 id, objective, agent, write scope, verify)이고, Orca 가 아는 것은 그 계약을
받은 worker 가 지금 도는지 물어보는지다. 계약은 Omija 가 쓴 것이니 Omija 쪽에 남는 게
맞고, liveness 는 여전히 Orca 만 안다.

**이 ref 를 파는 이유**: Run view (Architecture overview 7.1절)가 lane 그래프를 그리려면
어느 lane 이 무슨 task 이고 누가 도는지를 알아야 한다. 그걸 runtime 에 물어보면 Omija
코드가 Orca 를 알게 되고, 이 슬라이스가 2절에서 정한 "Orca 의존은 SKILL.md 산문 한 곳에
가둔다"가 깨진다. agent 이름 하나 때문에 그 경계를 넘지 않는다. dispatch 할 때 스킬이 한 번
쓰고, `omija status` 는 ref 만 읽는다.

이벤트 저장소와 projection 은 Phase 4 에서 Orca 를 벗어날 때 만든다.

## 5. CLI 계약

명령 다섯 개. 전부 `--repo` 를 받고 기본값은 현재 디렉터리다.

### 5.1 `omija preflight`

```text
omija preflight --base <ref> --run <run-id>
```

- base ref 를 SHA 로 해석한다
- working tree 가 dirty 면 파일 목록을 출력하고 exit 1
- `refs/omija/base/<run-id>` 에 SHA 를 기록한다
- stdout 으로 `{ "baseSha": "..." }` 출력

이미 그 run 의 base ref 가 있고 SHA 가 다르면 거부한다. base 는 Run 안에서 한 번만 정한다.

### 5.2 `omija stage`

```text
omija stage --run <run-id> --task <task-id> --branch <branch>
```

- `refs/omija/staging/<run-id>/<task-id>` 를 branch head 로 쓴다
- **원본 branch 는 읽기만 한다**

### 5.3 `omija scope-check`

```text
omija scope-check --run <run-id> --branch <branch> --allow <glob> [--allow <glob> ...]
```

- `refs/omija/base/<run-id>`..branch 의 변경 파일을 구한다
- glob 밖의 파일이 있으면 목록을 출력하고 exit 1
- 변경이 하나도 없어도 exit 1 (worker 가 아무것도 안 한 경우)

### 5.4 `omija preview`

```text
omija preview --run <run-id> --order <task-id,task-id,...>
```

- `refs/omija/integration/<run-id>` 가 있으면 지우고 base 에서 새로 만든다 (idempotent)
- order 순서대로 각 staging ref 를 integration head 위에 rebase 한다
- 성공하면 결과 graph 를 출력한다
- 충돌하면 어느 task 의 어느 파일인지 출력하고 exit 2. **자동 해결하지 않는다.**
- 실제 task branch 는 rewrite 하지 않는다

### 5.5 `omija apply`

```text
omija apply --run <run-id> [--base <ref>]
```

- base ref 가 `refs/omija/base/<run-id>` 와 같은 SHA 인지 확인한다. 다르면 exit 1 과 함께 preview 재생성을 요구한다
- `git merge --ff-only refs/omija/integration/<run-id>`
- 성공하면 staging ref 를 archive 로 옮기고 integration branch 를 지운다

### 5.6 출력 규약

모든 명령은 사람이 읽는 텍스트를 stderr 로, 기계가 읽는 JSON 을 stdout 으로 낸다. 스킬은 stdout 만 파싱한다.

exit code: `0` 성공, `1` 사용자가 고쳐야 함, `2` 충돌, `3` 내부 오류.

## 6. 안전장치

| 불변식 | 강제 지점 |
|---|---|
| base 가 dirty 면 시작하지 않는다 | `preflight` |
| Run 안에서 base SHA 는 한 번만 정한다 | `preflight` 가 기존 ref 와 대조 |
| worker 는 `write_scope` 밖을 못 건드린다 | `scope-check` |
| task branch 는 preview 때문에 rewrite 되지 않는다 | `stage` 가 복사만 함 |
| apply 직전 base 가 움직였으면 거부한다 | `apply` 가 ref 재확인 |
| 최종 반영은 fast-forward 만 | `git merge --ff-only` |
| destructive git 앞에 대상 ref 를 출력한다 | 공통 실행 래퍼 |

사용자의 dirty 상태를 자동 stash 하거나 버리지 않는다. 충돌을 자동 해결하지 않는다.

## 7. 저장소 구조

```text
omija/
├── src/
│   ├── cli.ts          parseArgs, 명령 분기, exit code
│   ├── git.ts          git 실행 래퍼 (destructive 명령 로깅 포함)
│   ├── refs.ts         ref 이름 규칙과 읽기/쓰기
│   └── commands/
│       ├── preflight.ts
│       ├── stage.ts
│       ├── scope-check.ts
│       ├── preview.ts
│       └── apply.ts
├── skill/
│   └── SKILL.md        오케스트레이션 스킬
├── test/
│   ├── fixture.ts      임시 저장소 생성
│   └── *.test.ts
└── docs/
```

pnpm workspace 와 패키지 분할은 아직 하지 않는다. 소비자가 하나뿐이다. Phase 4 에서 daemon 이 생길 때 나눈다.

## 8. 기술 선택

Node 24 표준 라이브러리를 기본으로 한다.

| 필요 | 선택 | 비고 |
|---|---|---|
| 타입 | TypeScript | Node 24 가 `.ts` 를 그대로 실행한다. 빌드 단계 없음 |
| 타입 검사 | `tsc --noEmit` | 실행용 컴파일은 안 한다 |
| 인자 파싱 | `node:util` 의 `parseArgs` | commander 안 쓴다 |
| 테스트 | `node:test` | vitest 안 쓴다 |
| git 실행 | `node:child_process` 의 `execFileSync` | 셸을 거치지 않는다 |
| glob 매칭 | `node:path` 의 `matchesGlob` | minimatch 안 쓴다 |

**런타임 의존성 0개.** YAML 파서도 필요 없다. plan 을 파일로 받지 않고 스킬이 명령 인자로 넘긴다.

## 9. 스킬 흐름

`skill/SKILL.md` 가 정의하는 순서다. 스킬은 판단하고, 위험한 조작은 명령에 넘긴다.

```text
1. 목표를 독립 task 로 쪼갠다
   기준: write_scope 가 겹치는가. 겹치면 하나로 묶는다.
2. task 별로 agent 를 고른다 (Architecture overview 12절 표를 초기값으로)
3. omija preflight  → baseSha 고정
4. task 마다:
     orca worktree create
     orca orchestration task-create
     orca orchestration dispatch   (지시서에 write_scope 와 verify 명령 포함)
5. orca orchestration worker-read 로 완료를 기다린다
6. task 마다:
     omija scope-check   → 위반이면 repair 지시
     verify 명령 실행    → 실패면 repair 지시
     omija stage
7. omija preview --order ...
   충돌이면 해당 task 에 conflict 해결 지시를 보내고 6번으로
8. 사용자에게 graph 를 보여주고 승인을 받는다
9. omija apply
10. orca worktree rm, orca orchestration worker-release
```

worker 지시서에 넣을 것: 목표, `write_scope`, verify 명령, base SHA, "rebase / merge / push 하지 마라", 완료 보고 형식.

## 10. 테스트

`node:test` 를 쓴다. 임시 저장소 fixture 를 만들어 실제 git 명령을 돌린다.

- `preflight` 가 dirty working tree 를 거부하는가
- `preflight` 를 두 번 부르고 base 가 다르면 거부하는가
- `stage` 이후 원본 branch 의 SHA 가 그대로인가
- `preview` 가 순서대로 rebase 해서 선형 history 를 만드는가
- `preview` 를 두 번 불러도 같은 결과인가
- 충돌하는 두 branch 를 preview 하면 task id 와 파일 목록이 나오는가
- `scope-check` 가 glob 밖 파일을 잡는가
- `scope-check` 가 변경 없음을 실패로 잡는가
- base 가 움직인 뒤 `apply` 가 거부하는가
- `apply` 성공 후 staging ref 가 archive 로 옮겨졌는가

스킬은 자동 테스트하지 않는다. 실제 작업으로 굴려서 검증한다.

## 11. 구현 순서

1. `git.ts` 와 `refs.ts`, 테스트 fixture
2. `preflight`, `stage` 와 각 테스트
3. `scope-check` 와 테스트
4. `preview` 와 테스트 (여기가 가장 오래 걸린다)
5. `apply` 와 테스트
6. `cli.ts` 조립
7. `SKILL.md`
8. 실제 저장소에서 task 두 개로 한 번 굴린다

## 12. 이 슬라이스가 하지 않는 것

- Task 사이 의존성과 스케줄링
- SQLite, 이벤트 저장소, projection
- daemon 과 동시 실행
- Orca 없이 도는 native runtime
- 교차 review 와 repair cycle 자동화
- 예산, 모델, effort 라우팅
- 충돌 자동 해결
- pnpm workspace 분할
- Desktop

## 13. 다음 단계에서 검증할 가정

이 슬라이스를 실제 작업에 몇 번 굴린 뒤 확인한다.

- Orca 의 orchestration 상태만으로 충분한가, 아니면 Omija 쪽 기록이 실제로 아쉬운가
- `write_scope` 겹침 금지가 실제 작업에서 너무 빡빡한가
- 오케스트레이션의 어느 부분이 매번 똑같이 반복되는가. 반복되는 것만 코드로 내린다
- preview 충돌이 얼마나 자주 나는가. 잦으면 task 분해 기준이 틀린 것이다

틀린 가정이 나오면 Architecture overview 에 변경 이유와 함께 기록한다.
