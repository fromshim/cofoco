# TodoCrew V1 — 이어받는 세션을 위한 현재 맥락

Updated: 2026-09-07

제품명은 **TodoCrew**, 패키지/향후 CLI는 `todocrew`다. Omija ADE/Git GUI 개발은 보류했고, 사용자와 기존 Claude Code/Codex CLI가 함께 관리하는 로컬 Todo companion으로 전환했다.

- 기본 UI: 데스크톱 펫 위 말풍선. 첫 V1은 macOS 로컬 단일 사용자 기준이다.
- Personal + 평면 Project, All은 집계 view. 프로젝트는 폴더 0..N개와 연결하며 디렉토리가 ID는 아니다.
- 굵은 독립 결과는 Todo, 내부 이정표는 1단계 Step, 링크/맥락은 Note다. Step 체크는 부모 완료와 독립이다.
- 상태는 open/in_progress/done 세 가지. 체크박스 + 이름, hover/focus의 >로 시작, 진행 중 … 표시. 에이전트 상태/needs-you는 없다.
- 사용자가 혼합형 권한을 선택했다. agent 생성·시작·Step 관리는 자동, 기존 Todo 제목/목표·완료·삭제·이동·재열기 등은 앱에서 확인한다.
- 사용자 명시 상태는 최신 revision을 읽어도 자동 반전할 수 없다. proposal은 승인 전 현재 Todo를 변경하지 않는다.
- UI/CLI/MCP는 하나의 서비스/SQLite 변경 경로를 쓴다. Todo/자식 공유 revision, 변경 이력, idempotency, soft delete/복원이 필요하다.
- 전역 MCP credential을 쓰는 세션들은 같은 권한을 공유한다. cwd는 분류 정보이며 권한 경계가 아니다. Personal 접근은 별도 opt-in이다.
- Todo 변경/새 제안은 피드백, Step/Note 변경은 상세/이력만 갱신한다. OS 알림은 기본 off다.

읽기 순서: [제품 계약](../product-spec.md) → [아키텍처](../architecture.md) → [Todo/Step 백로그와 인수 기준](../vertical-slice-1.md). [ADR 0002](../decisions/0002-todocrew-v1.md)에 기존 문서와 최신 결정의 충돌 및 설계 기본값이 있다.

V1 계약은 문서화됐지만 Todo core/SQLite/daemon/MCP/CLI/pet 구현은 아직 없다. 다음 작업은 UI 방향/와이어프레임이며 이후 runtime spike, core/MCP, pet, 실제 두 provider 도그푸딩 순서다. 구현 전 사용자 작업 지시와 현재 git status를 확인한다.

원본은 `974ca87` / `omija-phase0`로 보존했다. Git 엔진은 `packages/git-engine/`에 보존하며 소스/테스트/refs/CLI 계약을 바꾸지 않는다. `docs/archive/omija-ade/`의 로드맵과 orchestration-skill.md는 역사적 자료다. 기존 26개 테스트는 TodoCrew 완료 증거가 아니다.

현재 checkout 경로는 `/Users/seungboshim/Projects/fromshim/omija`다. saved project, 다른 세션, 외부 CLI/스킬 설치는 자동 개명하지 않는다. 이 파일은 전달용 문서이며 외부 세션에 실제 전송했다는 의미가 아니다.
