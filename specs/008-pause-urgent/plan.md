# Implementation Plan: 일시 중지와 급한 일 끼워 넣기

**Branch**: `chore/spec-008-plan` (구현은 Issue별 `feat/<issue>-<slug>`) | **Date**: 2026-11-18 | **Spec**: [spec.md](spec.md)

**Input**: `specs/008-pause-urgent/spec.md`(R-801~R-808, R-811~R-815, R-831~R-838), 토론 기록 셋(저장소 밖 `.audit/debate/20261118-spec008-clarify.md`, `20261118-spec008-pause-freeze-r1-raw.md`, `20261118-spec008-plan.md`), 기준 `origin/main` `2629d8c`

**상태: 초안.** 설계 결정 P1~P11은 토론 3:0으로 정했다(아래 "정한 것"). 시안 글자 M1~M19의 사람 확정이 남았고, 승인 항목은 구현 PR 병합으로 사람이 승인한다.

## Summary

MokaCore에 일시 중지 상태와 전이, 멈춘 작업 시간의 남은 초와 돌려주기, 하루 경계 처리, 노치 모드 `.paused`, 긴급 입력과 긴급 고정, 복귀 제안을 순수 로직으로 둔다. 시간 규칙은 주입한 `MokaClock`·`Calendar`로 리눅스 `swift test`에서 시험한다. 스키마는 바꾸지 않는다. 행동 로그에 사용자 행동 값 셋과 선택 규칙 이름 둘을 더하고, `moka-sim`은 일시 중지·다시 시작·긴급 입력과 출력 키를 받는다. 앱은 순수 로직을 연결한 뒤 확정 시안 글자로 화면을 만든다. 규칙 원본은 [data-model.md](data-model.md), 근거와 선택지는 [research.md](research.md), 공개 계약은 [contracts/](contracts/)다.

## Technical Context

**Language/Version**: Swift 6(언어 모드 6, ADR-0001), Python 3(튜닝 계약 pytest)

**Primary Dependencies**: GRDB 7.11.1(기존). 새 의존성 없음

**Storage**: 스키마 변경 없음. 설정 키 `default_pause_min` 하나를 기존 `settings` 표에 더한다. 일시 중지 상태와 긴급 고정은 메모리에만 둔다(R-807, R-813)

**Testing**: Swift Testing(`MokaCoreTests`, `MokaStoreTests`, 리눅스 CI `core-test`), XCTest `MokaAppTests`(macOS 로컬과 CI `app-snapshots`), pytest(`tuning-test`). 가짜 판단 공급자, `InMemory*` 저장소, 주입한 시계만 쓴다

**Target Platform**: macOS 14+ 메뉴 막대 앱(ADR-0005), Package는 리눅스에서도 빌드

**Project Type**: 데스크톱 앱 + Swift Package

**Performance Goals**: 긴급 입력 마지막 제출 뒤 10초 안에 긴급 할 일이 돈다(R-812, SC-803). 노치 펼침·접힘 100ms(PRD FR-06)

**Constraints**: 실제 판단 API, Keychain, 앱 DB를 시험·CI·시뮬레이터에서 열지 않는다(R-835, 헌법 VIII). `@unchecked Sendable` 금지. 새 이벤트가 없는 시나리오의 golden은 바이트 그대로(R-834)

**Scale/Scope**: MokaCore 새 파일 둘 안팎(일시 중지 상태, 긴급 입력), 고치는 MokaCore 파일 열 안팎과 시뮬레이터 넷, 앱은 `AppState`와 노치 뷰 넷, 기본 탭, 도움말. 자리는 data-model §12

## Constitution Check

*GATE: Phase 0 전 확인, Phase 1 설계 뒤 다시 확인함.*

| 원칙 | 판정 | 근거 |
|---|---|---|
| I 승인 없는 계약 변경 금지 | 통과(승인 항목 아홉, 아래 표) | 구현 PR "사람이 볼 결정"에 올리고 병합이 승인이다. P1~P11의 추천안은 토론 3:0으로 정했다 |
| II 테스트 먼저, 약화 금지 | 통과 | 단위마다 Red 커밋 다음 Green 커밋. `ValueTypeTests`의 `allCases`는 값 덧붙이기다 |
| III 네 가지로만 보고 | 통과 | quickstart. 실제 앱 확인은 사람이 하고, 하지 않으면 NOT_RUN |
| IV 같은 실패 2회 중단 | 통과 | 해당 시 handoff |
| V 작은 PR | 통과 | 작업 단위 일곱을 각각 PR로 |
| VI ID로 추적 | 통과 | 시험 표시 이름 `FR-20 R-80x`, `FR-19 R-81x`, 공통 `R-83x`(ADR-0003) |
| VII 보호 장치 우회 금지 | 통과 | 해당 없음 |
| VIII 판단 모델은 판단만 | 통과 | 긴급 고정과 일시 중지는 판단 입력에 넣지 않는다 |
| 보안·사용자 데이터 | 통과 | 픽스처·시안은 가짜 할 일 |

설계 뒤 재확인: 위반 없음. Complexity Tracking 해당 없음.

### 승인 항목

| # | 항목 | 이 plan | 단위 | 계약 문서 |
|---|---|---|---|---|
| 1 | 공개 타입 `NotchTimer`에 case `paused`를 더함(P1) | data-model §1 | 1 | 없음 |
| 2 | 행동 로그 사용자 행동 값 `pause`·`resume`·`urgent` | data-model §10 | 1(`pause`·`resume`), 2(`urgent`) | [storage-values-008.md](contracts/storage-values-008.md) §2 |
| 3 | 선택 규칙 이름 `urgent_pin_v1`·`urgent_return_v1` | data-model §10 | 2 | 같은 문서 §3 |
| 4 | `moka-sim` 입력 이벤트 `pause`·`resume`·`urgent`, 출력 키, 불변식(P8) | 새 이벤트가 있을 때만 켬 | 1·2 | [moka-sim-v1-additions-008.md](contracts/moka-sim-v1-additions-008.md) |
| 5 | 설정 키 `default_pause_min`, 범위는 `Defaults.quantumMinRange`(P10) | data-model §11 | 3(읽기·쓰기), 4(칸) | storage-values §5 |
| 6 | `Defaults.swift` 새 값: 기본 일시 중지 30분, 선택지 30·60·120분 | data-model §11 | 1 | 없음 |
| 7 | 모듈 경계: `TaskRepository`에 긴급 전용 메서드를 더함(P7) | data-model §8 | 2 | 없음 |
| 8 | 모듈 경계: `NotchSession`에 칸 `urgent`, `PriorityOrder.order`·`PickInput`에 고정 값 입력(P5) | data-model §9 | 2 | 없음 |
| 9 | spec 005 동작 변경: 도는 중 할 일을 지워도 남은 초를 돌려줌(P4) | data-model §3 | 1(함수), 3(앱) | 없음 |

바꾸지 않는 것: DB 스키마, 의존성, CI, `Package.swift` 타깃, `project.yml`, `questions.json`, `DecisionProvider`, 판단 입력, 채택된 ADR 본문.

### 정한 것 (처음 "확정할 것", 2026-11-18)

선택지와 대가, 근거 경로는 [research.md](research.md)의 같은 번호 절에 있다. 기록은 저장소 밖 `.audit/debate/20261118-spec008-plan.md`다. 소수 의견은 2라운드에서 모두 수렴해 남지 않았다.

| P | 결정 | 답 | 표결 | 단위 |
|---|---|---|---|---|
| P1 | `NotchTimer`에 멈춤 상태를 넣는 모양 | A 새 case `paused`. 남은 초와 고른 분은 타이머 case 한 곳에 | 1라운드 3:0 | 1 |
| P2 | 긴급 칩을 고를 때 남은 분이 0 | A 늘리기 확인으로 시작, 거절 버튼은 "돌아가기" | 1라운드 3:0 | 2·6 |
| P3 | 두 줄을 적는 동안 하루 경계를 넘김 | A `pause` 뒤 같은 처리에서 `day_end`, (나) 경계 뒤 돌아가기도 끝냄 | A 1라운드 3:0, (나) 2라운드 3:0 | 1 |
| P4 | 도는 중 할 일을 지울 때 남은 초 | B 돌려줌(spec 005 동작 변경) | 2라운드 3:0 | 1·3 |
| P5 | 긴급 고정·복귀 상태를 둘 곳 | B `NotchSession` 칸 `urgent`, init 인자 기본값 없음 | 2라운드 3:0 | 2 |
| P6 | 일시 중지 끝을 재는 타이머 | A 1초 타이머 하나, 기다리는 동안 끔, 끝 펼침 한 번 | 1라운드 3:0 | 3 |
| P7 | 긴급 입력을 한 번에 쓰는 저장 경계 | A `TaskRepository` 긴급 전용 메서드 | 1라운드 3:0 | 2 |
| P8 | `moka-sim` 일시 중지 입력 모양 | A 이벤트 하나 `pause`, 나머지 경우는 단위 시험 | 2라운드 3:0 | 1 |
| P9 | 긴급 입력 동안 줄어드는 돌려받을 시간 | B 제출 때 칩을 실제 남은 분으로 줄임, 1분 미만이면 P2 확인 | 2라운드 3:0 | 2·5 |
| P10 | 일시 중지 직접 입력 범위 상수 | A `Defaults.quantumMinRange` 같이 씀 | 1라운드 3:0 | 1 |
| P11 | 게이트가 열린 초안에서 일시 중지 | A 누를 수 없음(숨김과 꺼짐은 시안 M1에서 고름) | 1라운드 3:0 | 3·4 |

### 시안에서 확정할 것

시안은 `~/Dev/ai-platform/projects/moka/design/008-mockup.html`(저장소 밖)이다. 글자는 모두 초안이고 사람이 확정한다. 번호는 시안 맨 아래 표와 같다.

| M | 자리 | 초안 글자 | 시안 |
|---|---|---|---|
| M1 | 버튼 이름과 자리, 게이트가 열린 동안의 "일시 중지" | 일시 중지, +긴급. 게이트가 열리면 안 1 숨김, 안 2 꺼 두고 이유 한 줄(첫 행동을 적거나 넘기면 멈출 수 있어요.) | 1-1~1-4번 |
| M2 | 길이 고르기 | 얼마나 멈출까요? · 30분 · 1시간 · 2시간 · 내일 아침까지 · 직접… · 돌아가기 · 멈추기 | 2번 |
| M3 | 일시 중지 두 줄의 안내 | 멈추기 전에 적어 둘까요? | 3번 |
| M4 | 오른쪽 귀 글자 | 멈추는 중 · 일시 중지 · 기다리는 중 · 긴급 · 긴급으로 바꾸는 중 | 2~4·6·8번 |
| M5 | 멈춘 펼친 화면 | 일시 중지 중이에요 · 24:12 뒤에 끝나요 · 작업 시간 15:00 남았어요 · 다시 시작 | 4번 |
| M6 | 멈춘 접힌 노치 | 일시 중지 · 24:12 | 5번 |
| M7 | 길이가 끝난 뒤 펼친 화면 | 일시 중지가 끝났어요 · 다시 시작하면 15:00부터 이어 가요 | 6-1번 |
| M8 | 길이가 끝난 뒤 접힌 노치 | 다시 시작할까요? | 6-2번 |
| M9 | 초안에서 멈춘 화면 | 끝나면 이 할 일이 다시 떠요 | 7-1번 |
| M10 | 돌아온 초안의 안내 | 일시 중지가 끝났어요. 준비되면 시작해 주세요 | 7-2번 |
| M11 | 긴급 입력 | 급한 일이 뭐예요? · 가짜 할 일 A는 끊기 전까지 계속 돌아요. · 돌아가기 · 다음 | 8-1번 |
| M12 | 긴급 두 줄의 안내 | 하던 일을 적어 둘까요? | 8-2번 |
| M13 | 긴급 늘리기 확인 | 오늘 시간을 15분 늘려서 25분 할까요? · 10분만 할래요 · 늘리고 다음 | 9-1번 |
| M14 | 복귀 제안 | 긴급한 일을 끝냈어요. 하던 일로 돌아갈까요? | 10번 |
| M15 | 쓰기 실패 문구 | 일시 중지하지 못했어요. 다시 해 주세요. · 긴급한 일을 넣지 못했어요. 다시 해 주세요. | 3-2·8-3번 |
| M16 | 기본 탭 칸 | 기본 일시 중지 길이 · 일시 중지를 누를 때 먼저 골라 둘 길이예요. | 11번 |
| M17 | 도움말 (1) 노치에 더할 문장 | 자리를 비울 때는 "일시 중지"로 멈추고, 돌아오면 "다시 시작"을 눌러 주세요. 급한 일이 생기면 도는 중에 "+긴급"으로 바로 바꿀 수 있어요. | 12번 |
| M18 | 1시간 넘는 남은 일시 중지 시간의 표시 | 14:20:00(지금 `RemainingFormat` 그대로) | 5-2번 |
| M19 | 남은 시간이 0분일 때 긴급 확인(P2) | 오늘 남은 시간이 없어요. 25분 늘려서 할까요? · 늘리면 오늘 정한 시간이 2시간 25분이 돼요. · 돌아가기 · 늘리고 다음(두 줄을 마친 뒤 뜨면 늘리고 시작) | 9-2·9-3번 |

### 가정 (PR "가정")

- 이름과 값 모양: research R12·R13·R19, data-model §1.
- 제출 때 뜨는 P2 확인의 버튼과 적은 두 줄(research R20).
- "다시 시작" 쓰기 실패(research R14), 일시 중지 동안 기본 작업 시간 변경(R15), 긴급 할 일을 지울 때(R16), 일시 중지 끝의 활성화(R17), 시뮬레이터 켜는 법(R18).
- R-838의 "spec 001 잠자기 체크포인트"는 spec 001에 해당 요구가 없어 실제 규칙이 있는 spec 002 R-110과 spec 001 Edge Case "잠자기"에 표기했다.

## Project Structure

### Documentation (this feature)

```text
specs/008-pause-urgent/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── moka-sim-v1-additions-008.md
│   └── storage-values-008.md
└── checklists/requirements.md
```

`tasks.md`는 시안이 확정된 뒤 `speckit-tasks`로 만든다.

### Source Code (repository root)

```text
Sources/MokaCore/
├── Scheduler/PauseState.swift     # 새: 일시 중지 상태, 길이, 끝 시각, 돌려줄 초
├── Scheduler/UrgentInput.swift    # 새: 긴급 입력 값과 칩 상한
├── NotchTimer.swift               # case paused(P1)
├── NotchSession.swift             # 칸 urgent(P5), 일시 중지·다시 시작·긴급 함수, 멈춤 분기
├── SessionAssembly.swift          # 활성화의 하루 경계 처리, 복귀 띄움
├── Scheduler/NotchMode.swift      # .paused
├── Scheduler/AutoStart.swift      # 입력 전 자동 시작 막기
├── Scheduler/SchedulerPick.swift  # 긴급 고정
├── PriorityOrder.swift            # 고정된 할 일을 맨 앞에
├── DecisionLog.swift              # UserAction 셋, SchedulerChoice 둘
├── NotchStatus.swift              # 상태 글자
├── CoreSettings.swift, Defaults.swift
├── Storage.swift                  # 긴급 전용 메서드(P7)
└── Sim/SimScenario·SimStorageRunner·SimOutput·SimStorageState
Sources/MokaStore/GRDBTaskRepository.swift  # 긴급 전용 메서드(P7)
tuning/tests/test_schema_contract.py
App/Sources/
├── AppState.swift                 # 흐름, 끝 시각 타이머, 수명, 질의 막기
├── Views/ExpandedView·CollapsedView·NotchContentView·NotchText
├── Views/PauseViews.swift         # 새: 길이 고르기, 멈춘 화면
├── Views/UrgentViews.swift        # 새: 긴급 입력, 복귀 제안
├── Views/BasicTabView.swift, Views/HelpContent.swift
Tests/MokaCoreTests/ NotchSessionPauseTests, NotchSessionUrgentTests, NotchModeTests, AutoStartTests, SchedulerPickTests, PriorityOrderTests, DayBudgetTests, SimGoldenTests, SimScenarioTests, ValueTypeTests
Tests/MokaStoreTests/ StorageContractTests
App/Tests/MokaAppTests/ AppPauseTests(새), AppUrgentTests(새), ScreenStateSnapshotTests, SettingsSnapshotTests, HelpContentTests
```

**Structure Decision**: ADR-0001 구조 그대로다. 새 타깃과 의존성은 없다. 규칙은 MokaCore에 두어 리눅스에서 시험한다. 뷰는 `AppState`를 모르게 값과 콜백만 받는다(ADR-0009).

### 앱 연결

- 활성화 순서: 켤 때 복구 → 멈춘 채 하루 경계 처리(data-model §4) → 반복 리셋 → 이월 판정 → 모드 → 고르기 → 판단 질의.
- 일시 중지는 `NotchSession`이 전이를 맡고 `AppState`는 입력 단계만 든다. 쓰기는 지금 `commit` 길을 그대로 쓴다.
- 끝 시각은 `updateRefreshTimer`의 1초 타이머로 본다. 조건을 일시 중지 상태로 넓히고, 길이가 끝나 기다리는 동안은 끄며, 끝 펼침은 한 번만 한다(P6).
- 일시 중지 중에는 `refreshGate`가 게이트를 열지 않고 끝날 때 다시 판정한다(P11).
- 멈춘 두 줄과 긴급 입력은 지금의 `pendingAction`·`notesDraft`와 따로 둔다. `pendingAction`은 도는 중이 아니면 닫히고(research F10), `notesDraft`는 `session.run`이 바뀌면 지워지기 때문이다(data-model §2).
- 단위 3·5는 화면 버튼을 만들지 않는다. 병합되어도 사용자가 보는 동작은 바뀌지 않고, 단위 4·6이 버튼을 연다.

## 작업 단위 (tasks.md의 뼈대, Issue 후보)

한 단위가 PR 하나이고 따로 검증한다.

| # | 단위 | R-ID | 승인 | 시안 확정 | 반영한 결정 | 앞선 단위 |
|---|---|---|---|---|---|---|
| 1 | 일시 중지 순수 로직과 `moka-sim`: 멈춤 상태, 전이, 남은 초·경과 분·돌려주기, 하루 경계, 모드, 자동 시작 조건, 로그 값 `pause`·`resume`, 시뮬레이터 이벤트·출력·불변식, 앱은 컴파일에 필요한 줄만 | R-801~R-807(로직), R-815(일부), R-831~R-834(일부), R-835 | 1·2·4·6·9 | 아니오 | P1·P3·P4·P8·P10 | 없음 |
| 2 | 긴급 순수 로직과 `moka-sim`: 긴급 입력, 한 번에 쓰기, 칩 상한과 늘리기, 고정, 복귀 띄움, 로그 값 `urgent`, 선택 규칙 이름 둘 | R-811~R-814(로직), R-815(일부), R-833, R-834(일부), R-835 | 2·3·4·7·8 | 아니오 | P2·P5·P7·P9 | 1 |
| 3 | 일시 중지 앱 연결(버튼 없음): 흐름, 끝 시각 타이머, 펼침과 활성화, 잠자기·종료·지우기, 질의 막기, 자동 시작, 설정 키, 도는 중 지우기 돌려주기(Red·Green 커밋을 따로) | R-803·R-804·R-806·R-807·R-808(저장)·R-832 | 5·9 | 아니오 | P4·P6·P11 | 1 |
| 4 | 일시 중지 화면: 버튼, 길이 고르기, 두 줄, 멈춘 펼친·접힌 화면, 끝난 뒤 기다림, 초안 복귀, 기본 탭 칸 | R-801·R-802·R-803·R-804·R-808(칸)·R-836 | 5 | 예(시안 1~7·11번) | P10·P11 | 3 |
| 5 | 긴급 앱 연결(버튼 없음): 제출 흐름, 입력 중 시간 끝, 고정과 순위 표시, 복귀 제안, 쓰기 실패 | R-811~R-814(앱) | 없음 | 아니오 | P9 | 2·3 |
| 6 | 긴급 화면: "+긴급", 입력, 두 줄, 늘리기 확인, 복귀 제안 | R-811·R-812·R-814·R-836 | 없음 | 예(시안 1·8~10번) | P2·P9 | 4·5 |
| 7 | 도움말 (1) 노치 문장 | R-837 | 없음 | 예(시안 12번) | 없음 | 4·6과 같은 시기에 병합 |

R-835(가짜만)와 R-836(해요체, 시안 뒤)은 모든 단위에 걸친다. R-838은 이 PR에서 끝냈다.

순서: 시안 `008-mockup.html` 확정 → 단위 1 → 단위 2 → 단위 3 → 단위 4 → 단위 5 → 단위 6 → 단위 7.

단위 7은 없는 버튼을 설명하지 않도록 단위 4와 6이 모두 병합될 수 있을 때 병합한다.

## 앞 spec 대조 (R-838 대체 표기는 이 PR에서 붙임)

| 앞 spec 줄 | 이 plan | 처리 |
|---|---|---|
| spec 001 R-005, Edge Case "잠자기" | 멈춘 동안 남은 초가 줄지 않음 | 표기(R-802·R-803·R-804·R-807) |
| spec 002 R-110, R-111 | 멈춘 동안 잠자기 체크포인트 없음, 멈춘 할 일도 대기로 | 표기(R-807) |
| spec 003 R-215 | 고정된 할 일이 맨 앞 | 표기(R-813) |
| spec 005 R-403·R-406·R-408·R-409·R-410·R-411·R-412·R-416·R-417·R-420·R-421·R-422·R-432·R-433 | 줄마다 바뀐 내용 | 표기 |
| spec 005 R-420, data-model §11 돌려주는 목록 | 도는 중 설정 창에서 지워도 남은 초를 돌려줌(P4, spec 005 동작 변경) | 표기(승인 항목 9) |
| spec 005 용어 "쓴 시간", Edge Case "자리를 비움" | 일시 중지 시간은 넣지 않음 | 표기(R-805) |
| spec 005 data-model §11·§12·§13·§17 | 돌려주기, 모드, 설정 키, 자동 시작 | 절 제목 아래 한 줄로 표기 |
| spec 007 R-703 | (1) 노치 설명에 한두 문장 | 표기(R-837) |

## 위험

spec "대안과 위험"의 번호를 따르고, plan에서 생긴 것은 9부터 붙인다.

- 위험 2(되돌리기 어려운 계약): 승인 항목 2·3·4는 쌓이면 지울 수 없다. 단위 1·2 PR "사람이 볼 결정"에 값마다 올린다.
- 위험 8(타이머 상태가 늘어남): case `paused`로 컴파일러가 대부분 잡지만 `default`와 `guard`로 지나가는 자리는 잡지 못한다. data-model §12의 시험 목록과 시뮬레이터 불변식으로 본다.
- 위험 9(고정의 앱 경로가 좁음, plan): 긴급 고정이 고르기에 쓰이는 길은 멈춘 긴급 할 일이 하루 경계로 대기가 된 경우뿐이다(research F12). 순수 함수 시험과 이 길의 시뮬레이터 시나리오로 본다.
- 위험 10(저장 경계, plan): `TaskRepository` 메서드를 더하면 시험 대역도 함께 고쳐야 한다(P7). 메모리와 GRDB 구현의 계약 시험으로 같은 결과를 본다.
- 위험 11(칩이 줄어듦, plan): 긴급 입력을 적는 동안 돌려받을 시간이 줄면 제출 때 칩이 고른 값보다 짧아진다(P9). 쓴 시간은 넘지 않지만, 칩이 줄어도 화면에 따로 알리지 않아 사용자가 고른 길이와 다르게 돌 수 있다.
- 위험 12(질의 실행기, plan): 멈춘 뒤에도 실행기가 다음 질의를 꺼내면 R-803을 어긴다(research F11). 단위 3에서 앱 시험으로 본다.
- 위험 13(시뮬레이터 밖 경우, plan): 이벤트가 하나라(P8) 돌아가기, 두 줄을 적는 동안 하루 경계, 입력 중 활성화는 golden으로 볼 수 없다. data-model §12의 단위 시험이 필수다.
- 위험 14(기록 해석, plan): 두 줄을 적는 동안 하루 경계를 넘기면 `pause`와 `day_end`가 나란히 남는다(P3). 튜닝에서 `pause` 줄을 실제로 멈춘 구간으로 읽으면 틀릴 수 있다.

## 다음 단계

1. (끝남) P1~P11을 토론 3:0으로 정하고 data-model·contracts·quickstart에 반영했다.
2. 시안 `008-mockup.html`의 M1~M19를 사람이 확정한다(M1은 게이트가 열린 동안의 두 안 가운데 하나를 고른다).
3. `tasks.md`를 만들고 Issue 큐로 옮긴다.
