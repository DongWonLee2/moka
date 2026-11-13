# Implementation Plan: 사용 안내 (도움말 탭과 온보딩 안내 장)

**Branch**: `chore/spec-007-user-guide` (구현은 Issue별 `feat/<issue>-<slug>`) | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: `specs/007-user-guide/spec.md`(R-701~R-718, SC-701~SC-708), 확정한 것 Q1~Q12(debate 2026-11-12, 사용자 결정 2026-11-12), 확정 시안 `~/Dev/ai-platform/projects/moka/design/007-mockup.html` v2 화면 1~15(시안 확정 2026-11-13(사용자)). 기준 `origin/main` `fa17f19`.

## Summary

설정 창에 넷째 탭 "도움말"을 더하고, 항목 여덟의 글을 화면 상수에서 보간해 만든다(인용이 화면 글자와 어긋나면 시험이 실패). 온보딩 `OnboardingSteps` 맨 앞에 안내 장 셋을 더해 n/6(키 단계가 없으면 n/5)으로 세고, 안내 장 그림은 `NotchContentView`에 가짜 값을 넣어 그린다. 도움말 탭 맨 위 "안내 다시 보기"는 설정 창 위 시트로 안내 장 셋만 다시 보인다. 저장하는 값, 스키마, 설정 키, 공개 계약, 의존성, CI는 바꾸지 않는다. 규칙 원본은 [data-model.md](data-model.md), 결정 근거는 [research.md](research.md), 확인 순서는 [quickstart.md](quickstart.md)다.

## Technical Context

**Language/Version**: Swift 6(언어 모드 6, ADR-0001)

**Primary Dependencies**: SwiftUI, GRDB 7.11.1(기존, 이 plan은 쓰지 않음). 새 의존성 없음

**Storage**: 없음. 도움말 펼침은 `AppState` 메모리(research R3). 설정 키를 더하지 않는다(Q10)

**Testing**: XCTest `MokaAppTests`(macOS 로컬과 CI `app-snapshots`, 필수 아님), Swift Testing `MokaCoreTests`(리눅스 CI `core-test`, `ReasonText.deadline` 시험 하나). 가짜 값만 쓴다

**Target Platform**: macOS 14+ 메뉴 막대 앱(ADR-0005)

**Project Type**: 데스크톱 앱 + Swift Package

**Performance Goals**: 노치 펼침·접힘 100ms(PRD FR-06)는 이 plan이 건드리지 않는다. 안내 장 그림은 정적이라 타이머를 돌리지 않는다

**Constraints**: 실제 판단 API, Keychain, 앱 DB를 시험에서 열지 않는다(헌법 VIII). 화면 글자는 바꾸지 않고 상수로만 꺼낸다(기존 스냅샷 그림 그대로). `@unchecked Sendable` 금지. 시험 번들은 `App/Sources/Views`와 `AppState.swift`만 컴파일한다(`project.yml`)

**Scale/Scope**: 새 파일 다섯 남짓(`NotchText`, `HelpContent`, `HelpTabView`, `GuideCardView`·`GuideButtons`·`GuideIllustration`, `GuideSheetView`), 고치는 파일 14개(`SettingsTabBar`, `SettingsView`, `OnboardingView`, `MokaApp`, `AppState`, `ExpandedView`, `ExpiredView`, `GateView`, `TaskListTabView`, `CheckpointNotesView`, `TaskFormView`, `ContextFormView`, `NotchPanelHost`, MokaCore `ReasonLine`), 새 스냅샷 상태 열여섯

## Constitution Check

*GATE: Phase 0 전 확인, Phase 1 설계 뒤 다시 확인함.*

| 원칙 | 판정 | 근거 |
|---|---|---|
| I 승인 없는 계약 변경 금지 | 통과(승인 항목 없음, 아래) | 공개 계약, 스키마, 의존성, CI, 모듈 경계를 바꾸지 않는다 |
| II 테스트 먼저, 약화 금지 | 통과 | 단위마다 Red 커밋 다음 Green 커밋. `OnboardingSteps` 기존 시험은 `hasGuide: false` 인자만 더하고 기대값은 그대로 둔다(research R5). 온보딩 스냅샷 시험은 `initialStep`만 3 올린다 |
| III 네 가지로만 보고 | 통과 | quickstart. 새 사용자 첫 실행과 시트 띄우기는 사람이 하고, 하지 않으면 NOT_RUN |
| IV 같은 실패 2회 중단 | 통과 | 해당 시 handoff |
| V 작은 PR | 통과 | 아래 작업 단위 셋을 각각 PR로 |
| VI ID로 추적 | 통과 | 시험 표시 이름 `R-7xx`로 시작(ADR-0003) |
| VII 보호 장치 우회 금지 | 통과 | 해당 없음 |
| VIII 판단 모델은 판단만 | 통과 | 판단 입력과 공급자 경로를 건드리지 않는다. 도움말 "보내는 곳" 글은 `JudgmentState` 칸을 사용자 말로 옮긴 것이다 |
| 보안·사용자 데이터 | 통과 | 도움말과 시트는 저장소·키 보관함을 받지 않는다(타입으로 막음). 그림과 시험은 가짜 할 일만 |

설계 뒤 재확인: 위반 없음. Complexity Tracking 해당 없음.

### 승인 항목

없음.

| 항목 | 이 plan | 근거 |
|---|---|---|
| 공개 계약(DecisionProvider, `questions.json`, `moka-sim` 시나리오 형식) | 변경 없음 | spec R-718 |
| 스키마 | 변경 없음. 설정 키도 더하지 않음 | spec R-715, Q10 |
| 의존성 | 변경 없음 | `Package.swift`, `project.yml` 의존성 그대로 |
| CI | 변경 없음 | 워크플로 파일 그대로 |
| 모듈 경계 | 변경 없음. 새 타깃·제품 없음, `project.yml`의 `sources` 목록 그대로(새 파일은 기존 폴더 `App/Sources/Views`에 둠) | research R8 |

같은 모듈 안 접근 수준 조정 둘(`ReasonText.deadline`을 `public`, `RankBadge`를 `internal`)은 승인 항목이 아니다. 구현 PR "가정"에 적는다(research R10).

### 가정

- 이름: `HelpTopic`, `HelpBody`, `ShortcutRow`, `HelpContent`, `HelpText`, `HelpTabView`, `GuideCard`, `GuideText`, `GuidePresentation`, `GuideButtons`, `GuideCardView`, `GuideIllustration`, `GuideSheetView`, `NotchText`, `SheetText`, `TaskListText`, `AppState.helpExpanded`.
- 도움말 펼침은 `AppState`에 둔다(research R3). spec R-707에 반영했다.
- 기존 온보딩 스냅샷 그림은 단계 표시가 바뀌어 다시 찍는다(SC-707).

## Project Structure

### Documentation (this feature)

```text
specs/007-user-guide/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/MokaCore/Decision/ReasonLine.swift   # ReasonText.deadline 접근 수준만 public
App/Sources/
├── Views/NotchText.swift          # 새: 노치·메뉴·시트 버튼 글자 상수(화면 글자 그대로)
├── Views/HelpContent.swift        # 새: HelpTopic, HelpBody, ShortcutRow, HelpContent, HelpText
├── Views/HelpTabView.swift        # 새: 맨 위 줄과 접었다 펼치는 목록
├── Views/GuideCardView.swift      # 새: GuideCard, GuideText, GuidePresentation, GuideButtons, GuideCardView
├── Views/GuideIllustration.swift  # 새: NotchContentView에 가짜 값
├── Views/GuideSheetView.swift     # 새: 시트 내용
├── Views/OnboardingView.swift     # OnboardingSteps에 guide 쪽, showsGuide, skipGuide
├── Views/SettingsTabBar.swift     # help 탭과 아이콘
├── Views/ExpandedView.swift, ExpiredView.swift, CheckpointNotesView.swift, GateView.swift,
│   TaskListTabView.swift, TaskFormView.swift, ContextFormView.swift   # 글자를 상수로(화면 그대로), RankBadge internal
├── Notch/NotchPanelHost.swift     # 우클릭 메뉴 "종료"를 상수로
├── Settings/SettingsView.swift    # help 탭 연결, 시트
├── AppState.swift                 # helpExpanded
└── MokaApp.swift                  # 메뉴 글자 상수, 온보딩 showsGuide: true
Tests/MokaCoreTests/ReasonLineTests.swift            # deadline 표기 시험 하나 더함
App/Tests/MokaAppTests/
├── HelpContentTests.swift          # 새: 따옴표 검사, 글 고정, 문장 수, 목차 순서
├── GuideTests.swift                # 새: GuideButtons 표, OnboardingSteps 안내 장 이동
├── OnboardingKeyStepTests.swift    # 호출에 hasGuide: false
├── AppDecisionTests.swift 또는 새 AppHelpTests.swift  # helpExpanded
└── SettingsSnapshotTests.swift     # 새 스냅샷, 기존 온보딩 스냅샷 initialStep
```

**Structure Decision**: ADR-0001 구조 그대로다. 새 뷰와 규칙은 모두 `App/Sources/Views/`에 두어 시험 번들이 컴파일한다(research R8). 뷰는 `AppState`를 모르게 값과 콜백만 받는다(ADR-0009).

### 설계 요점

- **도움말 글과 시험(SC-703)**: `HelpContent`가 화면 상수로 글을 보간한다. 시험 셋(따옴표 검사, 글 고정, 문장 수)은 research R1, 인용 출처 표는 data-model §3.
- **안내 장 그림**: `GuideIllustration`이 `NotchContentView`(그리고 순위 장의 `RankBadge`)에 가짜 값을 넣고 누를 수 없게 그린다. `.allowsHitTesting(false)`로는 단축키와 자동 포커스가 꺼지지 않으므로, 환경 값 `\.isNotchIllustration`을 참으로 넣어 그림 속 "시작"의 기본 버튼 단축키를 떼고(`GateDisplay.detachesStartShortcut`에 `isIllustration`) 게이트·제목 칸의 자동 포커스를 건너뛴다(`GateDisplay.requestsFocus`). research R4, data-model §4.
- **시트**: `SettingsView`의 `.sheet`와 `GuideSheetView(onClose:)`. 저장소를 받지 않아 쓰기 0건. 창이 사라질 때(`.onDisappear`) 시트 상태를 비운다. research R6, data-model §6.
- **온보딩 단계**: `OnboardingSteps(hasGuide:hasKeyStep:initialStep:)`, 안내 장 셋이 맨 앞, n/6 또는 n/5, `skipGuide()`(안내 장이 아닌 첫 쪽으로), `submitKey`는 키 단계에서만, `canFinish`는 기본값 쪽에서만. research R5, data-model §5.
- **버튼 규칙**: `GuideButtons.make`의 여섯 경우 표. data-model §4.
- **스냅샷**: data-model §7. 비교 페이지는 `~/Dev/ai-platform/projects/moka/design/pr-<번호>/index.html`(ADR-0009).

## 작업 단위 (tasks.md의 뼈대, Issue 후보)

| # | 단위 | R-ID | 승인 | 시안 | 앞선 단위 |
|---|---|---|---|---|---|
| 1 | 도움말 탭: 글자 상수 꺼내기, `HelpContent`와 시험, `HelpTabView`, 넷째 탭, `helpExpanded`, 스냅샷 1~9 | R-701~R-709, R-716(도움말), R-717·R-718 | 없음 | 확정 1~9 | 없음 |
| 2 | 온보딩 안내 장: `GuideCard`·`GuideButtons`·`GuideCardView`·`GuideIllustration`, 그림 쪽 단축키·포커스 끄기, 안내 장 인용 시험, `OnboardingSteps` 확장, `showsGuide`, 스냅샷 10~13 | R-705(안내 장 인용), R-710~R-712, R-715, R-716(안내 장), R-717·R-718 | 없음 | 확정 10~13 | 단위 1의 글자 상수(T007) 병합 뒤. 안내 장 글이 "시작"·"이어서 할 일"·"지금은 넘기기"를 `NotchText`·`GateDisplay` 상수로 인용하기 때문이다. 그 뒤로는 단위 1의 나머지와 나란히 가능(겹치는 파일은 `SettingsSnapshotTests.swift`. 나중에 병합하는 쪽이 충돌을 푼다) |
| 3 | 안내 다시 보기 시트: `GuideSheetView`, `SettingsView` 시트 연결, 스냅샷 14·15 | R-713·R-714, R-717·R-718 | 없음 | 확정 14·15 | 1(버튼 자리), 2(`GuideCardView`) |

밀리면 단위 3을 먼저 넘긴다(spec 단위 나누기). 접근 수준 조정은 먼저 들어가는 단위가 한다(`ReasonText.deadline`은 단위 1의 인용, `RankBadge`는 단위 2의 그림).

## 앞 spec 대조

| 출처 | 이 plan | 처리 |
|---|---|---|
| spec 002 R-116 온보딩 두 단계, spec 006 R-624 세 단계 | 안내 장 셋을 맨 앞에 더해 여섯(키 단계 없으면 다섯) | spec 002·006에 대체 표기는 하지 않는다. 설정 단계 규칙은 그대로이고 앞에 쪽이 더해질 뿐이다. 용어집 onboarding 항목은 단위 2 PR에서 "안내 장 셋과 설정 단계 셋"으로 고친다 |
| spec 001 R-012 메뉴 항목 둘 | 그대로. "안내 다시 보기"를 메뉴에 두지 않음 | Q5 |
| spec 004 R-307 게이트 글자 | 상수 `GateDisplay`를 인용만 함 | 화면 글자 그대로 |
| PRD FR-21 첫 실행 3단계 | 6단계(5단계)로 달라짐 | spec 위험 5. PRD는 저장소 밖이라 사람이 고친다 |
| 기본 탭 "추가 시간" 안내와 이어 가기 동작 | 도움말에서 설명하지 않음 | spec 위험 6. #151에서 해결(이어 가기 처음 값 = 추가 시간) |

## 위험

spec "대안과 위험"의 번호와 같다.

- 위험 1(글이 낡음): 글 고정 시험이 화면 상수 변경을 잡지만 동작 규칙 변경은 잡지 못한다. 규칙을 바꾸는 spec은 도움말 항목도 함께 본다.
- 위험 2(온보딩이 길어짐): 조작은 "안내 건너뛰기"로 한 번만 는다(SC-704).
- 위험 3(스냅샷 변경): 탭 줄과 단계 표시 때문에 기존 그림이 다시 찍힌다. 비교 페이지에서 그 밖이 바뀌지 않았는지 사람이 본다.
- 위험 4(사람 확인): 새 사용자 첫 실행(quickstart 6-3)과 시트 띄우기(6-2)는 시험 번들 밖이라 사람이 본다.
- 위험 5(PRD FR-21): 사람이 PRD를 고친다.
- 위험 6(추가 시간 문구): 해결됨. 이어 가기 처음 값을 추가 시간으로 바꿨다([Issue #151](https://github.com/DongWonLee2/moka/issues/151)).
- 위험 7(그림 크기): 안내 장 그림의 노치 판은 실제보다 작다(research R4). 사람이 확정 시안 10~12번과 비교 페이지에서 본다.
- 위험 8(시트와 설정 창 닫기): 시트가 붙은 설정 창의 닫기가 막히는지, `Settings` 장면이 창을 닫아도 `@State`를 남기는지 직접 확인하지 못했다. `.onDisappear`에서 시트 상태를 비우는 대안을 처음부터 쓰고, 사람이 quickstart 6-2에서 본다(research R6). 결과(사람 확인 2026-11-13): 시트가 열린 채로는 설정 창이 닫히지 않아 R-714를 그에 맞게 고쳤다.
- 위험 9(그림 단축키): 환경 값을 읽지 않는 노치 부품이 새로 생기면 그림 속 단축키가 다시 살아날 수 있다. 단위 시험은 `GateDisplay` 함수만 지키므로 사람이 quickstart 6-3에서 Enter로 안내 장을 넘겨 본다.

## 다음 단계

1. `/speckit-tasks`(이 PR에 포함)
2. 이 spec PR 병합 뒤 Issue 셋(단위 1, 2, 3)
