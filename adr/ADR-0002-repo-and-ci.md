# ADR-0002: 저장소, CI, 서식, 비밀값 검사

- 상태: Accepted
- 작성일 / 사람 승인일: 2026-10-28 / 2026-10-28
- 결정 책임자: 저장소 소유자
- 관련 Spec/R-ID: 헌법 I(CI·보호 규칙은 승인 항목), 헌법 비밀값 조항
- 사용한 외부 근거: GitHub 문서 "Troubleshooting required status checks", GitHub changelog 2025-08-07(arm64 러너), swift-format README, gitleaks-action README, GitHub secret scanning·push protection 문서

## 맥락

저장소는 공개이고(GitHub Free), 밤 무인 실행의 진짜 경계는 main 보호와 필수 검사다. 필수 검사 이름은 실제 job 이름과 같아야 하고, 건너뛸 수 있는 워크플로를 필수로 두면 병합이 막힌다. 로컬(Xcode 27.1)과 CI(Swift 6.3.3)의 `swift format` 버전이 다르다.

## 평가 기준

1. 무인 실행이 거짓 FAIL로 멈추지 않는가 2. 검사 결과가 로컬에서 재현되는가 3. 비용(공개 저장소 무료 범위) 4. 비밀값이 공개 브랜치에 올라가기 전에 막히는가

## 대안

| 대안 | 장점 | 단점·위험 | 근거·실험 |
|---|---|---|---|
| A. job 4개 필수, 경로 필터 없음, 서식은 경고만 | 거짓 FAIL 적음 | 서식 차이가 PR에 섞일 수 있음 | GitHub 문서: 건너뛴 필수 검사는 "Pending" 상태로 병합을 막는다 |
| B. A + 서식 lint 필수 | 서식 고정 | 버전 차이로 로컬에서 재현되지 않는 FAIL, 밤 실행 중단 위험 | swift-format README: 버전이 다르면 새 문법을 인식하지 못함 |
| C. 경로 필터로 job을 나눠 실행 | 빠름 | 필터로 건너뛴 필수 검사가 병합을 막음 | 같은 GitHub 문서 |

## Agent의 추천과 근거

A를 추천한다(추천안 토론: CI 구성 2:1, 서식 3:0, 비밀값 3:0).
- 워크플로 `ci.yml` 하나. 트리거 `pull_request`, `push: main`, `workflow_dispatch`. `permissions: contents: read`. 경로 필터 없음.
- 필수 검사(= job 이름):
  - `core-test`: `ubuntu-24.04-arm`, `container: swift:6.3.3-noble`, `apt-get install libsqlite3-dev`, `swift test`.
  - `tuning-test`: ubuntu, Python, `pytest`.
  - `app-build`: `macos-26`, Xcode 26.6, `brew install xcodegen`, `xcodegen --version`을 로그에 남김, `xcodegen generate`, `xcodebuild build CODE_SIGNING_ALLOWED=NO`.
  - `secrets-scan`: gitleaks-action v3, `fetch-depth: 0`.
- 서식: `.swift-format` 설정 파일을 커밋한다. `format-lint`는 별도 job, `continue-on-error: true`(필수 아님). SwiftLint는 쓰지 않는다(승인된 의존성 밖).
- 비밀값: GitHub 공개 저장소 secret scanning(자동)과 사용자 수준 push protection(기본 켜짐)을 유지한다. pre-commit 훅은 두지 않는다.
- 소수 의견(XcodeGen): 처음부터 버전 고정 릴리스 zip과 체크섬으로 받자는 의견이 있었다. brew 새 버전이 밤에 `app-build`를 깨면 그때 고정한다(로컬 brew 기준 2.46.0).

## 사람의 최종 결정과 실제 판단 이유

Agent 추천안 채택. 판단 이유: 사용자 위임(토론 채택안 "전부 승인", 2026-10-28)

## 포기하는 것·운영 영향

- 트레이드오프: 서식 차이가 PR에 섞일 수 있다. CI 비밀값 검사는 push 뒤에 돈다. GitHub가 모르는 키 형식은 공개 브랜치에 올라간 뒤 잡힌다(키는 Keychain에만 있어 저장소로 들어올 경로가 없다는 전제).
- 되돌리기: 쉬움(워크플로 수정, 단 필수 검사 변경은 승인 항목).

## 결정 검증

- 실행할 실험: main 보호 설정 뒤 필수 검사 이름을 다시 조회해 job 이름과 대조. 일부러 실패하는 테스트와 가짜 예시 키(`AKIAIOSFODNN7EXAMPLE`)로 초안 PR이 BLOCKED되는지, 어느 층이 막았는지 기록.
- 성공 판정: 실패 주입 시 병합 불가, 원복 시 PASS.
- 재검토 트리거: brew XcodeGen으로 `app-build`가 이유 없이 깨짐(고정 zip으로), Xcode 27.1과 6.3.3의 `swift format lint` 출력이 같다고 확인됨(`format-lint` 필수로 승격), macOS job 대기로 밤 PR이 아침까지 초록이 안 됨, gitleaks 오탐으로 밤 실행이 막힘(allowlist).
