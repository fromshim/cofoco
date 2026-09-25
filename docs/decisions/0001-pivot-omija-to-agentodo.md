# ADR 0001 — Omija에서 AgenTODO로 제품 중심 전환

Status: **Historical; product name and V1 details superseded by [ADR 0002](0002-todocrew-v1.md)**
Date: 2026-09-04

이 문서는 당시 AgenTODO라는 작업명으로 결정한 이력을 보존한다. 현재 제품은 **Cofoco**이며 아래 상태/범위/후속 작업은 최신 계약으로 해석하지 않는다. 현재 기준은 [제품 명세](../product-spec.md), [ADR 0002](0002-todocrew-v1.md)의 V1 행동 계약, [ADR 0003](0003-product-name-cofoco.md)의 제품명이다.

## Context

Omija는 여러 코딩 에이전트와 Git worktree를 오케스트레이션하고 안전하게 통합하는 ADE를 지향했다. 실제 구현은 Git 통합 명령 다섯 개와 테스트, Orca를 호출하는 orchestration skill까지였다. 실 에이전트 두 개의 전체 실행과 Desktop은 아직 검증/구현하지 않았다.

사용자가 더 직접적으로 겪는 문제는 여러 프로젝트와 에이전트 세션을 병행하면서 할 일과 후속 작업을 잊는 것이다. 새 앱을 분리하거나 투두를 ADE의 부가기능으로 넣는 대신, 이를 제품 중심으로 전환하기로 했다.

## Decision

1. 제품명은 **AgenTODO**, 워드마크는 `agenTODO`, 패키지/향후 CLI는 `agentodo`로 한다.
2. 기본 화면은 **펫 위의 Todo 말풍선**이다. 최소 Desktop shell은 첫 vertical slice에 포함한다.
3. 개인/전역 할 일과 프로젝트/폴더별 할 일은 평면 scope로 관리한다. 전체는 집계 view다.
4. 사용자와 에이전트가 같은 durable Todo 목록을 관리하되, Todo와 실행 Task/Session을 분리한다.
5. 첫 slice는 local daemon + SQLite + shared API/CLI + MCP + 최소 펫 UI + 로컬 provider 연동이다.
6. Git GUI/ADE, agent launching, worktree orchestration, Git integration 기능은 보류한다.
7. 기존 Git 엔진은 재사용 후보로 보존하지만 첫 slice의 의존성이 아니다.

## Preservation and repository changes

- 변경 전 원본을 첫 커밋 `974ca87` (`chore: checkpoint original omija phase-0`)으로 보존했다.
- annotated tag `omija-phase0`를 그 원본에 고정했다. 태그는 이동하지 않는다.
- 기존 `src/`, `test/`를 내용 변경 없이 `packages/git-engine/{src,test}`로 이동했다.
- root package 이름/설명을 변경하고 test/typecheck 경로를 갱신했다.
- root의 `omija` bin 등록은 제거했다. 미구현 `agentodo` CLI를 기존 Git CLI로 가장하지 않는다.
- 기존 README/설계는 `docs/archive/omija-ade/`로 옮기고 superseded 표시를 붙였다.
- `skill/SKILL.md`는 아카이브의 `orchestration-skill.md`로 이동했다. 활성 skill이 아니며 파일에 남은 명령은 역사적 문맥이다.
- `refs/omija/*`, preview 경로, `OmijaError`, legacy CLI 표현은 의도적으로 보존한다. 외부 Git 저장소를 검색하거나 마이그레이션하지 않았다.
- 현재 작업 디렉토리 `/Users/seungboshim/Projects/fromshim/omija`는 세션의 경로 참조를 보존하기 위해 유지했다. saved-project 이름/경로와 별도 설치된 스킬·CLI는 자동 변경하지 않았다.
- Git remote는 설정되어 있지 않아 원격 저장소 개명이나 push를 수행하지 않았다.

## Current sources of truth

- [Product specification](../product-spec.md)
- [Architecture](../architecture.md)
- [Vertical slice 1 and active backlog](../vertical-slice-1.md)
- Root [AGENTS.md](../../AGENTS.md)

옛 ADE 문서는 과거 결정의 근거일 뿐 현재 요구사항이 아니다. Git 엔진을 명시적으로 다시 다룰 때만 참조한다.

## Consequences

사용자의 주의/기억 문제를 더 작은 제품 표면으로 검증할 수 있다. 기존 Git 구현과 회복 가능한 history는 잃지 않으며, 향후 실제 실행 기능이 필요해지면 별도 결정 후 편입한다.

새 Todo core/SQLite/daemon/MCP/CLI/pet UI는 아직 구현되지 않았다. “자동”은 연결된 agent의 명시적 보고와 reconciliation 지침을 뜻하며 모든 대화의 누락 없는 감시를 보장하지 않는다. Desktop toolkit, 초기 지원 OS, daemon 배포 방식은 runtime spike에서 결정한다.

## Verification and follow-up

원본 체크포인트와 이동 후 모두 Git 테스트 26개와 타입 검사를 통과했다. source/test 12개 파일이 태그의 원본과 byte-for-byte 동일한지 확인했다. 이것은 보존 검증이며 새 기능의 완료 증거가 아니다.

다음 구현은 [vertical slice 1](../vertical-slice-1.md)의 runtime spike와 Todo 계약부터 시작한다. 원격 저장소 생성/개명, 로컬 폴더 이동, 외부 세션에 메시지 전송은 이번 변경 범위에 포함하지 않는다.
