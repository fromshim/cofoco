# Cofoco V1 — 이어받는 세션을 위한 현재 맥락

Updated: 2026-10-01

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

Swift 코어·로컬 서비스·CLI·MCP와 `packages/cofoco-app/`의 네이티브 펫 앱이 연결됐다. 실제 Claude Code MCP 검증은 [기존 증거](../local-integration.md), 앱 목록/상세/승인/휴지통/설정/커스텀 펫과 재시작·helper 강제 종료 복구는 [Step 4 증거](../native-app.md)를 읽는다. 앱은 별도 SQLite 쓰기나 private pipe 대신 Keychain-authenticated owner HTTP와 2초 event polling을 쓴다([ADR 0005](../decisions/0005-desktop-owner-channel.md)). 기본 펫은 직접 그린 원본 코드 아트이고 우사기는 번들에 넣지 않는다. Provider 설정은 수동이며 Codex 연동·설정 설치/제거·두 provider 도그푸딩과 전체 접근성/기기 검증이 다음 작업이다. macOS 14는 빌드 하한일 뿐 실행 검증 주장으로 쓰지 않는다. 공개 배포 서명/공증도 남았다. 기존 실험 schema/원시 HTTP 파서/UI 스레드 종료 대기를 재사용하지 않는다. 작업 전 최신 사용자 지시와 git status를 확인한다.

원본은 `974ca87` / `omija-phase0`로 보존했다. Git 엔진은 `packages/git-engine/`에 보존하며 소스/테스트/refs/CLI 계약을 바꾸지 않는다. `docs/archive/omija-ade/`의 로드맵과 orchestration-skill.md는 역사적 자료다. 기존 26개 테스트는 Cofoco 완료 증거가 아니다.

현재 checkout 경로는 `/Users/seungboshim/Projects/fromshim/omija`다. saved project, 다른 세션, 외부 CLI/스킬 설치는 자동 개명하지 않는다. 이 파일은 전달용 문서이며 외부 세션에 실제 전송했다는 의미가 아니다.
