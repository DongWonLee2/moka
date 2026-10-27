---
name: Task
about: 독립적으로 검증 가능한 작업 하나
title: ""
labels: []
---

## 목적
[이 작업의 독립된 결과 한 문장]

## 요구사항 / 결정
- Task-ID: T
- FR·정책 번호:
- Spec: [커밋 고정 링크]
- ADR:

## 포함/제외 범위
- 포함:
- 제외:

## 수용 기준
- [ ] [검증 가능한 동작]
- [ ] [오류/경계 시나리오]

## 선행 작업·의존성
- Blocked by:
- 계약(스키마·DecisionProvider·시나리오 형식):

## 실제 검증 방법
- 명령: `swift test`, `cd tuning && python3 -m pytest`
- 필수 게이트: CI `core-test`, `tuning-test`, `app-build`, `secrets-scan`

## 위험과 승인
- 사람 승인 필요:
