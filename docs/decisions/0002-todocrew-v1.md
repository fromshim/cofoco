# ADR 0002 — TodoCrew V1 계약 확정

Status: **Accepted for V1 planning; implementation pending**
Date: 2026-09-07
Supersedes: [ADR 0001](0001-pivot-omija-to-agentodo.md)의 현재 제품명 및 이후 변경된 제품 동작

## 근거와 결정 순서

사용자는 TodoCrew를 선택하고 최신 대화의 결정을 우선해 V1 계약/문서를 확정하도록 요청했다. 최신 명시 결정, 이전에 수용한 방향, 기존 문서 순으로 대조했다. 미결정 세부사항은 아래 설계 기본값으로 기록한다. 프레임워크 검증은 구현 전 별도 작업이다.

## 충돌·미결정 사항 대조

| 주제 | 기존 문서/미결정 사항 | V1 결정 | 근거 |
|---|---|---|---|
| 제품명 | AgenTODO / agentodo | TodoCrew / todocrew | 최신 명시 선택 |
| Todo 상태 | open/in_progress/blocked/done/dismissed | open/in_progress/done만 유지 | 최신 명시 결정 |
| 행 UI | 추상적인 status/source 표시 | 체크박스 + 이름, hover/focus의 >, 진행 중 … | 최신 명시 결정 |
| 에이전트 상태 | SessionObservation, attention metadata | 제거; 출처/선택적 대화 참조만 이력에 보존 | 에이전트 상태 표시 제외 결정 |
| 작업 단위 | 굵은 Todo만 정의, Step 없음 | 독립적으로 기억할 결과는 Todo, 내부 이정표는 1단계 Step | 실제 사례 및 Step 수용 |
| Step 완료 | 미정 | Todo 완료와 독립; 미완료 Step을 둔 완료도 허용 | 설계 기본값: 실제 결과와 체크리스트 구분 |
| 개인/프로젝트 | 등록 폴더 중심 | Personal + 평면 논리 Project, 폴더 0..N 연결; All은 view | 개인 작업을 AI가 수행하는 사례 해결 |
| Git worktree | 자동 common-dir 탐지 필수 | 명시 폴더 별칭으로 지원, 자동 탐지는 보류 | V1 범위 축소를 위한 설계 기본값 |
| AI 변경 확인 | 보호 규칙만 있고 구체 UX 없음 | 생성·시작·Step 자동, 중요한 기존 Todo 변경은 제안/앱 확인 | 이 세션에서 사용자가 혼합형 선택 |
| 사용자 상태 보호 | 오래된 revision만 막음 | 사용자 명시 상태는 최신 revision을 읽어도 자동 반전 불가 | 사용자 제어권을 보존하는 설계 기본값 |
| Notes | Todo text field | 출처 있는 메모 항목; 타 작성자/사용자 수정본 교체는 확인 | 공유 컨텍스트 충돌을 줄이는 기본값 |
| 삭제 | dismissed와 hard-delete 금지 | 별도 soft delete + Trash/복원; 영구 삭제 보류 | 3상태 유지 및 삭제 요구 수용 |
| 후속 지원 공고 | AI가 원문 변경/완료하고 Todo 분할할지 미정 | 의미를 먼저 명확히 하고, 후보는 Note; 실제 약속만 Todo. 기존 목표 변경/완료와 연관 생성은 묶어 확인 | 취업 사례에 혼합형 정책 적용 |
| 알림 | 변경마다 알림, attention 중심 | Todo 변경/새 제안은 피드백; Step/Note는 상세·이력만, OS는 기본 off | 저부담 주의 환기를 위한 기본값 |
| 순서 | compact relevance 불명확 | scope별 안정적인 수동 순서, 추가/재열기는 끝에, 자동 재정렬 없음 | 주의/포인터 안정성을 위한 기본값 |
| 권한 | cwd 기반 격리로 읽힐 여지 | 동일 전역 credential의 모든 세션은 같은 grant 공유; Personal opt-in | 실제 보장 가능한 권한 경계 명시 |
| 초기 플랫폼 | 데스크톱 OS 미정 | 현재 사용자 환경인 macOS 단일 사용자 로컬 V1 | 초기 검증 대상 선택; 타 OS 출시는 별도 |
| CLI 범위 | 폭넓은 CRUD 명령 | add/list/show/status/open + integration/doctor | 펫 UI 우선, 중복 표면 축소 |

## 확정된 계약

- 사용자는 2026-09-07 검토에서 다음 네 항목을 명시적으로 확인했다: 기존 Todo 완료를 포함한 중요 변경의 승인, 사용자 지정 상태 보호, OS 알림 기본 비활성화, Git worktree/저장소 자동 연결 보류.
- [제품 명세](../product-spec.md)가 사용자 동작/범위의 기준이다.
- [아키텍처](../architecture.md)가 데이터 소유권, 제안/승인, revision, 이벤트, 권한과 도구 계약을 구체화한다.
- [백로그/인수 기준](../vertical-slice-1.md)은 실제 앱의 Todo → Step 형태로 개발 작업과 검증을 관리한다.
- 구현, UI 와이어프레임, 의존성 추가, MCP 설치는 이번 문서 확정에 포함하지 않는다.

## 남겨 둔 구현 검증

제품 동작에 관한 미결정 항목은 위 기본값으로 닫았다. 다음 작업에서 macOS UI 프레임워크, 서비스 시작/종료 및 IPC, SQLite 드라이버/마이그레이션, credential 저장, 설치/배포 방식을 작은 기술 검증으로 결정한다. exact JSON/SQL 스키마 및 실제 provider 설정은 해당 버전과 런타임에 맞춰 검증한다. 이 항목들은 새 기능이 구현됐다는 근거가 아니다.

## 이름과 역사 보존

현재 README, AGENTS, 패키지, 명세, handoff는 TodoCrew를 사용한다. ADR 0001과 이전 changelog에는 당시 AgenTODO 결정이라는 역사적 사실을 남기고 superseded를 명시한다. 아카이브의 현재 문서 안내문만 갱신한다.

omija-phase0 태그, 974ca87 원본, packages/git-engine 소스/테스트, refs/omija/* 및 기존 CLI 계약은 보존한다. 로컬 디렉토리와 saved project 이름은 변경하지 않는다. 이번 결정은 도메인 확보나 상표 등록 가능성 판정이 아니다.
