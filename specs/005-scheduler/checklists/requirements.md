# Specification Quality Checklist: 스케줄러 (마일스톤 4)

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-11-10
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- 1차 검토(2026-11-10): 확인 표시 3개가 남아 "No [NEEDS CLARIFICATION] markers remain"만 미통과였다. R-407(시간 끝에서 스케줄러가 하는 일), R-412(이월 대상), R-415("날짜 바꿀래요"의 뜻)다.
- 2차 검토(2026-11-13, 기준 `origin/main` `09ca515`): 세 질문의 답을 반영해 확인 표시가 0개다. R-407은 사람 결정(다수안), R-412는 토론 3:0 사용자 위임, R-415는 사람 결정(소수안 채택)이다.
- 3차 검토(2026-11-13, PR #169 리뷰 반영): 이월 대상에 진행 중 할 일, 로그 범위, 바꿀 기존 안내 글, "오늘 끝" 흐름, 이월 답 대기의 다른 길을 채웠다. R-422의 "오늘 끝" 화면 순서(선택지 A·B)는 화면 결정이라 [사람 결정 대기]로 남겼다. 요구 동작(두 줄, 상태, 계기)은 정해져 있어 시험할 수 있다.
- 4차 검토(2026-11-13, 남은 결정 넷 토론 반영): R-422 순서는 토론 3:0(사용자 위임)으로 정해 [사람 결정 대기] 표시를 지웠다. R-416 로그 범위(토론 2:1), 범위 나누기(토론 3:0), 워밍업 0.8(토론 3:0)을 반영했다. R-424~R-430, User Story 4~6, SC-407~SC-409는 Issue #171로 넘겼다.
- R-404(연속 상한)와 R-405(마무리 규칙)는 앱에 걸리는 경로가 없고 고르기 순수 함수 시험으로만 재현한다(R-407, SC-402). 요구 문장 자체는 시험할 수 있다.
- 참조 정리: spec 003·004·006·007, ADR-0010·0011·0012, 질문 파일 v3, #151(시간 끝 칩 처음 값 = 추가 시간), 온보딩 6단계(spec 007 R-711)에 맞췄다. R 번호는 R-4xx만 쓰고 다른 spec과 겹치지 않는다.
- 구현 용어 점검: 코드 이름은 저장 계약 이름(`carry_count`, `carry_today` 등), 기본값 파일(`Defaults.swift`), 앞 spec R-ID 참조에만 쓴다.
- 성공 기준의 "단위 시험", "스냅샷"은 확인 방법이고 기술 선택이 아니다(spec 003과 같은 서술).
- 범위: 나눈 뒤 남은 요구는 26개다(R-401~R-423에서 지운 R-418을 빼고 R-431~R-434를 더함).
- 승인 항목: 스키마(`carry_count`, `due_decision`), 선택 규칙 이름 목록(R-411, 셋), 행동 로그 사용자 행동 값, 시뮬레이터 입력 형식과 출력, 설정 키, `Defaults.swift` 새 값.
