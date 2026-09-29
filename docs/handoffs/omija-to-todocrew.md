# Cofoco V1 — 이어받는 세션을 위한 현재 맥락

Updated: 2026-09-29

제품명은 **Cofoco**, 앱 패키지/현재 Swift CLI 이름은 `cofoco`로 계획한다. 기존 root package는 보존된 Git 엔진 작업공간으로 유지한다. Omija ADE/Git GUI 개발은 보류했고, 사용자와 기존 Claude Code/Codex CLI가 함께 관리하는 로컬 Todo companion으로 전환했다.

- 기본 UI: 데스크톱 펫 위 말풍선. 첫 V1은 macOS 로컬 단일 사용자 기준이다.
- Personal + 평면 Project, All은 집계 view. 프로젝트는 폴더 0..N개와 연결하며 디렉토리가 ID는 아니다.
- 굵은 독립 결과는 Todo, 내부 이정표는 1단계 Step, 링크/맥락은 Note다. Step 체크는 부모 완료와 독립이다.
- 상태는 open/in_progress/done 세 가지. 체크박스 + 이름, hover/focus의 재생 버튼으로 시작, 진행 중 … 표시. 에이전트 상태/needs-you는 없다.
- 사용자가 혼합형 권한을 선택했다. agent 생성·시작·Step 관리는 자동, 기존 Todo 제목/목표·완료·삭제·이동·재열기 등은 앱에서 확인한다.
- 사용자 명시 상태는 최신 revision을 읽어도 자동 반전할 수 없다. proposal은 승인 전 현재 Todo를 변경하지 않는다.
- UI/CLI/MCP는 하나의 서비스/SQLite 변경 경로를 쓴다. Todo/자식 공유 revision, 변경 이력, idempotency, soft delete/복원이 필요하다.
- 전역 MCP credential을 쓰는 세션들은 같은 권한을 공유한다. cwd는 분류 정보이며 권한 경계가 아니다. Personal 접근은 별도 opt-in이다.
- Todo 변경/새 제안은 피드백, Step/Note 변경은 상세/이력만 갱신한다. OS 알림은 기본 off다.

읽기 순서: [제품 계약](../product-spec.md) → [아키텍처](../architecture.md) → [Todo/Step 백로그와 인수 기준](../vertical-slice-1.md). [ADR 0002](../decisions/0002-todocrew-v1.md)에 V1 행동 계약, [ADR 0003](../decisions/0003-product-name-cofoco.md)에 현재 제품명이 있다.

UI는 2026-09-28 사용자가 최종 승인했다. [ADR 0004](../decisions/0004-macos-runtime.md)에서 SwiftUI/AppKit + 앱이 실행하는 Swift 서비스 + 시스템 SQLite3를 선택했다. `experiments/macos-runtime/`의 격리된 실험은 최적화 `.app` 빌드, 로컬 서명, SQLite 트랜잭션/백업, 단일 서비스, 창/도우미 시작·종료를 검증했다. 코디네이터가 최종 번들 검증을 재실행했고 입력 포커스, 한글 붙여넣기, 숨김/복원을 직접 조작해 확인했다.

Swift Todo/Step/Project 코어와 초기 로컬 서비스·CLI·MCP 어댑터가 생겼다. 격리된 Claude Code 실제 세션에서 Personal Todo 생성·조회·시작·재조회를 검증했고 CLI에서도 저장 상태를 확인했다([증거와 한계](../local-integration.md)). 서비스 반복 연결 회귀 테스트도 통과했다. 다만 provider 설정 설치는 수동, Codex CLI와 펫 앱은 아직 없으며 서비스도 앱이 자동 관리하지 않는다. 다음은 두 번째 provider 연동, 설정 설치/제거, 네이티브 펫 UI와 두 provider 도그푸딩이다. 실험의 원시 HTTP 파서·fixture schema·UI 스레드 종료 대기를 제품에 가져가지 않는다. macOS 14는 빌드 하한일 뿐 실제 검증은 macOS 26.5.2 arm64 환경에서 했다. 물리적 다중 디스플레이·전체 접근성·크래시 복구·공개 배포는 후속 검증이다. 구현 전 사용자 작업 지시와 현재 git status를 확인한다.

원본은 `974ca87` / `omija-phase0`로 보존했다. Git 엔진은 `packages/git-engine/`에 보존하며 소스/테스트/refs/CLI 계약을 바꾸지 않는다. `docs/archive/omija-ade/`의 로드맵과 orchestration-skill.md는 역사적 자료다. 기존 26개 테스트는 Cofoco 완료 증거가 아니다.

현재 checkout 경로는 `/Users/seungboshim/Projects/fromshim/omija`다. saved project, 다른 세션, 외부 CLI/스킬 설치는 자동 개명하지 않는다. 이 파일은 전달용 문서이며 외부 세션에 실제 전송했다는 의미가 아니다.
