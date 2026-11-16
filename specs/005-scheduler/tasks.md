---

description: "spec 005 스케줄러 작업 목록"
---

# Tasks: 스케줄러 (마일스톤 4)

**Input**: `specs/005-scheduler/`의 plan.md, spec.md(R-401~R-423, R-431~R-434), research.md(Q1~Q6, R7~R17), data-model.md(§1~§19), contracts/(moka-sim-v1-additions-005.md, storage-values-005.md), quickstart.md. 화면 시안 `~/Dev/ai-platform/projects/moka/design/005-mockup.html`(저장소 밖, T003에서 사람 확정)

**Tests**: 넣는다. 헌법 II와 AGENTS.md "실패하는 테스트를 먼저 쓰고 실패를 확인한 뒤 구현한다". 테스트 태스크마다 Red 커밋을 남기고, 구현 태스크에서 Green 커밋을 남긴다.

**Organization**: plan "작업 단위" 여섯 순서로 묶는다. 각 태스크 끝의 `〔단위 N〕`은 Issue 하나가 된다. 사용자 이야기는 US1(가중 순환), US2(이월 카드), US3(가용 시간)이다.

**원본 규칙**: 규칙, 값, 모양은 data-model.md와 contracts/가 원본이다. 태스크는 절 번호를 가리키고 문장을 옮겨 적지 않는다. 시험은 그 절의 규칙을 빠짐없이 덮는다.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 다른 파일을 고치고 아직 안 끝난 태스크에 기대지 않아 병렬로 할 수 있다
- **[Story]**: US1~US3(spec.md)
- **[사람]**: 화면 확정이나 실제 앱 확인을 사람이 해야 끝난다
- **[화면 뒤]**: T003(시안 확정) 뒤에만 시작한다
- **[승인 N]**: plan "승인 항목" N번. 그 단위 PR "사람이 볼 결정"에 올리고 병합이 승인이다

## 공통 규칙 (모든 태스크)

- 테스트 표시 이름은 R-ID로 시작한다(ADR-0003): 스케줄러 `FR-05 R-40x`, 이월 `FR-08 R-41x`, 가용 시간 `FR-10 R-42x`, 공통 `R-43x`. MokaCore·MokaStore는 Swift Testing, 앱 시험 번들은 XCTest.
- 시간 규칙은 주입한 `MokaClock`과 `GregorianCalendar.make(timeZone:)`으로 시험한다. 실제 시간을 기다리지 않는다. 하루 경계는 05:59·06:00·며칠 건너뜀·뉴욕 시간대(`storage-us4-newyork` 무늬)를 덮는다.
- 실제 판단 API, Keychain, 앱 DB를 시험·CI·`moka-sim`에서 열지 않는다. `FakeDecisionProvider`, `InMemoryKeyStore`, `InMemory*` 저장소, 시뮬레이터 `judge`만 쓴다. 가짜 할 일만 쓴다(예: "가짜 할 일 A").
- 기존 시험의 기대값을 바꿔야 통과하면 멈추고 원인을 본다. 예외는 둘이고 PR에 바뀐 줄과 이유를 적는다: 고르기 규칙 교체로 바뀌는 기존 storage golden(spec 위험 5), 값을 덧붙인 `ValueTypeTests`의 `allCases`.
- 앱에서 연속 상한(R-404)과 마무리 규칙(R-405)이 동작한다고 보고하지 않는다(SC-402, 위험 8).
- `@unchecked Sendable`과 경고 억제를 쓰지 않는다. `Package.swift`, CI, 의존성은 바꾸지 않는다.
- 화면 문구는 고객용 해요체이고 확정 시안 글자를 그대로 쓴다. 값을 끼워 넣는 글자는 MokaCore, 고정 글자는 뷰 상수(data-model §19).
- 검증 명령: `swift test`, `cd tuning && python3 -m pytest`, 앱 빌드와 앱 시험(quickstart 4). 결과는 PASS/FAIL/SKIP/NOT_RUN.

---

## Phase 1: Setup

- [ ] T001 기준 상태 확인: `swift test`, `cd tuning && python3 -m pytest`, 앱 빌드, quickstart 4의 앱 시험을 돌려 기존 시험이 PASS인지 기록한다. 기존 storage golden 일곱의 파일 해시와 스냅샷 참조 이미지 해시 목록을 PR "완료 증거"에 적는다(위험 5 비교 기준) 〔단위 1〕
- [x] T002 [사람] 메인 세션이 plan "확정할 것" Q1~Q6을 debate로 정하고(2026-11-16, Q1-B, Q2-A, Q3-C, Q4-B, Q5-A, Q6-A), data-model §2·§5·§9·§11·§13과 contracts 둘, plan, research의 선택지 문단을 하나로 고친다. Q2-D는 Issue #173 〔단위 1〕
- [ ] T003 [사람] 시안 `005-mockup.html`을 사용자에게 보이고 "확정할 것" 열둘을 확정받는다. 확정 전에는 [화면 뒤] 태스크를 시작하지 않는다 〔단위 3〕

---

## Phase 2: 단위 1 — 순수 스케줄러 로직과 `moka-sim` (US1 바탕) [승인 2·3·4·6]

**목적**: 리눅스 `swift test`만으로 spec 규칙 전부를 재현한다. `MokaTask`에 두 값을 더하되 GRDB 읽기·쓰기는 단위 2다. 앱 화면은 바꾸지 않는다. 다만 앱도 `NotchSession`으로 고르므로 이 단위가 병합되면 앱 노치 순서가 가중 순환으로 바뀐다(워밍업은 `isWarmup`을 넘기는 단위 2부터, 이월 판정과 가용 시간은 앱에서 아직 돌지 않음).

- [ ] T004 [P] `Tests/MokaCoreTests/ValueTypeTests.swift`: `UserAction.allCases`와 `SchedulerChoice.allCases` 끝에 새 값 셋씩(data-model §16), `MokaTask`의 `carryCount` 0과 `dueDecision` 거짓 처음 값. 컴파일 실패를 확인한다(`FR-11 R-411`, `FR-08 R-416`) 〔단위 1〕
- [ ] T005 `Sources/MokaCore/DecisionLog.swift` 값 셋씩, `Sources/MokaCore/TaskModel.swift` 두 값(data-model §1), `Sources/MokaCore/Defaults.swift` 새 값(§14). T004 PASS, 기존 시험 PASS 〔단위 1〕
- [ ] T006 [P] `Tests/MokaCoreTests/ScoreRulesTests.swift`: data-model §3 aging 식(미룬 1 → 1, 오늘 할래요 1 → 0.5, avoiding 배율, 둘이 섞임), 판단 입력 해시가 `carryCount`와 상관없음. `PriorityOrderTests.swift`: §4 후보에서 이월 답 대기 뺌, `OtherTaskTests.swift`: "다른 할 일"에서 뺌. 실패를 확인한다(`FR-05 R-402`, `FR-05 R-401`, `FR-08 R-413`) 〔단위 1〕
- [ ] T007 `Sources/MokaCore/Decision/ScoreRules.swift`, `Sources/MokaCore/PriorityOrder.swift`, `Sources/MokaCore/OtherTask.swift`. T006 PASS 〔단위 1〕
- [ ] T008 [P] [US1] `Tests/MokaCoreTests/SchedulerPickTests.swift`: data-model §5 판정 순서 다섯과 §5-4 공통 성질 넷(SC-401 100번 50·30·20 ±2와 4위 0번, 같은 입력 같은 결과), 순위 몫(점수 없는 할 일 섞임, 모두 점수 없음), 후보 둘·하나, priority 0 최소 몫, 창 규칙(data-model §5-4: 창은 `order` 앞 셋을 먼저 정함, `excluded`·연속 상한 후보는 그 고르기에서만 건너뛰고 몫을 버리지 않음, 넷째 후보는 `excluded`가 있어도 0번, 창에서 실제로 빠진 후보의 몫만 버림, 새로 든 후보는 0에서 시작, 몫은 `Int`), `excluded`(후보 하나면 예외), 연속 상한(순수 함수만, 상한 때문에 비면 무시), 메인 세션 시뮬레이션의 특정 사례 하나(몫 5:3:2 창에서 0부터 10번 고른 뒤 급한 새 할 일이 1위 몫 5로 들면 바로 다음 차례에 뽑히고 이어지는 10번 중 5번. 일반 성질로 시험하지 않음, data-model §5-4 반례), 마무리 규칙이 연속 상한보다 앞섬·`estMin` 없으면 없음·남은 시간 0 이하, 워밍업(§6 후보 조건, 없으면 가중 순환, 이름 둘), `memoryDay`가 바뀌면 몫 상태 비움. `RemainingEstimate` 시험. 실패를 확인한다(`FR-05 R-403`, `R-404`, `R-405`, `R-406`, SC-401, SC-402) 〔단위 1〕
- [ ] T009 [US1] `Sources/MokaCore/Scheduler/SchedulerPick.swift`, `SchedulerMemory.swift`, `RemainingEstimate.swift`(매끄러운 가중 순환, 정수 몫). T008 PASS 〔단위 1〕
- [ ] T010 [P] [US2] `Tests/MokaCoreTests/CarryJudgmentTests.swift`: data-model §9 `needsRun`·구간 시작·대상 규칙 전부, spec US2 시나리오 1·5·6·6a·6b·6d·9, 이월 답 로그 줄 뺌, 체크포인트 계기 상관없음, 이미 대기인 표시 유지, 여러 번 돌려도 같음, 05:59·06:00, 며칠 건너뜀, 반복 할 일 제외, 같은 초 경계(지난 판정 시각과 같은 초의 체크포인트·로그 줄은 손댄 것으로 셈, `createdAt >= since`를 초로 내림해 비교), `revertedIDs`가 손댄 할 일로 들어감. `CarryAnswerTests.swift`: §10 답 셋의 갱신과 로그 줄(판단 칸 있음·`fallback`), 날짜 오류, 진행 중 할 일에 답 거부, 카드 순서와 까닭. 실패를 확인한다(`FR-08 R-412`, `R-415`, `R-416`, `R-417`, SC-403, SC-404) 〔단위 1〕
- [ ] T011 [US2] `Sources/MokaCore/Scheduler/CarryJudgment.swift`, `CarryAnswer.swift`. T010 PASS 〔단위 1〕
- [ ] T012 [P] [US3] `Tests/MokaCoreTests/DayBudgetTests.swift`: data-model §11 기록 읽기(어제 기록 무시), 남은 분 내림, 칩 처음 값 순서(시작 전·시간 끝), 프리셋 꺼짐, `aboveRemaining`, 쓴 시간 셈(data-model §11: 시작·"N분 더" 때 고른 분 × 60을 더함, 도는 중 완료·미루기·바꾸기·종료 때 남은 초를 돌려줌, 잠자기는 돌려주지 않음, 시간 끝까지 가면 돌려줄 것 없음), 하루 경계를 넘는 작업 시간과 그 뒤 "N분 더"가 처음 시작한 하루(`budgetDay`)에 들어감과 그 "N분 더" 칩이 시작한 하루의 남은 분 이하·0이면 꺼짐·시작한 하루에 기록이 없거나 "더 할래요"면 상한 없음(research R10, data-model §11), `capActive`인 동안 `usedSeconds ≤ hours × 3600`이고 돌려받은 시간으로 다시 시작하면 시작한 분 합은 그보다 클 수 있음(data-model §11 예). `NotchModeTests.swift`: §12 표 여섯 줄과 초안 비움, 시간 끝 겹침의 "N분 더" 꺼짐. `QuantumChipTests.swift`에 상한 경우. 실패를 확인한다(`FR-10 R-409`, `R-419`, `R-420`, `R-421`, `R-422`) 〔단위 1〕
- [ ] T013 [US3] `Sources/MokaCore/Scheduler/DayBudget.swift`, `NotchMode.swift`, `Sources/MokaCore/QuantumChip.swift`(상한과 `aboveRemaining`, 글자는 T003 전까지 시안 초안 글자로 두고 단위 4에서 확정 글자로 맞춤). T012 PASS 〔단위 1〕
- [ ] T014 [P] [US1] [US2] [US3] `Tests/MokaCoreTests/NotchSessionSchedulerTests.swift`: `NotchSession`이 `SchedulerPick`으로 고르고 `pickedBy`를 로그 줄에 씀(가중 순환, 워밍업, "다른 할 일"은 이름 유지, 빠른 입력 초안, research R12), 바꾸기·미루기 뒤 `excluded`, 완료가 `dueDecision`을 지움, 오늘 끝과 겹친 시간 끝의 세 버튼 계기 `day_end`(research R11), 가용 2시간에서 "더 할래요" 전 쓴 시간(`usedSeconds`) 120분 이하·시작 칩은 남은 분 이하·쓴 시간이 120분이면 고르기 없음(SC-405), 버튼 처리 순서(커밋 → 남은 초 돌려주기 → 모드 판정 → 모드 6일 때만 고르기, data-model §12): 60분 작업 시간을 10분에 완료하면 오늘 끝이 아니라 고르기가 돌고 다음 칩이 남은 분 이하, 하루 경계 뒤 "N분 더"는 `last_start_day`를 쓰지 않아 다음 첫 고르기가 워밍업이고 전날 기록의 쓴 시간이 그 전날 가용 시간을 넘지 않음(전날 남은 분 0이면 "N분 더" 꺼짐과 계기 `day_end`, 버튼 뒤 새 하루 모드)(research R10), "N분 더"는 `recentPicks`를 바꾸지 않음, `nextMark`(research R15). 기존 `NotchSessionTests`·`NotchSessionPriorityTests`의 `priority_rotate_v0` 기대는 새 이름으로 바꾸고 PR에 적는다. 실패를 확인한다(`FR-05 R-403`, `R-406`, `R-408`, `R-411`, `FR-10 R-422`) 〔단위 1〕
- [ ] T015 [US1] `Sources/MokaCore/NotchSession.swift`(memory 칸, 고르기 교체, 완료 때 표시 지움, `day_end` 계기, `nextMark`). `PriorityRotateRule`은 남기고 호출만 바꾼다. T014 PASS 〔단위 1〕
- [ ] T016 [P] 시뮬레이터 Red: `Tests/MokaCoreTests/Fixtures/sim/`에 새 golden 다섯(`storage-005-rotate`, `storage-005-warmup`, `storage-005-carry`(contracts 예, 새 이벤트가 있어 켜짐), `storage-005-budget`(오늘 끝과 "더 할래요", 시간 끝 겹침), `storage-005-boundary-running`(하루 경계에 도는 할 일, spec 6b·6c, 첫날 `budget` 이벤트가 있어 켜짐))과 기대 출력. `boundary-running`은 계약 "새 불변식"의 손 확인 순서대로 각 줄의 `timer_state`·`due`·`notch_task`가 불변식(빈 상태일 때만 `due` 할 일이 노치에 없음)을 지키는지 기대 출력을 쓰기 전에 손으로 따라가 PR에 적는다. `errors/`에 contracts "종료 코드 2" 경우마다 하나와 불변식 위반 경우, `SimGoldenTests` 필수 이름 집합과 `SimScenarioTests` 표. 기존 storage golden 일곱의 기대 출력을 새 규칙으로 다시 쓰고 바뀐 줄 표를 만든다. 실패를 확인한다(`R-432`, SC-402~SC-406) 〔단위 1〕
- [ ] T017 `Sources/MokaCore/Sim/SimScenario.swift`(이벤트 셋, 새 이벤트가 있을 때만 켬), `SimStorageRunner.swift`(활성화 순서 data-model §15, 이월 답·가용 시간·"더 할래요", 설정 메모리), `SimOutput.swift`(키 순서), `SimStorageState.swift`(불변식). T016 PASS, spec 001 golden 바이트 그대로 〔단위 1〕

- [ ] T043 [P] [US1] `App/Tests/MokaAppTests/AppSchedulerTests.swift`(새, 단위 2 T022가 이어 씀): 키 없음에서 가짜 할 일 넷(마감 순 A·B·C·D)으로 바꾸기·미루기를 이어 누르면 A·B·C가 순위 몫 5:3:2에 가깝게 뜨고 D는 0번, 바꾸기·미루기 바로 뒤에 방금 할 일이 다시 뜨지 않음(R-408, `previousTaskID` → `excluded`, plan "앱 연결"), 완료 뒤에는 뺄 할 일 없음. 앱 코드는 바꾸지 않고 시험만 더한다(단위 1이 `NotchSession`을 바꿔 앱 순서가 바뀌는 것을 확인). 먼저 T015 전 상태에서 실패를 확인한다(`FR-05 R-403`, `R-408`) 〔단위 1〕
- [ ] T044 [P] GLOSSARY 새 용어(Issue #174 둘째 항목)를 단위 1 PR 전에 별도 PR로 내거나 단위 1 PR에 함께 넣는다 〔단위 1〕

**확인 지점**: `swift test` PASS(새 시험, 기존 시험, 바뀐 storage golden), pytest PASS. 앱 빌드 PASS, 기존 앱 시험 PASS(고르기 순서를 1위·다음 순위로 고정한 앱 시험이 있으면 새 규칙 기대로 고치고 PR에 적는다). PR "사람이 볼 결정"에 승인 2·3·4·6과 바뀐 golden 줄 표.

---

## Phase 3: 단위 2 — 스키마와 이월 판정 저장, 앱 고르기 연결 (US1) [승인 1·2·5·7]

**목적**: 두 열을 저장하고, 이월 판정을 한 트랜잭션으로 쓰는 경계를 만들고, 앱 노치를 새 고르기로 바꾼다. 이월 판정은 활성화에 아직 걸지 않는다(plan 위험 12).

- [ ] T018 [P] `Tests/MokaStoreTests/MigrationTests.swift`: 이름 목록 끝 `v4_tasks_carry`, 스냅샷 비교(새 `schema/moka-schema.sql`), v3까지 마이그레이션한 DB에 가짜 할 일을 넣고 v4를 돌리면 두 값이 처음 값. `StorageContractTests.swift`·`StoreConstraintTests.swift`: 두 열 읽기·쓰기, `carry_count < 0` 거부, `carry_*`·`carry_card_v1` 줄 왕복과 모르는 값 거부. `tuning/tests/test_schema_contract.py`: contracts storage-values §1~§3. 실패를 확인한다(`FR-08 R-412`, `R-416`, ADR-0004) 〔단위 2〕
- [ ] T019 `Sources/MokaStore/Migrations.swift`(`v4_tasks_carry`, 기존 마이그레이션처럼 SQL을 줄바꿈 없는 한 문자열로 써서 `sqlite_master` 글자가 스냅샷과 맞게), `Sources/MokaStore/GRDBTaskRepository.swift`(두 열), `schema/moka-schema.sql`(시험 출력 그대로). T018 PASS, pytest PASS 〔단위 2〕
- [ ] T020 [P] `Tests/MokaStoreTests/StorageContractTests.swift`와 `Tests/MokaCoreTests/` 메모리 구현 시험: `TaskRepository.applyCarryJudgment(_:judgedAt:)`가 표시 여럿과 `carry_judged_at`을 한 트랜잭션으로 씀, 중간 실패를 주입하면 표시와 판정 시각이 둘 다 없음, `lastCarryJudgment()`가 다음 판정의 이전 판정 시각을 돌려줌(SC-406). 경계 시험(data-model §9): `GRDBSettingsStore`·`InMemorySettingsStore`가 `carry_judged_at` 읽기·쓰기를 `StoreError.invalidValue(column: "key")`로 거부하고 아무것도 쓰지 않음, `CoreSettings`에 이 키 상수가 없음, 소스에서 이 키 글자가 두 `TaskRepository` 구현 밖에 없음. R-111 표시는 저장하지 않는다(Q2-A). 메모리 구현과 GRDB 구현이 같은 시험을 통과. 실패를 확인한다(`FR-08 R-412`, SC-406) 〔단위 2〕
- [ ] T021 `Sources/MokaCore/Storage.swift`, `Sources/MokaStore/GRDBTaskRepository.swift`(이월 판정 읽기·쓰기), `Sources/MokaStore/GRDBSettingsStore.swift`와 `InMemorySettingsStore`(키 거부), `Sources/MokaCore/CoreSettings.swift`(키 `last_start_day`), `Sources/MokaCore/Sim/SimStorageRunner.swift`가 같은 경계를 씀. T020 PASS 〔단위 2〕
- [ ] T022 [P] [US1] `App/Tests/MokaAppTests/AppSchedulerTests.swift`(새): 키 없음에서 마감일 순 앞 셋을 번갈아 띄움(spec US1-7), 점수 있는 할 일 셋이면 priority 비(US1-1, 가깝다), 하루 첫 고르기 워밍업과 같은 하루 재시작 뒤 워밍업 없음(`last_start_day`), 시간 끝 화면 버튼 그대로이고 다른 할 일이 보이지 않음(US1-8), 버튼 줄 `scheduler_choice`, "다음" 표시(`nextMarkID`)가 다음 고르기 결과, 순위는 이월 답 대기 뺌. `AppTestSupport.swift`에 주입 시계로 하루를 넘기는 도움 함수. 이월 판정·답 `AppState` 함수(`judgeCarryIfNeeded`, `answerCarry`)를 직접 불러 저장 결과를 봄(활성화 연결은 단위 3). 실패를 확인한다(`FR-05 R-403`, `R-406`, `R-407`, `R-408`, `R-434`) 〔단위 2〕
- [ ] T023 [US1] `App/Sources/AppState.swift`: `input(at:)`에 memory, `pickIfEmpty`는 지금처럼 `session.picked`만 부름(바꾸기·미루기 뒤 방금 할 일은 단위 1부터 `NotchSession`이 `previousTaskID`를 `excluded`로 넘겨 이미 뺌, plan "앱 연결"), 시작 커밋에 `last_start_day`, `ranks`·`nextMarkID`, 판정·답 함수(활성화에서 부르지 않음). T022 PASS, 앱 빌드 PASS, 기존 앱 시험 PASS 〔단위 2〕
- [ ] T024 [P] 대체 표기 확인: 이 plan PR에서 붙인 "spec 005가 대체" 표기(spec 002 R-104, spec 003 R-204·R-209·R-212·R-215, spec 004 R-315, spec 007 도움말 3·6번과 안내 장 순위 장)가 구현과 맞는지 보고, 다르면 고친다(`R-434`) 〔단위 2〕
- [ ] T025 [사람] [US1] quickstart 6-1 〔단위 2〕

**확인 지점**: US1 시나리오 1~8(1·7은 앱 시험, 2·3·4는 순수 함수, 5·6은 저장 포함). 이월 답 대기 할 일은 아직 생기지 않는다.

---

## Phase 4: 단위 3 — 이월 카드 화면 (US2) [화면 뒤]

**Goal**: 하루가 바뀐 뒤 활성화하면 이월 대상이 카드로 뜨고, 답하기 전에는 어디에도 고를 할 일로 나오지 않는다.

**Independent Test**: 주입 시계로 하루를 넘긴 앱 시험과 시안 1~3·10-1·11번 스냅샷.

- [ ] T026 [P] [US2] `App/Tests/MokaAppTests/AppCarryTests.swift`(새): spec US2 시나리오 1~10 전부(1 카드에 A·B만, 2~4 답 셋, 5·6·6a 다음 판정, 6b·6c 하루 경계에 진행 중, 6d R-111 뒤 판정, `revertedIDs`를 판정 쓰기가 성공할 때까지 메모리에 들고 있음(판정 쓰기를 실패시킨 뒤 다음 활성화의 재판정에도 들어감, 같은 하루 재시작 뒤 앱을 끄지 않고 하루를 넘기면 그 판정에 들어감, data-model §9), 7 고르지 않음, 8 재시작 뒤 같은 할 일부터, 9 반복 리셋, 10 로그 한 줄), 활성화 넷(시작, 깨어남, 노치 펼침, 설정 창)에서 판정, 초안이 표시를 받으면 비우고 카드, "다른 할 일"·순위·"다음"에 이월 대상 0건, 카드 없이 대기로 돌아온 건수 0(SC-403), 앱 DB를 열 수 없으면 카드 없음(R-119), 답 쓰기 실패면 카드 그대로와 해요체 한 줄. 실패를 확인한다(`FR-08 R-412`~`R-417`, SC-403, SC-404) 〔단위 3〕
- [ ] T027 [US2] `App/Sources/AppState.swift`: `launch()`·`activate()`에 판정(data-model §15), `notchMode`, 초안 비우기, 카드 답·날짜 고르기 상태. T026 PASS 〔단위 3〕
- [ ] T028 [P] [US2] [화면 뒤] `App/Tests/MokaAppTests/ScreenStateSnapshotTests.swift`·`SettingsSnapshotTests.swift`: data-model §19의 `test_R414_carryCardTouched`, `test_R414_carryCardOverdueLast`, `test_R415_datePicker`, `test_R414_collapsedCarry`, `test_R413_taskTabDue` 라이트·다크를 확정 시안대로 쓰고 실패를 확인한다. 순위가 바뀌는 기존 할 일 탭 참조 이미지 목록을 PR에 적는다(`FR-08 R-413`, `R-414`, `R-415`, `R-433`) 〔단위 3〕
- [ ] T029 [US2] [화면 뒤] `App/Sources/Views/CarryCardView.swift`(새, 카드와 날짜 고르기, Enter·esc), `ExpandedView.swift`·`CollapsedView.swift`(모드 분기), `TaskListTabView.swift`(이월 답 대기 상태 글자), `Sources/MokaCore/NotchStatus.swift`·`CarryText`(시안 확정 글자). T028 PASS 〔단위 3〕
- [ ] T030 [사람] [US2] quickstart 6-2, 6-3. 비교 페이지 `design/pr-<번호>/index.html` 〔단위 3〕

**확인 지점**: US2 시나리오 1~10, SC-403, SC-404.

---

## Phase 5: 단위 4 — 가용 시간 질문과 오늘 끝 (US3) [화면 뒤] [승인 5·6]

**Goal**: 그날 고른 시간 안에서만 작업 시간을 배정하고, 다 쓰면 "오늘 끝"과 "더 할래요"만 보인다.

**Independent Test**: 주입 시계로 작업 시간을 이어 돌리는 앱 시험과 시안 4~9·10-2·10-3번 스냅샷.

- [ ] T031 [P] [US3] `App/Tests/MokaAppTests/AppBudgetTests.swift`(새): spec US3 시나리오 1~6(7은 단위 6), 질문 전 빠른 입력은 저장만, 질문 답 쓰기 실패면 질문 그대로, 같은 하루 재시작에 다시 묻지 않고 쓴 시간 이어 셈, 도는 중 일찍 끝내면 남은 초를 돌려받음, 버튼 처리 순서(커밋 → 돌려주기 → 모드 판정 → 고르기)로 일찍 끝낸 작업 시간 뒤 오늘 끝이 잘못 뜨지 않음, 칩 상한과 프리셋 꺼짐, 직접 입력이 남은 분보다 크면 시작 꺼짐, 시간 끝 겹침에서 "N분 더"·직접 입력 Enter 막음과 세 버튼 계기 `day_end`, 그 뒤 고르기 0번(SC-405), "더 할래요" 뒤 그날 상한 없음, 오늘 끝에서 재시작해도 오늘 끝, 일시 중지가 없어 도는 타이머 시간은 쓴 시간에 듦·시간 끝 화면에서 기다린 시간은 들지 않음(spec Edge Cases). 실패를 확인한다(`FR-10 R-409`, `R-419`~`R-422`, SC-405, SC-406) 〔단위 4〕
- [ ] T032 [US3] `App/Sources/AppState.swift`: 가용 시간 답, `day_budget` 쓰기, 쓴 시간 갱신(시작 때 더함, 일찍 끝나면 돌려줌), 모드 판정을 고르기 앞에, "더 할래요". `Sources/MokaCore/CoreSettings.swift` 키 `day_budget`. T031 PASS 〔단위 4〕
- [ ] T033 [P] [US3] [화면 뒤] 스냅샷: `test_R419_askBudget`, `test_R421_draftCapped`, `test_R421_customAboveRemaining`, `test_R409_expiredCapped`, `test_R422_expiredDayEnd`, `test_R422_dayEnd`, `test_R419_collapsedAskBudget`, `test_R422_collapsedDayEnd` 라이트·다크. 기존 시간 끝 화면 참조 이미지는 바뀌지 않아야 한다. 실패를 확인한다(`FR-10 R-419`, `R-421`, `R-422`, `R-433`) 〔단위 4〕
- [ ] T034 [US3] [화면 뒤] `App/Sources/Views/BudgetViews.swift`(새, 질문과 오늘 끝), `ExpiredView.swift`(꺼진 "N분 더"와 이유 한 줄), `QuantumChipView.swift`(꺼진 프리셋), `CollapsedView.swift`, `Sources/MokaCore/QuantumChip.swift`·`BudgetText`(시안 확정 글자). T033 PASS 〔단위 4〕
- [ ] T035 [사람] [US3] quickstart 6-4, 6-5(실제 타이머 1시간. 못 하면 NOT_RUN) 〔단위 4〕

**확인 지점**: US3 시나리오 1~6, SC-405, SC-406.

---

## Phase 6: 단위 5 — R-434 안내 글 [화면 뒤]

- [ ] T036 [P] [화면 뒤] `App/Tests/MokaAppTests/HelpContentTests.swift`·`GuideTests.swift`·`OnboardingKeyStepTests.swift`·`DecisionFieldTextTests.swift`: 확정 시안 13번 오른쪽 글자 여덟 줄, 도움말 3번 문장 수 2~5와 따옴표 안 글자가 화면 상수에 있음(spec 007 R-705). 바뀌는 스냅샷(도움말 3·6번 펼침, 안내 장 순위 장, 기본 탭 키 칸, 온보딩 키 단계, 판단 모델 칸) 목록을 PR에 적는다. 실패를 확인한다(`R-434`, spec 007 R-717) 〔단위 5〕
- [ ] T037 [화면 뒤] `App/Sources/Views/HelpContent.swift`, `GuideCardView.swift`, `KeyFieldState.swift`, `OnboardingView.swift`, `DecisionField.swift`, `BasicTabView.swift`(하루 시작 안내). T036 PASS 〔단위 5〕
- [ ] T038 [사람] quickstart 6-6 〔단위 5〕

---

## Phase 7: 단위 6 — 자동 시작과 "내일" 표시 (밀리면 먼저 뺌) [화면 뒤] [승인 5·6]

- [ ] T039 [P] `Tests/MokaCoreTests/AutoStartTests.swift`·`TomorrowMarkTests.swift`: data-model §17·§18(3초 경계, 입력이 다시 걸기, 모드·게이트에서 거짓, 상한 없으면 빈 집합, `estMin` 없으면 기본 작업 시간). 실패를 확인한다(`FR-05 R-410`, `FR-10 R-423`) 〔단위 6〕
- [ ] T040 `Sources/MokaCore/Scheduler/AutoStart.swift`, `TomorrowMark.swift`. T039 PASS 〔단위 6〕
- [ ] T041 [P] [화면 뒤] 앱 시험(자동 시작이 주입 시계로 3초 뒤 한 번, 설정 키 `auto_start`, spec US3-7 "내일")과 스냅샷 `test_R423_taskTabTomorrow`, `test_R410_basicTabAutoStart`. 실패를 확인한다 〔단위 6〕
- [ ] T042 [화면 뒤] `App/Sources/AppState.swift`(자동 시작 일정), `BasicTabView.swift`, `TaskListTabView.swift`, `CoreSettings.swift` 키 `auto_start`. T041 PASS 〔단위 6〕

---

## 의존과 순서

- T002는 끝났다(2026-11-16).
- 단위 1 → 단위 2 → 단위 3 → 단위 4 → 단위 6.
- 단위 1 병합 조건(plan "작업 단위"): T043 앱 노치 순서 시험 PASS, 그리고 단위 5 PR이 리뷰를 마쳐 병합할 수 있을 것. 단위 1과 단위 5를 이어 병합한다(plan 위험 11). 단위 5는 시안 확정(T003) 뒤 단위 1과 나란히 만든다.
- T003(시안 확정) → [화면 뒤] 태스크.
- 같은 단위 안에서 [P] Red 태스크는 나란히 쓸 수 있고, 각 Green은 짝 Red 뒤다.

## 작업 단위와 Issue

| 단위 | 태스크 | Issue 제목 후보 | 브랜치 |
|---|---|---|---|
| 1 | T001, T002, T004~T017, T043, T044 | spec 005 단위 1: 스케줄러 순수 로직과 moka-sim | `feat/<issue>-scheduler-core` |
| 2 | T018~T025 | spec 005 단위 2: 스키마 v4와 이월 판정 저장, 앱 고르기 | `feat/<issue>-carry-store` |
| 3 | T003, T026~T030 | spec 005 단위 3: 이월 카드 화면 | `feat/<issue>-carry-card` |
| 4 | T031~T035 | spec 005 단위 4: 가용 시간 질문과 오늘 끝 | `feat/<issue>-day-budget` |
| 5 | T036~T038 | spec 005 단위 5: 순위 안내 글 바꾸기(R-434) | `feat/<issue>-rank-copy` |
| 6 | T039~T042 | spec 005 단위 6: 자동 시작과 내일 표시 | `feat/<issue>-autostart-tomorrow` |

## FR·SC ↔ 태스크

| 요구 | 태스크 |
|---|---|
| R-401 | T006, T007 |
| R-402 | T006, T007, T022 |
| R-403 | T008, T009, T014, T015, T022, T023, T043 |
| R-404, R-405 | T008, T009(순수 함수만) |
| R-406 | T008, T009, T022, T023 |
| R-407 | T014, T022 |
| R-408 | T014, T015, T022, T043 |
| R-409 | T012, T013, T031~T034 |
| R-410 | T039~T042 |
| R-411 | T004, T005, T014, T018 |
| R-412 | T010, T011, T018~T021, T026, T027 |
| R-413 | T006, T007, T026~T029 |
| R-414, R-415 | T010, T011, T026~T029 |
| R-416 | T004, T010, T011, T016, T018 |
| R-417 | T010, T014, T026, T027 |
| R-419~R-422 | T012~T017, T031~T034 |
| R-423 | T039~T042 |
| R-431 | 모든 시험(가짜만) |
| R-432 | T016, T017 |
| R-433 | T028, T029, T033, T034 |
| R-434 | T022~T024, T036, T037 |
| SC-401, SC-402 | T008, T009, T016 |
| SC-403, SC-404 | T010, T026 |
| SC-405 | T014, T016, T031 |
| SC-406 | T018, T020, T031 |
| SC-410 | 기존 시험 번들 경계(quickstart 1) |
