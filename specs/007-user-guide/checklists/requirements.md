# Specification Quality Checklist: 사용 안내 (도움말 탭과 온보딩 안내 장)

**Purpose**: plan으로 넘어가기 전에 명세가 완전하고 품질이 맞는지 확인한다
**Created**: 2026-11-12
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [ ] No [NEEDS CLARIFICATION] markers remain
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

- [NEEDS CLARIFICATION] 표시는 본문에 쓰지 않고 "확정할 것" Q1~Q12로 모았다. 추천 없이 선택지만 있고, debate로 추천을 정한 뒤 사람이 확인하면 이 항목을 채운다.
- 구현 내용 항목의 판정 근거: 인용 문구의 출처를 밝히려고 화면 파일 이름(`GateView`, `ReasonText` 등)과 기존 타입 이름(`OnboardingSteps`, `StepBar`, `JudgmentState`)을 적었다. 구현 방법(뷰 구성, 상수 꺼내는 방식)은 plan에 둔다. spec 004·006과 같은 기준이다.
- 금지 기호(em dash, 화살표)는 0건이다.
