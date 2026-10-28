# ADR-0001: 스택, 모듈 구조, 언어 모드

- 상태: Accepted
- 작성일 / 사람 승인일: 2026-10-28 / 2026-10-28
- 결정 책임자: 저장소 소유자
- 관련 Spec/R-ID: PRD 전체(FR-05 타이머, FR-16 설정, 7장 정책 1~5), 헌법 I·VIII
- 사용한 외부 근거: GRDB README(리눅스 지원 문구), GitHub changelog 2025-08-07(arm64 러너)

## 맥락

목하는 macOS 메뉴 막대 앱이다. 핵심 규칙(점수, 스케줄러, quantum 타이머, 체크포인트, 긴급 끼워넣기)은 밤 무인 실행과 리눅스 CI에서 화면 없이 검증되어야 한다. 실제 decision API는 테스트·검증·무인 실행에서 부르지 않는다(헌법 VIII). 승인된 외부 의존성은 DynamicNotchKit(SPM), GRDB, XcodeGen 셋뿐이다. (정정: DynamicNotchKit은 ADR-0008로 제외)

## 평가 기준

1. 리눅스 `swift test`로 규칙과 스키마를 검증할 수 있는가 2. 실제 API 호출을 구조로 막는가 3. 되돌리기 비용 4. 의존성을 늘리지 않는가

## 대안

| 대안 | 장점 | 단점·위험 | 근거·실험 |
|---|---|---|---|
| A. `MokaCore` 한 타깃에 순수 로직, GRDB·URLSession은 앱 타깃 | 단순 | 스키마 시험이 macOS 앱 빌드에서만 돈다 | — |
| B. `MokaCore` + `MokaStore`(GRDB) + `moka-sim`, URLSession 실제 전송만 앱 타깃 | 스키마까지 리눅스에서 시험, 테스트·`moka-sim`이 실제 공급자를 링크하지 않음 | 타깃 하나 더 | GRDB 7.11.1 + Swift Testing이 `swift:6.3.3-noble`(aarch64)에서 `swift test` PASS |
| C. B + `MokaNet`(URLSession) 타깃 | 네트워크 계층 분리 | 실제 호출은 시험하지 않으므로 얻는 검증이 없고 리눅스 FoundationNetworking 문제만 는다 | — |

## Agent의 추천과 근거

B를 추천한다(추천안 토론 3:0).
- Package 하나: `MokaCore`(의존성 없음: 점수, 스케줄러, 상태 전이, 체크포인트, 타이머 상태기계, 긴급 규칙, DecisionProvider 프로토콜, 요청 조립과 응답 해석, 가짜 공급자, 서킷브레이커, 금지 필드 검사), `MokaStore`(GRDB 마이그레이션과 저장소, `MokaCore`에 의존), `moka-sim`(실행 파일, 위 둘에만 의존).
- URLSession으로 실제 decision API를 부르는 공급자는 앱 타깃에만 둔다. 테스트 타깃과 `moka-sim`은 그것을 링크하지 않으므로 헌법 VIII을 빌드 구조가 지킨다.
- 앱 타깃(노치 UI, Keychain, GRDB 연결)은 얇게 둔다. 프로젝트 파일은 XcodeGen `project.yml`로 생성하고 `.pbxproj`는 커밋하지 않는다.
- `swift-tools-version: 6.0`. Package 타깃은 Swift 6 언어 모드(엄격한 동시성).
- 앱 타깃도 Swift 6 모드로 시작한다. DynamicNotchKit 등으로 동시성 오류가 나면 **첫 실패에서** 앱 타깃만 `SWIFT_VERSION: 5.0`으로 내리고 이 ADR에 적는다(같은 원인 2회 실패로 멈추는 일을 피한다). 나중에 6으로 올리는 diff는 크므로 처음부터 6으로 둔다. (정정: DynamicNotchKit은 ADR-0008로 제외)
- Xcode: CI는 `macos-26` 러너의 Xcode 26.6, 로컬은 Xcode 27.1. 리눅스 이미지는 `swift:6.3.3-noble`.

## 사람의 최종 결정과 실제 판단 이유

Agent 추천안 채택. 판단 이유: 사용자 위임(토론 채택안 "전부 승인", 2026-10-28)

## 포기하는 것·운영 영향

- 트레이드오프: 실제 네트워크 전송 코드는 자동 시험하지 않는다. 실제 호출 확인은 사람이 자기 키로 앱을 켜서 한다.
- 되돌리기: Package 안 파일 이동이라 쉽다. 언어 모드는 타깃마다 한 줄.

## 결정 검증

- 실행할 실험: 리눅스 CI(`ubuntu-24.04-arm`)에서 `MokaCore`·`MokaStore` 테스트 PASS. 테스트 타깃 의존성에 실제 공급자가 없는지 `Package.swift`로 확인.
- 성공 판정: 첫 CI 실행 PASS.
- 재검토 트리거: arm 러너에서 GRDB 빌드 실패(그때 `MokaStore` 테스트를 macOS job으로 옮김), 앱 타깃이 Swift 6 모드로 빌드되지 않음.
