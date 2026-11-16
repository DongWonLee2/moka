# Implementation Plan: 스케줄러 (마일스톤 4)

**Branch**: `chore/spec-005-plan` (구현은 Issue별 `feat/<issue>-<slug>`) | **Date**: 2026-11-16 | **Spec**: [spec.md](spec.md)

**Input**: `specs/005-scheduler/spec.md`(R-401~R-423, R-431~R-434. R-418 지움, R-424~R-430은 Issue #171), debate 기록 둘(저장소 밖 `.audit/debate/20261113-spec005-clarify.md`, `20261113-spec005-round2.md`), PRD 7장·9장, 기준 `origin/main` `67b526e`

## Summary

MokaCore에 스케줄러 순수 로직을 둔다: 후보 거르기(이월 답 대기 뺌), 앞 셋 가중 순환과 연속 상한·마무리 규칙(순수 함수만), aging에 이월 횟수, 아침 워밍업, 이월 판정과 이월 답, 가용 시간·쓴 시간·칩 상한·오늘 끝 판정, 노치 모드. 시간 규칙은 주입한 `MokaClock`·`Calendar`로 리눅스 `swift test`에서 시험한다. 스키마는 `tasks`에 `carry_count`·`due_decision`을 덧붙이는 마이그레이션 `v4_tasks_carry` 하나다. 행동 로그에 사용자 행동 값 셋과 선택 규칙 이름 셋을 더하고, `moka-sim`은 이월 답·가용 시간 답·"더 할래요" 이벤트와 출력 키를 받는다. 앱은 고르기를 새 규칙으로 바꾸고, 이월 카드·날짜 고르기·가용 시간 질문·오늘 끝 화면과 R-434 안내 글을 확정 시안 글자로 만든다. 규칙 원본은 [data-model.md](data-model.md), 결정 근거는 [research.md](research.md), 공개 계약은 [contracts/](contracts/)다.

## Technical Context

**Language/Version**: Swift 6(언어 모드 6, ADR-0001), Python 3(튜닝 계약 pytest)

**Primary Dependencies**: GRDB 7.11.1(기존). 새 의존성 없음

**Storage**: `tasks`에 열 둘(승인 항목 1). 이월 판정 시각, 오늘의 가용 시간 기록, 워밍업용 마지막 시작 하루, 자동 시작은 기존 `settings(key, value)` 표의 새 키(data-model §13). 새 표 없음

**Testing**: Swift Testing(`MokaCoreTests`, `MokaStoreTests`, 리눅스 CI `core-test`), XCTest `MokaAppTests`(macOS 로컬과 CI `app-snapshots`), pytest(`tuning-test`). 가짜 판단 공급자, `InMemory*` 저장소, 주입한 시계만 쓴다

**Target Platform**: macOS 14+ 메뉴 막대 앱(ADR-0005), Package는 리눅스에서도 빌드

**Project Type**: 데스크톱 앱 + Swift Package

**Performance Goals**: 노치 펼침·접힘 100ms(PRD FR-06). 고르기는 후보 앞 셋만 보므로 할 일 수에 선형. 이월 판정은 활성화 때 하루 한 번(전체 체크포인트·로그를 한 번 읽음)

**Constraints**: 실제 판단 API, Keychain, 앱 DB를 시험·CI·시뮬레이터에서 열지 않는다(R-431, 헌법 VIII). `eraseDatabaseOnSchemaChange` 금지(ADR-0004). `@unchecked Sendable` 금지. spec 001 타이머 golden 바이트 그대로. 앱에서 연속 상한·마무리 규칙이 동작한다고 보고하지 않는다(R-407, SC-402)

**Scale/Scope**: MokaCore 새 파일 아홉 남짓(`Scheduler/`), 고치는 파일 여섯(`ScoreRules`, `PriorityOrder`, `NotchSession`, `DecisionLog`, `Storage`, `QuantumChip`, `Defaults`, `CoreSettings`, 시뮬레이터 넷), MokaStore 둘(마이그레이션, 저장소), 앱 뷰 다섯 남짓(새 노치 화면 넷, 할 일 탭, 기본 탭, 접힌 노치)과 안내 글 상수 여섯 곳

## Constitution Check

*GATE: Phase 0 전 확인, Phase 1 설계 뒤 다시 확인함.*

spec 확인 질문 셋과 남은 결정 넷은 2026-11-13 debate와 사람 결정으로 정했다(spec 결정 이력). 이 plan에서 새로 생긴 갈림 여섯은 아래 "확정할 것"에 선택지로만 두었다. 그 밖은 에이전트 판단이며 research R7~R17과 PR "가정"에 있다.

| 원칙 | 판정 | 근거 |
|---|---|---|
| I 승인 없는 계약 변경 금지 | 통과(승인 항목 일곱, 아래 표) | 스키마, 로그 값, 선택 규칙 이름, 시뮬레이터 형식, 설정 키, `Defaults` 새 값, 저장 경계. 구현 PR "사람이 볼 결정"에 올리고 병합이 승인이다 |
| II 테스트 먼저, 약화 금지 | 통과 | 단위마다 Red 커밋 다음 Green 커밋. 고르기 규칙 교체로 바뀌는 기존 storage golden과 `ValueTypeTests` 단언은 약화가 아니라 규칙 교체·값 덧붙이기이고 PR에 바뀐 줄과 이유를 적는다 |
| III 네 가지로만 보고 | 통과 | quickstart. 실제 앱 하루 경계 확인은 사람이 하고, 하지 않으면 NOT_RUN |
| IV 같은 실패 2회 중단 | 통과 | 해당 시 handoff |
| V 작은 PR | 통과 | 작업 단위 여섯을 각각 PR로 |
| VI ID로 추적 | 통과 | 시험 표시 이름 `FR-05 R-40x`, `FR-08 R-41x`, `FR-10 R-42x`, 공통 `R-43x`(ADR-0003) |
| VII 보호 장치 우회 금지 | 통과 | 해당 없음 |
| VIII 판단 모델은 판단만 | 통과 | 이월 횟수·미룬 횟수는 판단 입력에 넣지 않는다(spec 003 R-201). 고르기는 코드가 점수로 한다 |
| 보안·사용자 데이터 | 통과 | 픽스처·시안은 가짜 할 일. 앱 DB 업그레이드 확인은 사람이 자기 기기에서 한다 |

설계 뒤 재확인: 위반 없음. Complexity Tracking 해당 없음.

### 승인 항목

| # | 항목 | 이 plan | 단위 | 계약 문서 |
|---|---|---|---|---|
| 1 | 스키마: `tasks.carry_count`, `tasks.due_decision`, 마이그레이션 `v4_tasks_carry`, `schema/moka-schema.sql`, pytest 계약 | data-model §2(칸 모양은 확정할 것 Q6) | 2 | [contracts/storage-values-005.md](contracts/storage-values-005.md) §1 |
| 2 | 행동 로그 사용자 행동 값 `carry_today`·`carry_drop`·`carry_move` | data-model §10·§16 | 1(열거형), 2(저장) | 같은 문서 §2 |
| 3 | 선택 규칙 이름 `weighted_rotate_v1`·`warmup_v1`·`carry_card_v1` | data-model §16 | 1 | 같은 문서 §3 |
| 4 | `moka-sim` 입력 이벤트 셋(`carry`, `budget`, `more`)과 출력 키, 새 불변식, 기존 storage golden 갱신 | 켜는 법은 확정할 것 Q3 | 1 | [contracts/moka-sim-v1-additions-005.md](contracts/moka-sim-v1-additions-005.md) |
| 5 | 설정 키 `auto_start`, `carry_judged_at`, `day_budget`, `last_start_day`(Q2-B면 `carry_reverted`) | data-model §13 | 2·4·6 | storage-values §5 |
| 6 | `Defaults.swift` 새 값 아홉(이월 가중 0.5, 워밍업 0.8·30분, 창 3, 순위 몫 5:3:2, 최소 몫 0.05, 연속 상한 2, 가용 시간 1·2·4·6·8, 자동 시작 3초) | data-model §14 | 1(로직 값), 4·6(화면 값) | 없음 |
| 7 | 모듈 경계: 이월 판정 원자 쓰기를 위한 `MokaCore`↔`MokaStore` 저장 프로토콜 변경 | 확정할 것 Q1 | 2 | data-model §9 |

바꾸지 않는 것: 의존성, CI, `Package.swift` 타깃, `questions.json`(워밍업 0.8은 `Defaults`, debate 3:0), `DecisionProvider`, `decisions_log`·`checkpoints`·`settings` 표 모양, 판단 입력.

| 바꿀 수 있었던 것 | 이 plan | 근거 |
|---|---|---|
| 오늘의 가용 시간·이월 판정 시각을 새 표로 | 설정 키 | spec 대안 표 "새 표(스키마 변경)" 기각 |
| `decisions_log.task_id` NULL 허용(가용 시간 답 로그) | 바꾸지 않음 | spec R-416, debate 2:1 |
| 할 일별 마지막 칩 값 `tasks.quantum_min` | 메모리 | spec 가정, Non-Goals |
| 새 `MokaScheduler` 타깃 | 두지 않음 | research R7 |

### 확정할 것 (메인 세션이 debate로 정함, 추천 없음)

| Q | 결정 | 선택지 | 막는 단위 |
|---|---|---|---|
| Q1 | 이월 표시와 판정 시각을 한 트랜잭션으로 쓰는 저장 경계(R-412, SC-406). R-119는 할 일 저장소가 없어 판정을 돌리지 않으므로 메모리 설정과 묶을 일은 없음 | A `StoreBatch`에 설정 덮어쓰기 칸 / B `TaskRepository`에 이월 판정 전용 읽기·쓰기 둘, 키는 저장소만 다룸 / C 두 저장소를 묶는 새 작업 단위 프로토콜 | 2 |
| Q2 | R-111이 되돌린 할 일을 같은 하루 안 재시작 뒤에도 손댄 할 일로 세는 저장 표시. 시간 끝 화면에서 정상 종료해도 빈틈이 생김(research Q2) | A 두지 않음(위험으로 적음) / B 설정 키 `carry_reverted`, 판정이 같은 트랜잭션에서 지움 / C 되돌릴 때 `quit` 체크포인트 한 줄 / D 시간 끝 정상 종료에도 `quit` 체크포인트(spec 002 규칙 넓힘) | 2 |
| Q3 | 시뮬레이터에서 이월·가용 시간을 켜는 법(R-432) | A `version: 2`만 / B storage 모드면 늘(기존 golden 다시 만듦) / C 새 이벤트가 있을 때만(spec 003 무늬) | 1 |
| Q4 | 쓴 시간을 세는 법(R-420, R-421, SC-405) | A 끝날 때 실제 초 / B 시작할 때 고른 분, 일찍 끝나면 돌려줌 / C 체크포인트·로그에서 셈(도는 중 완료 경과 새 저장) | 1(로직), 4(앱) |
| Q5 | 가중 순환 몫 셈 방식(R-403) | A 매끄러운 가중 순환 / B 뒤처진 후보 먼저(횟수 기반) / C 고정 순서 표 | 1 |
| Q6 | `due_decision` 칸 모양(승인 항목 1) | A `INTEGER` 0·1 / B `TEXT` 표시 시각 또는 NULL | 2 |

각 선택지의 대가는 research Q1~Q6에 있다. 답이 나오면 data-model·contracts·tasks의 해당 절을 고친다.

### 가정 (PR "가정")

- 이름: `SchedulerPick`, `PickInput`, `PickResult`, `CurrentTask`, `SchedulerMemory`, `RemainingEstimate`, `CarryJudgment`, `CarryJudgmentInput`, `CarryAnswer`, `CarryAnswerError`, `CarryCardReason`, `DayBudget`, `NotchMode`, `AutoStart`, `TomorrowMark`, `CarryText`, `BudgetText`.
- 설정 키 이름과 `day_budget` JSON 모양(data-model §11·§13).
- 오늘 끝과 겹친 시간 끝의 세 버튼 모두 `day_end`(research R11).
- 하루 경계를 넘는 작업 시간은 시작한 하루에만 셈(research R10).
- 카드 순서는 마감 순, 남은 개수는 지금 것 포함(research R13).
- 빠른 입력 초안의 로그 이름(research R12).
- `rotationMinWeight` 0.05는 에이전트 값(data-model §14).
- "내일" 표시는 진행 중 할 일을 쌓지 않음(data-model §18).

## Project Structure

### Documentation (this feature)

```text
specs/005-scheduler/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── moka-sim-v1-additions-005.md
│   └── storage-values-005.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/MokaCore/
├── Scheduler/SchedulerPick.swift      # 새: 가중 순환, 연속 상한, 마무리, 워밍업
├── Scheduler/SchedulerMemory.swift    # 새: 몫 상태, 최근 고르기, 칩 기억, pickedBy
├── Scheduler/RemainingEstimate.swift  # 새: 남은 예상 시간
├── Scheduler/CarryJudgment.swift      # 새: 판정 필요 여부, 대상
├── Scheduler/CarryAnswer.swift        # 새: 답 셋의 StoreBatch, 카드 순서와 까닭
├── Scheduler/DayBudget.swift          # 새: 가용 시간 기록, 남은 분, 쓴 시간 셈(Q4)
├── Scheduler/NotchMode.swift          # 새: 모드 우선순위(data-model §12)
├── Scheduler/AutoStart.swift          # 새(단위 6)
├── Scheduler/TomorrowMark.swift       # 새(단위 6)
├── Decision/ScoreRules.swift          # aging에 carryCount
├── PriorityOrder.swift                # 후보에서 dueDecision 뺌
├── OtherTask.swift                    # dueDecision 뺌
├── TaskModel.swift                    # carryCount, dueDecision
├── NotchSession.swift                 # SchedulerPick 호출, memory, 완료 때 표시 지움, day_end 계기
├── DecisionLog.swift                  # UserAction 셋, SchedulerChoice 셋
├── Storage.swift                      # 저장 경계(Q1), InMemory 구현
├── QuantumChip.swift                  # 칩 상한, aboveRemaining
├── NotchStatus.swift                  # 새 상태 글자
├── CoreSettings.swift                 # 설정 키
├── Defaults.swift                     # 새 값
└── Sim/SimScenario·SimStorageRunner·SimOutput·SimStorageState  # 이벤트 셋, 출력 키, 불변식
Sources/MokaStore/
├── Migrations.swift                   # v4_tasks_carry
└── GRDBTaskRepository.swift           # 두 열, 저장 경계(Q1)
schema/moka-schema.sql
tuning/tests/test_schema_contract.py
App/Sources/
├── AppState.swift                     # 활성화 순서, 판정·답, 가용 시간, 오늘 끝, 모드, 쓴 시간
├── Views/CarryCardView.swift          # 새: 이월 카드와 날짜 고르기
├── Views/BudgetViews.swift            # 새: 가용 시간 질문, 오늘 끝
├── Views/ExpandedView.swift·ExpiredView.swift·CollapsedView.swift·QuantumChipView.swift
├── Views/TaskListTabView.swift        # 이월 답 대기 상태, "내일"
├── Views/BasicTabView.swift           # 자동 시작, 하루 시작 안내
└── Views/HelpContent·GuideCardView·KeyFieldState·OnboardingView·DecisionField  # R-434 글
Tests/MokaCoreTests/ SchedulerPickTests, CarryJudgmentTests, CarryAnswerTests, DayBudgetTests, NotchModeTests, NotchSessionSchedulerTests, ScoreRulesTests, PriorityOrderTests, SimGoldenTests(새 golden), SimScenarioTests(오류 픽스처)
Tests/MokaStoreTests/ MigrationTests, StorageContractTests, StoreConstraintTests
App/Tests/MokaAppTests/ AppSchedulerTests(새), AppCarryTests(새), AppBudgetTests(새), ScreenStateSnapshotTests, SettingsSnapshotTests, HelpContentTests, GuideTests
```

**Structure Decision**: ADR-0001 구조 그대로다. 새 타깃과 의존성은 없다. 스케줄러 로직은 MokaCore `Scheduler/`에 두어 리눅스에서 시험한다. 뷰는 `AppState`를 모르게 값과 콜백만 받는다(ADR-0009). 저장 프로토콜 변경 모양은 Q1의 답을 따른다.

### 앱 연결

- 활성화 순서(data-model §15): R-111 → 반복 리셋 → 이월 판정 → 모드 → 고르기 → 판단 질의.
- `pickIfEmpty`는 모드를 먼저 본다. `.session`이고 빈 상태일 때만 `SchedulerPick`을 부른다. 바꾸기·미루기 뒤에는 방금 할 일을 `excluded`로 넘긴다.
- `AppState`의 모드 값(`notchMode`)을 뷰가 받아 펼친 화면·접힌 화면을 고른다. 이월 답·가용 시간 답·"더 할래요"는 `AppState` 함수 셋이고 쓰기 실패면 화면을 그대로 두고 해요체 한 줄을 보인다.
- 쓴 시간은 Q4의 답대로 버튼 커밋·시간 끝·종료에서 갱신한다. 시간 끝 `tick`이 `capActive && remainingMinutes < 1`을 보면 시간 끝 화면의 "N분 더"를 끈다.
- 단위 1이 `NotchSession` 고르기를 바꾸면 앱 노치 순서도 바뀐다. 단위 2가 `isWarmup`, `excluded`, `nextMarkID`를 앱 값으로 넘긴다.
- 단위 2는 판정·답 함수를 앱 시험으로만 부르고 활성화에 걸지 않는다(research R17). 단위 3이 카드 화면과 함께 건다.

## 작업 단위 (tasks.md의 뼈대, Issue 후보)

| # | 단위 | R-ID | 승인 | 시안 확정 | 앞선 단위 |
|---|---|---|---|---|---|
| 1 | 순수 스케줄러 로직과 `moka-sim`: 후보 거르기, 가중 순환·연속 상한·마무리·워밍업, aging, 남은 예상 시간, 이월 판정·답, 가용 시간·칩 상한·오늘 끝, 노치 모드, 로그 값 열거형, 시뮬레이터 이벤트·출력·불변식, 기존 storage golden 갱신 | R-401~R-409, R-411, R-412(로직), R-415·R-416(로직), R-419~R-422(로직), R-431, R-432 | 2·3·4·6 | 아니오 | Q3·Q4·Q5 |
| 2 | 스키마와 이월 판정 저장, 앱 고르기 연결: `v4_tasks_carry`, 스냅샷, pytest, 저장 경계, R-111 표시, 두 열 읽기·쓰기, 앱이 새 고르기·워밍업·aging·"다음" 표시를 씀, 판정·답 함수(활성화에는 아직 걸지 않음) | R-402·R-403·R-406·R-408(앱), R-412·R-413(저장), R-415·R-416(저장), R-434("다음" 표시), SC-406 | 1·2·5·7 | 아니오 | 1, Q1·Q2·Q6 |
| 3 | 이월 카드 화면: 카드, 날짜 고르기, 접힌 노치 표시, 할 일 탭 이월 답 대기, "다른 할 일"·순위에서 뺌, 활성화 연결, 진행 중 할 일 흐름 | R-412(앱), R-413, R-414, R-415, R-417, R-433 | 없음 | 예(005 시안 1~3·10-1·11번) | 2 |
| 4 | 가용 시간 질문과 오늘 끝: 질문, 쓴 시간, 칩 상한과 막는 문구, 오늘 끝, "더 할래요", 시간 끝 겹침과 `day_end` | R-409(앱), R-419~R-422, R-433 | 5·6 | 예(005 시안 4~9·10-2·10-3번) | 3 |
| 5 | R-434 안내 글: 도움말 3·6번, 안내 장 순위 장, 키 칸, 온보딩 키 단계, 판단 모델 칸 셋, 하루 시작 안내 | R-434 | 없음 | 예(005 시안 13번) | 1(병합은 1 가까이) |
| 6 | 자동 시작과 "내일" 표시(밀리면 먼저 뺌) | R-410, R-423 | 5·6 | 예(005 시안 11·12번) | 4 |

R-431(가짜만)과 R-433(해요체, 시안 뒤)은 모든 단위에 걸친다.

단위 1은 화면을 바꾸지 않지만, 앱도 `NotchSession`으로 고르므로 병합되면 앱 노치 순서가 가중 순환으로 바뀐다. 워밍업은 `isWarmup`을 넘기는 단위 2부터 앱에서 걸린다.

순서: Q3·Q4·Q5가 정해지면 단위 1, Q1·Q2·Q6이 정해지면 단위 2. 시안 `005-mockup.html` 확정 뒤 단위 3, 4. 단위 5는 시안 확정 뒤 바로 만들어 단위 1과 가깝게 병합한다(단위 1이 병합되면 노치가 가중 순환으로 바뀌어 지금 안내 글이 틀리므로). 단위 6은 마지막이다.

## 앞 spec 대조 (R-434 대체 표기는 이 PR에서 붙임)

| 앞 spec 줄 | 이 plan | 처리 |
|---|---|---|
| spec 002 R-104 "다른 할 일" 목록 | 이월 답 대기를 뺌 | 줄 끝에 "spec 005가 대체" 표기(R-413) |
| spec 003 R-204 aging | (미룬 횟수 + 0.5 × 이월 횟수) | 표기(R-402) |
| spec 003 R-209 고르기 | 가중 순환, 워밍업, 고르는 때 | 표기(R-403·R-406·R-408) |
| spec 003 R-212 선택 규칙 이름 | 새 이름 셋 | 표기(R-411) |
| spec 003 R-215 순위·"다음" | 이월 답 대기 뺌, "다음"은 다음 고르기 결과 | 표기(R-413·R-434) |
| spec 004 R-315 키 없으면 마감일 순 | 마감일 순 앞 셋을 번갈아 | 표기(R-403) |
| spec 007 도움말 3·6번, 안내 장 순위 장 | 시안 13번 글로 바꿈 | 표기(R-434) |

## 위험

spec "대안과 위험"의 번호를 따르고, plan에서 생긴 것을 더한다.

- 위험 2(되돌리기 어려운 계약): 승인 항목 1~5는 쌓이면 지울 수 없다. 단위 1·2 PR "사람이 볼 결정"에 값마다 올린다.
- 위험 5(기존 기대 출력): 기존 storage golden 일곱의 `notch_task`·`scheduler_choice`가 바뀐다. 단위 1 PR에 바뀐 줄 표를 붙인다.
- 위험 8(앱 경로 없는 규칙): R-404·R-405는 `SchedulerPickTests`로만 시험한다.
- 위험 11(안내 글 공백, plan): 단위 1과 5 사이에는 앱이 가중 순환으로 고르는데 안내 글은 "마감이 가까운 순으로 떠요"다. 단위 5를 시안 확정 직후 만들어 그 사이를 줄인다.
- 위험 12(판정 없는 표시, plan): 단위 2만 병합된 앱에서 판정이 활성화에 걸리면 이월 답 대기 할 일이 화면 없이 숨는다. 그래서 단위 2는 판정을 걸지 않고, 단위 3 시험이 "카드 없이 숨은 할 일 0건"(SC-403)을 확인한다.
- 위험 13(업그레이드, plan): 기존 앱 DB에 `v4_tasks_carry`가 돈다. 메모리 DB 시험과 v3 DB 사본 업그레이드 시험(`MigrationTests`)으로 보고, 실제 기기 업그레이드는 사람이 확인한다(quickstart 6-1).
- 위험 14(Q2 빈틈): Q2-A를 고르면 시간 끝 화면에서 정상 종료한 뒤 같은 날 다시 켠 할 일이 다음 날 카드에 오르지 않을 수 있다.

## 다음 단계

1. 메인 세션이 확정할 것 Q1~Q6을 debate로 정하고 data-model·contracts·tasks를 고친다.
2. 시안 `005-mockup.html` 사람 확정.
3. 이 PR 병합 뒤 Issue 큐(단위 1, 2, 3, 4와 5, 6).
