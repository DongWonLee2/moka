# Implementation Plan: 노치와 타이머 (마일스톤 1)

**Branch**: `chore/spec-001-notch-timer` (구현은 Issue별 `feat/<issue>-<slug>`) | **Date**: 2026-10-28 | **Spec**: [spec.md](spec.md)

**Input**: `specs/001-notch-timer/spec.md`(R-001~R-015)

## Summary

노치(없으면 직접 만든 떠 있는 창)에 수동 입력한 할 일 하나와 사용자가 고른 시간의 타이머를 띄운다. 타이머·칩·설정 규칙·표시 위치 선택은 MokaCore 값 타입과 순수 함수로 두고 리눅스 `swift test`와 `moka-sim`으로 화면 없이 검증한다. 기본 작업 시간은 GRDB `settings` 테이블에 저장하며, 이 PR 묶음에서 첫 마이그레이션과 스키마 스냅샷이 시작된다. 화면은 HTML 시안을 사용자가 확정한 뒤 만들고, 그 전에 DynamicNotchKit spike로 미확인 동작 6가지를 확인한다. 결정 근거는 [research.md](research.md).

## Technical Context

**Language/Version**: Swift 6(언어 모드 6, ADR-0001). 앱 타깃은 Swift 6 첫 실패 시 5.0(ADR-0001 32행)

**Primary Dependencies**: GRDB 7.11.1(`MokaStore`, 기존), DynamicNotchKit 1.1.0 `revision: cd0b3e52d537db115ad3a9d89601f20e0bee8d27`(앱 타깃만, `project.yml`, 새로 연결 — 의존성 자체는 ADR-0001 승인)

**Storage**: SQLite `~/Library/Application Support/dev.dongwon.moka/moka.sqlite`(ADR-0004), `settings` 테이블 하나. 할 일·타이머는 메모리

**Testing**: Swift Testing(`MokaCoreTests`, `MokaStoreTests`, 리눅스 CI `core-test`), XCTest 스냅샷 번들 `MokaAppTests`(macOS 로컬, CI job 없음)

**Target Platform**: macOS 14+, `LSUIElement` 메뉴 막대 앱(ADR-0005). Package 타깃은 리눅스(`swift:6.3.3-noble`)에서도 빌드

**Project Type**: 데스크톱 앱 + Swift Package(라이브러리 2개 + CLI)

**Performance Goals**: 펼침·접힘 100ms(FR-06). 이번에는 사람 눈 확인(SC-004), 계기 측정은 버퍼 기간

**Constraints**: 실제 시간을 기다리는 시험 금지(헌법 II), `Date()`·`TimeZone.current`를 MokaCore에서 직접 읽지 않음(ADR-0003), 실제 앱 DB 경로를 테스트·`moka-sim` 기본값으로 두지 않음(ADR-0004·0006), 시간 끝 자동 펼침은 키보드 포커스를 가져가지 않음(R-009)

**Scale/Scope**: 사용자 1명, 할 일 동시 1개, 설정 키 1개, 화면 상태 6개

## Constitution Check

*GATE: Phase 0 전 확인, Phase 1 설계 뒤 다시 확인함.*

| 원칙 | 판정 | 근거 |
|---|---|---|
| I 승인 없는 계약 변경 금지 | 통과(승인 받음) | 첫 마이그레이션·스냅샷(D1), `moka-sim` v1(D2), DynamicNotchKit 연결(D3), 스냅샷 방법(D4)을 토론 → 사용자 "전부 승인"(2026-10-28). EGM 리뷰 뒤 계약 보강·ADR-0004 정정(새 ADR)·Package.swift 내부 의존 정리·포커스 규칙(SC-001)을 토론 → 사용자 승인(2026-10-28). 구현 PR마다 "사람이 볼 결정"에 다시 적는다 |
| II 테스트 먼저, 약화 금지 | 통과 | R-ID마다 Red 커밋 → Green 커밋. 시간 규칙은 주입한 `MokaClock`. 오류 주입은 quickstart 3 |
| III 네 가지로만 보고 | 통과 | quickstart 결과 표는 PASS/FAIL/SKIP/NOT_RUN. 스냅샷 생성 PASS는 화면 정합 증거가 아니라고 명시(R8) |
| IV 같은 실패 2회 중단 | 통과 | Swift 6 첫 실패에서 5.0으로 내림(두 번째 시도 없음). spike 상한 반나절 |
| V 작은 PR | 통과 | 아래 "작업 단위" 5개를 각각 PR로 |
| VI ID로 추적 | 통과 | 테스트 표시 이름 `FR-06 R-005: …`(ADR-0003), tasks·Issue·PR 표에 R-ID |
| VII 보호 장치 우회 금지 | 통과 | 해당 없음 |
| VIII 판단 모델은 판단만 | 통과 | 이번 범위에 판단 질의 없음. `moka-sim`은 네트워크·DB 인자 없음 |
| 보안·사용자 데이터 | 통과 | 시나리오·스냅샷은 가짜 할 일만, `.verify/` 커밋 안 함, 로그에 할 일 제목 없음(R7) |

설계 뒤 재확인: 위반 없음. Complexity Tracking 해당 없음.

## Project Structure

### Documentation (this feature)

```text
specs/001-notch-timer/
├── spec.md
├── plan.md               # 이 파일
├── research.md           # R1~R9 결정
├── data-model.md         # 상태기계, 칩, settings, 표시 위치, 화면 상태
├── quickstart.md         # 검증 절차 1~6
├── contracts/
│   └── moka-sim-v1.md    # 공개 계약
├── checklists/requirements.md
└── tasks.md              # 시안 v3.4 확정 뒤 작성
```

시안: `~/Dev/ai-platform/projects/moka/design/001-mockup.html`(저장소 밖, 로컬 전용).

### Source Code (repository root)

```text
Package.swift                         # 내부 의존만 정리: moka-sim→MokaStore 제거, MokaStoreTests에 MokaCore 명시(토론 Q5, 사용자 승인 2026-10-28)
Sources/MokaCore/
├── MokaClock.swift                   # 현재 시각 주입(앱만 씀)
├── NotchTimer.swift                  # 상태기계(empty(draft:)/running/expired), 전이 함수 apply, 남은 초 올림·자름, 불변식 검사
├── QuantumChip.swift                 # 프리셋, 직접 입력 검증, 남은 시간 표시 형식 M:SS, shouldStayExpanded
├── QuantumSettings.swift             # SettingsStore 프로토콜, 읽기 규칙(없거나 범위 밖이면 25)
├── Defaults.swift                    # 기본 분 25, 범위 1…180, 프리셋
├── DisplayTarget.swift               # 화면 목록 → .notch / .floating
└── Sim/                              # moka-sim v1 시나리오 타입·디코더·실행기·출력
Sources/MokaStore/
├── MokaDatabase.swift                # 기존 + 경로 주입 열기
├── Migrations.swift                  # MokaMigrations.migrator(DatabaseMigrator에 v1_settings 등록, 시험은 ADR-0007대로 리터럴과 migrator.migrations 비교)
└── GRDBSettingsStore.swift           # SettingsStore 구현
Sources/moka-sim/main.swift           # `run <file>` → 실행기 → stdout, 종료 코드
Tests/MokaCoreTests/                  # 타이머·칩·설정 규칙·표시 위치·Sim golden
Tests/MokaCoreTests/Fixtures/sim/     # 가짜 시나리오 + 기대 출력
Tests/MokaStoreTests/                 # 마이그레이션 이름, 스냅샷 비교, 경로 가드, 왕복
schema/moka-schema.sql                # 첫 스냅샷(settings)
App/Sources/
├── MokaApp.swift                     # 메뉴 막대(설정…, 종료), AppState 생성
├── AppState.swift                    # @Observable @MainActor
├── Notch/NotchHost.swift             # DynamicNotchKit을 import하는 유일한 파일
├── Notch/FloatingHost.swift          # 직접 만든 .nonactivatingPanel 떠 있는 창
├── Notch/ScreenWatcher.swift         # NSScreen → DisplayTarget 입력, 화면 변경 알림
├── Views/                            # 접힘·펼침·칩·시간 끝 SwiftUI 뷰(스냅샷 대상)
└── Settings/SettingsView.swift
App/Tests/MokaAppTests/               # 스냅샷 도우미 + 상태별 PNG(XCTest, TEST_HOST 없음)
project.yml                           # DynamicNotchKit 패키지, MokaStore 의존, MokaAppTests 타깃
```

**Structure Decision**: ADR-0001 구조(루트 `Package.swift`, MokaCore·MokaStore·moka-sim, 얇은 `App/`)를 그대로 쓴다. 설계서 §1의 `Packages/` 3개 패키지 레이아웃과 `Moka/` 앱 폴더는 ADR-0001과 어긋나며 ADR을 따른다([승인 P] Q1).

## 작업 단위 (tasks.md의 뼈대, Issue 후보)

| # | 단위 | R-ID | 시안 확정 필요 | 무인 가능 |
|---|---|---|---|---|
| 1 | MokaCore 타이머 상태기계·칩·설정 규칙·표시 위치 + `moka-sim` v1 + golden | R-003·004·005·007·008·010·011(선택 함수)·013·015 | 아니오 | 예 |
| 2 | MokaStore 첫 마이그레이션 `v1_settings`·스냅샷·경로 가드·`GRDBSettingsStore` | R-012 | 아니오 | 예(리눅스·macOS 스냅샷 텍스트 비교 포함) |
| 3 | DynamicNotchKit spike(버리는 브랜치) + 스냅샷 도우미 첫 시험 | — (R-002·009·011 위험 확인) | 아니오 | 아니오(사람 눈·손) |
| 4 | 앱: AppState, NotchHost, 접힘·펼침·입력·칩·시간 끝 뷰, 메뉴 막대, 설정 화면 | R-001·002·006·007·008·009·012(화면) | 예 | 화면 확인은 사람 |
| 5 | 앱: 떠 있는 창·화면 변경, 스냅샷 번들, 스냅샷 방법 ADR | R-011, D4 | 예 | 화면 확인은 사람 |

1·2는 서로 파일이 겹치지 않아 병렬로 갈 수 있다. 단, 단위 2의 `GRDBSettingsStore`는 단위 1의 `SettingsStore` 프로토콜(T007)에 기대므로 T007 PR을 먼저 병합한다. `Package.swift` 정리는 spec PR에 들어 있다. 4·5는 3의 PASS와 시안 확정 뒤에 시작한다.

## 설계서 대조

| 설계서 | 이 plan | 처리 |
|---|---|---|
| §1 MokaApp의 AppCoordinator | `AppState` 하나 | 이번 범위에 둘로 나눌 일이 없음(R6) |
| §1 `Packages/`·MokaDecision, `Moka/` 폴더, `Moka.xcodeproj` | ADR-0001 구조 | ADR이 이김([승인 P] Q1) |
| §1 Clock 프로토콜 주입 | `MokaClock` | 같음(ADR-0003 이름) |
| §2 `settings.value` JSON 문자열 | TEXT, 키마다 형식(정수는 10진 문자열) | D1을 따름 |
| §2 DB 경로 `Application Support/Moka/`, WAL | `dev.dongwon.moka/`, 기본 저널 | ADR-0004, WAL은 spec 002 |
| 초안 ADR-0005 floating 그대로·hover 기본값 | 직접 만든 떠 있는 창, R-009 동작 | spec(사용자 결정)을 따름 |
| §4 시퀀스 1 quantum 만료 → 체크포인트 | 만료 → 자동 펼침(체크포인트 없음) | 체크포인트는 마일스톤 2(FR-07). 만료 화면 자리를 그때 이어 씀 |

## 다음 단계

1. HTML 시안 v3.4 확정(완료, 2026-10-28)
2. `/speckit-tasks`(완료, EGM 반영 뒤 42개)
3. EGM 금붕어 리뷰(완료, uninterrupted 5단계, `.audit/egm/consolidated_review_report.md`, 커밋 안 함). 승인 항목은 토론(`.audit/debate/20261028-1225-spec001-egm-approvals.md`) 뒤 사용자 승인, 나머지 🔴·🟡 지적은 이 문서들에 반영
4. Issue 큐(작업 단위 1·2를 먼저, 3은 사람 세션, 4·5는 spike 뒤)
