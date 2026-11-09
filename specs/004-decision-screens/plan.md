# Implementation Plan: 판단 결과 화면 연결 (마일스톤 3 나머지)

**Branch**: `chore/spec-004-decision-screens` (구현은 Issue별 `feat/<issue>-<slug>`) | **Date**: 2026-11-10 | **Spec**: [spec.md](spec.md)

**Input**: `specs/004-decision-screens/spec.md`(R-301~R-319), 확인 질문 셋 debate(research R2~R4)

## Summary

spec 003이 저장한 판단 결과를 노치와 설정 창, 온보딩에 보인다. 노치 펼친 화면에 이유 줄(D-n, 손해, 미룬 횟수)을 두고, concrete가 임계값 미만인 할 일이 시작 전으로 뜨면 구체화 게이트가 첫 행동 한 줄을 받는다. 재판정은 새 질의 경로 없이 spec 003의 "판단 입력이 바뀌면 다시 묻기" 규칙으로 일어난다. 첫 행동이 판단 입력에 들어 있기 때문이다(research R5). 게이트 판정과 이유 줄 글자는 MokaCore 순수 함수로 두어 리눅스 `swift test`로 확인하고, 앱은 메모리 기록, 첫 행동 쓰기, 화면만 맡는다. 온보딩 맨 앞에 키 단계를 더하고, 401 뒤 키 확인 필요를 노치 펼친 화면과 할 일 탭에도 보인다. 스키마, `questions.json`, 공급자 경계, `moka-sim` 형식, 로그 값은 바꾸지 않는다. 규칙 원본은 [data-model.md](data-model.md), 결정 근거는 [research.md](research.md)다.

## Technical Context

**Language/Version**: Swift 6(언어 모드 6, ADR-0001)

**Primary Dependencies**: GRDB 7.11.1(기존). 새 의존성 없음

**Storage**: 바꾸지 않는다. 첫 행동은 기존 `tasks.first_action` 열을 기존 `StoreBatch(updatedTasks:)`로 쓴다. 게이트 기록은 메모리. 키는 spec 003 Keychain 그대로

**Testing**: Swift Testing(`MokaCoreTests`, 리눅스 CI `core-test`), XCTest `MokaAppTests`(macOS 로컬과 CI `app-snapshots`, 필수 아님). 가짜 공급자와 가짜 키 보관함만 쓴다

**Target Platform**: macOS 14+ 메뉴 막대 앱(ADR-0005), Package는 리눅스에서도 빌드

**Project Type**: 데스크톱 앱 + Swift Package

**Performance Goals**: 노치 펼침·접힘 100ms 이내(PRD FR-06)를 지킨다. 이유 줄은 계산 속성이라 질의를 기다리지 않는다. 게이트 통과는 답이 저장된 뒤 1초 안에 화면에 반영된다(SC-303)

**Constraints**: 실제 시간을 기다리는 시험 금지(헌법 II). 실제 판단 API, Keychain, 앱 DB는 시험·CI에서 열지 않는다(헌법 VIII). 기존 golden 바이트와 스냅샷 참조 이미지 그대로. `decisions_log`에 새 줄 종류 없음. `@unchecked Sendable` 금지

**Scale/Scope**: MokaCore 파일 둘(이유 줄, 게이트), 뷰 셋(펼친 화면, 할 일 탭, 온보딩)에 인자 추가, 새 스냅샷 상태 열넷 남짓

## Constitution Check

*GATE: Phase 0 전 확인, Phase 1 설계 뒤 다시 확인함.*

확인 질문 셋은 2026-11-10 무인 실행에서 debate로 정했다(모두 3:0, 기록은 로컬 `.audit/debate/20261110-0100-spec004-clarify.md`, 커밋 안 함). 나머지는 메인 세션 판단이며 research R5~R10과 PR "가정"에 있다.

| 원칙 | 판정 | 근거 |
|---|---|---|
| I 승인 없는 계약 변경 금지 | 통과(승인 항목 없음) | 스키마, `questions.json`, DecisionProvider, `moka-sim` 형식, `user_action`·`scheduler_choice` 값, 의존성, CI를 바꾸지 않는다. 아래 "승인 항목" 표 |
| II 테스트 먼저, 약화 금지 | 통과 | R-ID마다 Red 커밋 다음 Green 커밋. 게이트 기다림은 가짜 공급자를 붙잡고 풀어 만든다. 기존 스냅샷은 새 인자 기본값으로 그대로 둔다(research R9) |
| III 네 가지로만 보고 | 통과 | quickstart. 실제 판단 결과에 달린 게이트 확인은 열리지 않으면 SKIP |
| IV 같은 실패 2회 중단 | 통과 | 해당 시 handoff |
| V 작은 PR | 통과 | 아래 작업 단위 넷을 각각 PR로 |
| VI ID로 추적 | 통과 | 시험 표시 이름 `FR-04 R-30x`, `FR-13 R-30x`, `FR-21 R-31x`, `FR-14 R-31x`(ADR-0003) |
| VII 보호 장치 우회 금지 | 통과 | 해당 없음 |
| VIII 판단 모델은 판단만 | 통과 | 게이트 판정, 횟수, 넘기기는 코드가 한다. 판단 입력은 spec 003 그대로이고 첫 행동은 이미 들어 있는 칸이다 |
| 보안·사용자 데이터 | 통과 | 온보딩 키도 spec 003 `saveKey`로 Keychain에만. 게이트 줄은 로그에 남기지 않는다. 픽스처와 시안은 가짜 예시 |

설계 뒤 재확인: 위반 없음. Complexity Tracking 해당 없음.

### 승인 항목

없음. 승인 항목(공개 계약, DB 스키마, 의존성, CI, 모듈 경계, 저장소·권한 설정)이 생기지 않게 설계했다.

| 바꿀 수 있었던 것 | 이 plan | 근거 |
|---|---|---|
| 게이트 기록 저장(설정 표 키 추가) | 메모리만 | research R3 |
| concrete만 묻는 새 질의 | spec 003 다시 묻기 규칙 | research R5 |
| 게이트 입력 로그(새 `user_action`) | 남기지 않음 | spec R-312 |
| 게이트 할 일을 질의 줄 앞으로(`needsQuery` 순서) | 바꾸지 않음 | spec 위험 2 |

사람이 볼 결정은 debate로 정한 Q1~Q3의 확인과 화면 시안 확정이다.

### 가정

- 이름: `ReasonLine`, `ReasonText`, `DeadlineDistance`, `ConcreteGate`, `GateRecord`, `GatePhase`, `GateInput`, `OnboardingKeyInput`, `settingsTabRequest`.
- `Defaults.concreteGateMaxSubmissions = 3`을 `Defaults.swift`에 둔다(PRD FR-13 값, 새 값 아님).
- 발급 링크 주소는 앱 상수 한 곳에 둔다. 사람이 시안 확정 때 TypeSafe 공식 문서에서 정한다.
- 온보딩 키 단계 실패 문구는 spec 003 `keyActionFailure`를 함께 쓴다. 그래서 온보딩에서 실패하면 설정 창 기본 탭에도 같은 실패 문구가 보인다. 다음 성공에 둘 다 사라진다.

## Project Structure

### Documentation (this feature)

```text
specs/004-decision-screens/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── checklists/requirements.md
└── tasks.md            # /speckit-tasks
```

contracts/는 두지 않는다. 외부에 보이는 계약(질문 파일, 공급자, 시뮬레이터 형식)을 바꾸지 않는다.

### Source Code (repository root)

```text
Sources/MokaCore/
├── Decision/ReasonLine.swift         # 새: DeadlineDistance, ReasonLine.make, ReasonText.line
├── Decision/ConcreteGate.swift       # 새: GateRecord, GatePhase, 판정 함수
└── Defaults.swift                    # concreteGateMaxSubmissions
App/Sources/
├── AppState.swift                    # 게이트 기록·판정 호출·첫 행동 쓰기·넘기기, reasonLine, showsKeyNotice, settingsTabRequest, 온보딩 키 입력
├── Views/ExpandedView.swift          # 이유 줄, 게이트, 키 확인 한 줄, 시작 단축키 조건
├── Views/NotchContentView.swift      # 새 인자 전달
├── Views/TaskListTabView.swift       # 키 확인 한 줄
├── Views/OnboardingView.swift        # 키 단계(입력이 있을 때만 세 단계)
├── Notch/NotchPanelHost.swift        # AppState 값과 설정 열기 동작 연결
├── Settings/SettingsView.swift       # settingsTabRequest 소비, 할 일 탭 인자
└── MokaApp.swift                     # 온보딩에 키 입력 넘김
Tests/MokaCoreTests/ReasonLineTests.swift, ConcreteGateTests.swift   # 새
App/Tests/MokaAppTests/AppGateTests.swift(새), AppDecisionTests.swift, ScreenStateSnapshotTests.swift, SettingsSnapshotTests.swift
```

**Structure Decision**: ADR-0001 구조 그대로다. 새 타깃과 의존성은 없다. 판단 관련 Core 파일은 `Sources/MokaCore/Decision/` 아래에 둔다. 뷰는 스냅샷 번들이 컴파일하는 `App/Sources/Views/`에 두고 `AppState`를 모르게 한다(ADR-0009). `SettingsTab`은 이미 `Views/`에 있어 앱 시험 번들이 `settingsTabRequest`를 컴파일할 수 있다.

### 앱 연결

- 게이트 판정은 AppState의 한 함수(`refreshGate()`)가 맡는다. 부르는 곳은 노치 할 일 변경(`session` didSet), 답 저장 뒤, 실패를 장부에 적은 뒤, `reloadTasks` 뒤, `keyNeedsCheck`·`hasKey` 변경 뒤다(data-model §3).
- 첫 행동 쓰기는 `editTask`처럼 `write(StoreBatch(updatedTasks:))` 뒤 `reloadTasks()`다. `reloadTasks`가 이미 `requestScores()`를 부르므로 질의를 따로 부르지 않는다.
- 노치 키 확인 한 줄의 동작은 `settingsTabRequest = .basic` 다음 기존 "설정…"과 같은 순서(`SettingsWindowRaiser.request`, `NSApp.activate`, `openSettings`)로 창을 연다. 패널 쪽 연결은 `NotchPanelHost`가 맡는다.

## 작업 단위 (tasks.md의 뼈대, Issue 후보)

| # | 단위 | R-ID | 시안 확정 | 무인 가능 | 앞선 단위 |
|---|---|---|---|---|---|
| 1 | MokaCore 규칙: 이유 줄 값과 글자, 게이트 판정 함수, `Defaults` 값 | R-302·303·304·306(판정)·308(판정)·309(판정) | 아니오(글자 구분자만 시안 뒤 확정, 시험은 값 기준) | 예 | 없음 |
| 2 | AppState 연결: 게이트 기록·판정 호출·첫 행동 쓰기·넘기기·시작과 할 일 변경 때 닫기, `reasonLine`, `showsKeyNotice`, `settingsTabRequest`, 앱 시험 | R-305·307(동작)·308·309·310·312·318 | 아니오 | 예 | 1 |
| 3 | 노치 화면: 이유 줄, 게이트 셋, 키 확인 한 줄, 시작 단축키 조건, 패널 연결, 스냅샷 | R-301·307(화면)·311·316 | 예(004 시안) | 코드는 가능, 화면 확정과 실제 판단 결과 확인은 사람 | 2 |
| 4 | 설정 창과 온보딩: 할 일 탭 키 확인 한 줄, 설정 탭 요청 소비, 온보딩 키 단계, 스냅샷 | R-313·314·315·317 | 예(004 시안) | 코드는 가능, 새 사용자 첫 실행은 사람 | 2 |

R-319(가짜 공급자만, 계약 그대로)는 모든 단위에 걸친다.

순서: 1 다음 2, 그다음 3과 4를 나란히. 시안 `004-mockup.html`은 단위 1과 함께 확정을 받는다. 밀리면 단위 4의 온보딩 키 단계(R-313~R-315)를 먼저 다음 spec으로 넘긴다(spec 위험 1).

## PRD·spec 003 대조

| 출처 | 이 plan | 처리 |
|---|---|---|
| PRD 6장 재판정 질문 concrete 하나 | 질문 넷을 함께 다시 묻기 | research R5, spec 위험 7 |
| PRD FR-04 손해 옵션 "보통/큼/치명적" | "조금/꽤/아주" | spec 003 R-202 |
| PRD FR-11 모든 입력 기록 | 게이트 입력은 기록하지 않음 | spec R-312, 위험 4 |
| PRD FR-13 "현재 할 일로 뜰 때" | 시작 전에만 열고 넘기기 있음 | research R2·R10 |
| spec 003 R14 온보딩 키 단계 기각 | 이번에 넣음, 사람 확인은 새 사용자 계정 | spec 위험 6 |
| spec 002 R-116 "시작하기"에서 한꺼번에 저장 | 키만 단계에서 바로 저장 | research R7 |
| spec 002 시안 9번 첫 행동은 체크포인트에서만 바뀜 | 게이트가 둘째로 씀, 마지막 값이 남음 | spec 위험 3 |
| spec 003 data-model §6 `needsQuery` 순서 | 그대로(게이트 할 일이 뒤에 설 수 있음) | spec 위험 2 |

## 위험

spec "대안과 위험"의 번호와 같다.

- 위험 1(일정): 필수는 단위 1·2·3(FR-04, FR-13). 밀리면 온보딩 키 단계, 그다음 할 일 탭 키 확인 순으로 넘긴다.
- 위험 2(게이트 기다림): 전체 재질의 중에 게이트 할 일이 줄 뒤에 선다. 기다리는 동안 시작 버튼과 넘기기가 켜져 있어 사용자를 막지 않는다. 검증 첫 주에 길게 보이면 다음 spec에서 `needsQuery` 순서를 다시 본다(승인 항목이 아니라 spec 003 규칙 변경이라 debate).
- 위험 3(첫 행동 쓰는 곳 둘): 게이트 줄과 체크포인트 다음 할 일 줄이 같은 칸을 쓴다. 마지막에 쓴 값이 남는다. 앱 시험으로 두 순서를 모두 확인한다.
- 위험 4(라벨 공백): 게이트 입력과 넘기기가 로그에 없어 concrete 튜닝 라벨이 없다. 마일스톤 5 튜닝 때 새 행동 값을 승인 항목으로 올린다.
- 위험 5(개인정보): 게이트 줄은 첫 행동 칸으로 판단 모델에 간다. spec 003부터 보내던 칸이다.
- 위험 6(사람 확인): 온보딩 키 단계는 새 사용자 계정에서만 볼 수 있다. 앱 시험과 스냅샷이 대부분을 맡는다.
- 위험 7(PRD와 다름): 위 대조 표의 PRD 줄. 사람이 PRD를 고친다.
- 위험 8(키 실패 문구 공유): 온보딩 키 저장 실패가 설정 창 기본 탭에도 보인다. 다음 성공에 둘 다 사라져 받아들인다.

## 다음 단계

1. `/speckit-tasks`
2. 시안 `004-mockup.html` 사람 확정
3. spec·plan·tasks PR 병합 뒤 Issue 큐(단위 1, 2, 3과 4)
