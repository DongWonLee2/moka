---

description: "spec 002 저장과 체크포인트 작업 목록"
---

# Tasks: 저장과 체크포인트 (마일스톤 2)

**Input**: `specs/002-storage-checkpoint/`의 plan.md, spec.md(R-101~R-118), research.md(R1~R16), data-model.md, contracts/moka-sim-v1-additions.md, quickstart.md. 화면 시안 `~/Dev/ai-platform/projects/moka/design/002-mockup.html` v2(2026-10-30 사용자 확정, 저장소 밖)

**Tests**: 넣는다. 헌법 II(테스트 먼저)와 AGENTS.md "실패하는 테스트를 먼저 쓰고 실패를 확인한 뒤 구현한다"를 따른다. 테스트 태스크마다 Red 커밋 → 구현 태스크에서 Green 커밋.

**Organization**: 사용자 이야기(US1~US5)별로 묶는다. 각 태스크 끝의 `〔단위 N〕`은 plan "작업 단위" 번호이고 Issue 하나가 된다. 단위 1·3은 이야기마다 흩어져 있으니 Issue는 단위 번호로 모은다(아래 "작업 단위 ↔ Issue" 표).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 다른 파일을 고치고 아직 안 끝난 태스크에 기대지 않아 병렬로 할 수 있다
- **[Story]**: US1~US5(spec.md)
- **🔒**: 화면·앱 수명 사람 확인이 필요하다. 무인 실행으로 끝까지 가지 않는다(코드와 빌드는 무인 가능, 확인은 사람)
- **👁 사람이 볼 결정**: PR "사람이 볼 결정"에 올린다(스키마 스냅샷, `moka-sim` 계약 변경)
- **시안 N**: `002-mockup.html`의 N번 화면
- 이 파일의 "확인 지점"은 Phase 완료 조건이다(GLOSSARY의 체크포인트와 다르다)

## 공통 규칙 (모든 태스크)

- 테스트 표시 이름은 `@Test("FR-07 R-108: …")`처럼 PRD FR과 R-ID로 시작한다(ADR-0003). R-ID와 FR: R-101·102·103·118 FR-01, R-104 FR-05, R-105 FR-06, R-106~R-111 FR-07, R-112 FR-11, R-113·R-114 FR-09, R-115 FR-02, R-116 FR-21, 설정 키 FR-16. FR이 없는 것은 `ADR-0003 R-117:`, `ADR-0004:`처럼 근거 ADR로 시작한다. Swift Testing을 쓴다. 앱 스냅샷 번들만 XCTest.
- 타입·함수 이름과 모양은 data-model.md의 Swift 블록을 따른다. 거기 없는 작은 이름은 구현 PR에서 정하고 PR "가정"에 적는다.
- 시각은 주입한 값(`now`·`at`, 앱은 `MokaClock`)과 그레고리력 + 고정 `TimeZone(identifier: "Asia/Seoul")`·`"America/New_York"`으로 시험한다. MokaCore에서 `Date()`, `TimeZone.current`, `Calendar.current`를 읽지 않는다. 실제 시간을 기다리지 않는다.
- 가짜 할 일·가짜 키만 쓴다(예: "가짜 할 일 A", "가짜-키-0000"). 실제 앱 DB 경로(`~/Library/Application Support/dev.dongwon.moka/`), 실제 Keychain, 실제 decision API(TypeSafe Jev, OpenRouter)를 테스트·`moka-sim`·무인 실행에서 열거나 부르지 않는다(SC-106, ADR-0006). `eraseDatabaseOnSchemaChange`를 켜지 않는다.
- `Package.swift`를 바꾸지 않는다. 새 의존성을 두지 않는다. 새 파일은 기존 타깃 폴더에 둔다(plan "Structure Decision"). 이 전제가 깨지면 멈추고 PR "사람이 볼 결정"에 올린다.
- 로그(`os.Logger`)·`moka-sim` 출력에 할 일 제목, 체크포인트 두 줄 본문, 컨텍스트 이름, 키를 남기지 않는다.
- 화면 문구는 고객용 해요체, 시안 v2 글자를 그대로 쓴다. 화면 이름은 GLOSSARY: 컨텍스트 → "일정", 영향 → "중요도"(normal/high/critical = 조금/꽤/아주), 첫 행동 → "이어서 할 일", 연장 기본값 → "추가 시간". 코드·스키마 이름은 그대로다.
- 검증 명령: `swift test`, `cd tuning && python3 -m pytest`, 앱은 `xcodegen generate && xcodebuild build -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`. 결과는 PASS/FAIL/SKIP/NOT_RUN.

---

## Phase 1: Setup

**Purpose**: 기준 상태와 상수 자리

- [ ] T001 기준 상태 확인: `swift test`, `cd tuning && python3 -m pytest`, 앱 빌드를 돌려 기존 시험이 PASS인지 기록한다(원래 실패와 새 회귀 구분). 기존 golden(`Tests/MokaCoreTests/Fixtures/sim/*.expected.jsonl`)의 해시를 PR "완료 증거"에 적어 둔다(기존 golden 불변 조건, contracts "원칙") 〔단위 1〕
- [ ] T002 [P] `Sources/MokaCore/Defaults.swift`에 상수를 더한다: `Defaults.extendMin = 10`, `Defaults.extendMinRange = 1...180`, `Defaults.dayStart = "06:00"`(data-model §6). 기존 `quantumMin`·`quantumMinRange`·`quantumPresets`는 그대로 〔단위 1〕

---

## Phase 2: Foundational (모든 이야기가 기대는 것)

**Purpose**: 값 타입, 하루 경계, 저장 프로토콜·메모리 구현, v2 마이그레이션. US1~US5가 모두 이것에 기댄다

**⚠️ CRITICAL**: 이 Phase의 단위 1 몫이 병합되기 전에는 단위 2·3·5를 시작하지 않는다

### Tests (Red)

- [ ] T003 [P] `Tests/MokaCoreTests/ValueTypeTests.swift`에 값 타입 시험을 쓰고 실패를 확인한다(data-model §2·§5.6):
  - `FR-01 R-101`: `Weekday(rawValue:)`는 "1(일)~7(토)"만, 0·8은 nil. `LocalDay(text:)`는 `YYYY-MM-DD`이고 "형식·달력 날짜가 틀리면 nil"(`2026-02-30`, `2026-1-5`, `2026-13-01`), `text` 왕복, `adding(days:calendar:)`가 달·해를 넘김, `weekday(calendar:)`가 `Calendar.component(.weekday, from:)`와 같은 번호
  - `DayStart(text:)`는 "`HH:MM`(24시간, 두 자리). 00:00~23:59"만(`6:00`, `24:00`, `06:60` → nil)
  - `FR-01 R-101` 값 검증 표: 제목·컨텍스트 이름 "앞뒤 공백 제거 뒤 비어 있지 않음", `est_min` "nil 또는 1 이상 정수", `weekday` "`.weekly`면 1~7, 아니면 nil", 두 줄 "앞뒤 공백 제거. 비면 `""`". 틀리면 "저장 안 함"
  - 열거형 `rawValue`: `TaskStatus` todo/active/done/dropped, `Recurrence` none/daily/weekly, `ContextImpact` normal/high/critical, `CheckpointTrigger` 여덟 값(`dayEnd` = `"day_end"`, `` `switch` `` = `"switch"`), `UserAction` done/skip/switch, `SchedulerChoice.oldestUnpickedV0` = `"oldest_unpicked_v0"`
  〔단위 1〕
- [ ] T004 [P] `Tests/MokaCoreTests/DayBoundaryTests.swift`에 하루 경계 시험을 쓰고 실패를 확인한다(data-model §5.4, R-114):
  - `FR-09 R-114`: 하루 시작 06:00에서 05:59:59 → 어제, 06:00:00 → 오늘(`Asia/Seoul`, `America/New_York` 둘 다)
  - `America/New_York` 3월·11월 전환일. 하루 시작 02:30 같은 전환 구간 값(`matchingPolicy: .nextTime`, `repeatedTimePolicy: .first`). "하루는 시간이 흐를수록 줄어들지 않는다"(research R9)
  - `start(of:dayStart:calendar:)`와 `day(containing:)`의 왕복
  〔단위 1〕
- [ ] T005 [P] `Tests/MokaCoreTests/AppSettingsTests.swift`에 설정 읽기·쓰기 규칙 시험을 쓰고 실패를 확인한다(data-model §6):
  - `FR-16`: `default_extend_min` "없거나 1~180 밖이면 10", `day_start` "없거나 형식이 틀리면 `06:00`", `onboarding_done` "값이 `true`가 아니면 온보딩을 보임"(`"TRUE"`, `"1"`도 보임)
  - `FR-16`: "쓰기는 형식을 지킨 값만 받고, 틀리면 이전 값을 둔다". 저장소가 throw하면 읽기 기본값
  〔단위 1〕
- [ ] T006 [P] `Tests/MokaStoreTests/StorageContractTests.swift`에 공용 계약 시험을 `@Test(arguments:)`로 두 구현(메모리, GRDB 메모리 DB)에 쓰고 실패를 확인한다(data-model §3, research R7). 이 태스크에서는 메모리 구현만 인자로 넣고 GRDB 인자는 T013에서 더한다:
  - `FR-01 R-101`: 할 일 왕복(모든 열), "id는 1부터 차례로", `tasks()`는 "버림 포함, id 오름차순"
  - `FR-07 R-108`·`FR-11 R-112`: `apply(StoreBatch)`가 할 일 갱신·체크포인트·로그를 한 번에. "하나라도 실패하면 아무것도 남지 않는다"(없는 할 일을 가리키는 체크포인트를 섞어 `taskNotFound` → 앞의 할 일 갱신도 없음)
  - `checkpoints()`·`decisions()`는 id 오름차순, 덧붙이기만(수정·삭제 메서드가 없음을 컴파일로 확인)
  - `FR-02 R-115`: 컨텍스트 왕복, `contexts()`는 "date 오름차순, 같으면 id", `deleteContext`는 실제 삭제, 없는 id는 `contextNotFound`
  - `latestCheckpoint(taskID:)`는 가장 큰 id
  〔단위 1·2〕
- [ ] T007 [P] `Tests/MokaStoreTests/MigrationTests.swift`의 이름 시험 리터럴을 `["v1_settings", "v2_tasks_contexts_checkpoints_log"]`로 바꾸고(ADR-0007), 스키마 스냅샷 시험이 새 표 넷을 요구하게 해 실패를 확인한다(data-model §7). `Tests/MokaStoreTests/StoreConstraintTests.swift`에 GRDB 전용 시험을 쓴다:
  - `ADR-0004 R-112`: 원시 SQL로 넣은 줄 가운데 `provider` 없이 `question_version`·`probs_json`·`state_hash`나 `model_snapshot`이 있는 줄은 거부, `provider = 'fallback'`만 있고 나머지 NULL인 줄은 허용(F5)
  - `ADR-0004 R-101`: `recurrence = 'daily'` + `cycle_day` NULL 거부, `'none'` + NULL 허용, `'weekly'` + `weekday` NULL 거부, `weekday` 8 거부(F2·P2)
  - `ADR-0004 R-108`: `trigger` 여덟 값 밖 거부, `impact` 세 값 밖 거부, `status` 네 값 밖 거부
  - `ADR-0004`: 체크포인트·로그가 가리키는 할 일을 DELETE하면 실패(`ON DELETE RESTRICT`, 외래 키가 켜져 있는지 이 시험으로 확인)
  - P3: 원시 SQL로 모르는 `user_action`·`scheduler_choice`를 넣고 `decisions()`로 읽으면 `StoreError.unknownValue(column:value:)`
  〔단위 2〕
- [ ] T008 [P] `tuning/tests/test_schema_contract.py`를 쓰고 실패를 확인한다(research R16): `schema/moka-schema.sql`을 `sqlite3` 메모리 DB에 실행하고 `decisions_log` 열 이름 집합이 research R5 목록과 같은지, 판단 칸이 모두 NULL인 가짜 줄과 폴백 줄(`provider = 'fallback'`, 나머지 NULL)을 넣을 수 있는지, 공급자 없이 다른 판단 칸이나 `model_snapshot`이 있는 줄이 거부되는지, `tasks`의 `daily` + `cycle_day` NULL이 거부되고 `none` + NULL이 들어가는지 본다. 표준 라이브러리만 〔단위 2〕

### Implementation (Green)

- [ ] T009 `Sources/MokaCore/`에 값 타입을 둔다: `TaskModel.swift`(`TaskID`, `TaskStatus`, `Recurrence`, `Weekday`, `MokaTask`, `NewTask`), `ContextModel.swift`(`ContextID`, `ContextImpact`, `MokaContext`, `NewContext`), `CheckpointModel.swift`(`CheckpointTrigger`, `CheckpointNotes`, `Checkpoint`, `NewCheckpoint`), `DecisionLog.swift`(`UserAction`, `SchedulerChoice`, `Judgment`, `DecisionLogEntry`, `NewDecisionLogEntry`), 값 검증 함수(data-model §5.6). T003 PASS 〔단위 1〕
- [ ] T010 `Sources/MokaCore/LocalDay.swift`에 `LocalDay`, `DayStart`, `DayBoundary.day(containing:dayStart:calendar:)`·`start(of:dayStart:calendar:)`를 구현한다(data-model §2·§5.4, ADR-0010). T004 PASS. 리눅스 컨테이너(quickstart 1의 `docker run`)에서도 PASS인지 PR에 적는다(plan 위험 7) 〔단위 1〕
- [ ] T011 `Sources/MokaCore/AppSettings.swift`에 `default_extend_min`·`day_start`·`onboarding_done` 읽기·쓰기 규칙을 둔다. 기존 `QuantumSettings.swift`는 바꾸지 않는다. T005 PASS 〔단위 1〕
- [ ] T012 `Sources/MokaCore/Storage.swift`에 `StoreError`, `StoreBatch`, `TaskRepository`, `ContextStore`, `InMemoryTaskRepository`, `InMemoryContextStore`를 두고, `Sources/MokaCore/KeyStore.swift`에 `KeyStore`(`save`는 "앞뒤 공백을 뺀 값. 비면 저장하지 않음", `hasKey`, `delete`, 값 읽기 없음)와 `InMemoryKeyStore`를 둔다. 메모리 구현은 "GRDB 구현과 같은 규칙을 지킨다: id는 1부터 차례로, 없는 할 일을 가리키는 체크포인트·로그는 `taskNotFound`, `apply` 도중 실패하면 되돌림". T006(메모리) PASS 〔단위 1〕
- [ ] T013 👁 `Sources/MokaStore/Migrations.swift`에 `v2_tasks_contexts_checkpoints_log`를 `v1_settings` 뒤에 등록한다. data-model §7의 `CREATE TABLE` 네 문장을 각각 한 줄 문자열 `db.execute(sql:)`로 실행하고 `DEFAULT`·색인을 두지 않는다. `Sources/MokaStore/GRDBTaskRepository.swift`·`GRDBContextStore.swift`를 구현한다: 시각 `created_at`은 "UTC `YYYY-MM-DDTHH:MM:SSZ`", 날짜는 `YYYY-MM-DD`(research R13, GRDB `Date` 기본 형식 안 씀), 열거 값은 `rawValue`로 쓰고 읽을 때 모르는 값은 `unknownValue`, `apply`는 `write` 한 트랜잭션. T006에 GRDB 인자를 더하고 T006·T007 PASS. 스냅샷 시험이 출력한 텍스트를 사람이 `schema/moka-schema.sql`로 옮긴다(ADR-0004, 이름순 다섯 표). 스냅샷 변경은 PR "사람이 볼 결정" 〔단위 2〕
- [ ] T014 T008 PASS 확인(`cd tuning && python3 -m pytest`). T013의 스냅샷만으로 통과해야 한다 〔단위 2〕

**확인 지점**: `swift test`·pytest PASS. 메모리·GRDB 두 저장소가 같은 계약을 통과한다(SC-101의 저장 몫)

---

## Phase 3: User Story 1 - 할 일이 저장되고 노치가 다음 할 일을 띄운다 (Priority: P1) 🎯 MVP

**Goal**: 할 일을 노치·설정 창에서 넣고 고치고 지운다. 앱을 다시 켜도 남는다. 노치는 가장 먼저 만든 대기 할 일을 띄운다. 할 일 탭에서 보기·정렬을 고른다

**Independent Test**: 화면 없이 `swift run moka-sim run Tests/MokaCoreTests/Fixtures/sim/storage-us1-pick.json`이 할 일 셋 추가 → `relaunch` → `notch_task` 1을 출력한다. 화면은 quickstart 6 첫째·둘째·여덟째 줄

### Tests (Red)

- [ ] T015 [P] [US1] `Tests/MokaCoreTests/TaskRulesTests.swift`에 고르기 시험을 쓰고 실패를 확인한다(data-model §5.1): `FR-05 R-104` "후보 = `status == .todo`인 할 일. `active`·`done`·`dropped`는 뺀다", "후보가 둘 이상이고 `previous`가 후보에 있으면 그것을 뺀다. 후보가 하나뿐이면 빼지 않는다", "남은 후보 가운데 `id`가 가장 작은 것. 없으면 nil", `previous`가 후보에 없으면 무시 〔단위 1〕
- [ ] T016 [P] [US1] `Tests/MokaCoreTests/TaskListViewTests.swift`에 목록 보기 시험을 쓰고 실패를 확인한다(data-model §5.7, R-118):
  - `FR-01 R-118`: "버린(`dropped`) 할 일은 늘 뺀다". `all` = 버리지 않은 모든 할 일. `today` = "마감 ≤ 오늘 + `.daily` + 오늘 요일과 `weekday`가 같은 `.weekly`". `thisWeek` = "마감 ≤ 이번 주 토요일(주는 일요일 시작, `weekday` 1=일과 같다) + 모든 반복". "마감 없는 일반 할 일은 `all`에만 나온다. 상태(대기·진행 중·완료)로는 거르지 않는다"
  - 정렬: `created`는 id 오름차순(R-104와 같은 순서), `deadline`은 "마감 오름차순, 마감 없음은 맨 뒤, 같으면 `created` 순서"
  - 경계값: "오늘 05:59:59(어제로 봄)·06:00:00, 토요일 마감·일요일 마감, 매주 반복의 요일이 오늘과 같음·다름"(`today`는 호출자가 `DayBoundary`로 구해 넘긴다)
  〔단위 1〕
- [ ] T017 [P] [US1] `Tests/MokaCoreTests/NotchSessionTests.swift`에 세션 시험(할 일 연결 몫)을 쓰고 실패를 확인한다(data-model §4.2 표): `empty(nil)` + 고르기 → 후보 있으면 `empty(draft)` + `taskID`, 빠른 입력 → 할 일 만듦(`NewTask`, 반복 없음) → `empty(draft)`, `empty(draft)` + 시작 → `running` + 할 일 `active`, 지움(노치의 할 일) → `empty(nil)` → 고르기. 표의 "거부" 칸마다 하나. "초안의 칩은 그 순간의 `default_quantum_min`" 〔단위 1〕
- [ ] T018 [P] [US1] 👁 `Tests/MokaCoreTests/SimScenarioTests.swift`에 storage 모드 디코딩 오류 시험을 더한다(contracts "오류 덧붙임" 종료 코드 2 줄 전부): `storage`가 불리언이 아님, `storage` 없이 새 이벤트나 `settings.day_start`, 새 이벤트의 모르는 키·필수 필드 없음·타입 틀림, 없는 `task` id, 버린 할 일 고침, 빈 제목, `recurrence` 밖, `weekday` 1~7 밖이거나 결과 반복이 `weekly`가 아닌데 `weekday`, `est_min` 0 이하, 없는 날짜, `day_start` 형식, `edit_task`에 고칠 필드 없음, 단계 × 이벤트 표의 "2", 도는 중 `complete`나 초안 `start`에 두 줄 필드. 픽스처는 `Tests/MokaCoreTests/Fixtures/sim/errors/storage-<이름>.json`, 기대 오류 종류는 시험 코드 표 〔단위 3〕
- [ ] T019 [P] [US1] 👁 `Tests/MokaCoreTests/Fixtures/sim/`에 storage golden 두 개를 둔다(`SimGoldenTests`가 같은 이름 `.expected.jsonl`을 요구): `storage-contract-example.json`(contracts "입력 덧붙임" 예시 그대로, 기대 출력은 contracts "위 입력의 출력 전체" 아홉 줄 그대로)과 `storage-us1-pick.json`(`add_task` 셋 → `relaunch` → `notch_task` 1, `edit_task`·`delete_task` → 지운 할 일이 후보에서 빠짐, `enter_title`로 빠른 입력). 기존 golden 파일은 고치지 않는다 〔단위 3〕

### Implementation (Green)

- [ ] T020 [US1] `Sources/MokaCore/TaskRules.swift`에 `OldestUnpickedRule.pick(from:excluding:)`와 `choice`를 둔다. T015 PASS 〔단위 1〕
- [ ] T021 [US1] `Sources/MokaCore/TaskListView.swift`에 `TaskListScope`(`all`, `today`, `thisWeek`), `TaskListOrder`(`created`, `deadline`), `TaskListView.rows(_:scope:order:today:calendar:)`를 둔다. 입력·출력은 `[MokaTask]`(data-model §5.7). T016 PASS 〔단위 1〕
- [ ] T022 [US1] `Sources/MokaCore/NotchSession.swift`에 `NotchSession`(`timer`, `taskID`, `previousTaskID`)과 고르기·빠른 입력·시작·지움 동작을 둔다. 함수는 "새 세션과 `StoreBatch`를 돌려주고, 호출자가 `apply`한 뒤 세션을 바꾼다". 타이머 전이는 spec 001 `NotchTimer.apply` 그대로. T017 PASS 〔단위 1〕
- [ ] T023 [US1] 👁 `Sources/MokaCore/Sim/`에 storage 모드를 더한다: `SimScenario.swift`(`storage`, `settings.day_start`, 새 이벤트 `add_task`·`edit_task`·`delete_task`·`set_day_start`·`activate`·`relaunch`·`quit`·`sleep`·`skip`·`switch`, 기존 `start`·`complete`의 `done_note`·`next_note`), `SimRunner.swift`(저장소를 주입받는 공개 진입점, CLI는 `InMemoryTaskRepository`, 앱과 같은 MokaCore 함수만 부름, 암묵 tick은 원본 그대로, 단계 × 이벤트 표, "꺼짐" 단계), `SimOutput.swift`(원본 여섯 키 뒤로 `notch_task`, `has_first_action`, `tasks`, `checkpoint`, `decision`을 이 순서로, 직접 조립), 불변식 검사(contracts "오류 덧붙임" 종료 코드 1 줄 전부). `storage`가 없거나 `false`면 출력은 원본과 바이트 단위로 같다. 이 태스크는 US1 이벤트(`add_task`·`edit_task`·`delete_task`·`enter_title`·`start`·`relaunch`)와 출력 형식까지. T018(US1 몫)·T019 PASS, 기존 golden 변경 0줄(`git diff --stat main -- Tests/MokaCoreTests/Fixtures/sim/*.expected.jsonl`) 〔단위 3〕
- [ ] T024 [US1] 👁 `specs/001-notch-timer/contracts/moka-sim-v1.md`에 contracts/moka-sim-v1-additions.md 내용을 옮긴다(이 문서가 "구현 PR이 원본에 옮긴다"고 정함). PR "사람이 볼 결정"에 계약 변경으로 올린다 〔단위 3〕
- [ ] T025 🔒 [US1] `App/Sources/Views/`에 노치 뷰를 고친다(시안 1·2번). 뷰는 값과 콜백만 받는다(ADR-0009):
  - `CollapsedView.swift`: 초안이 있는 대기 할 일은 "회색 점 + 회색 제목"(C1-B, 시간 없음, 왼쪽 104pt, 길면 …). 빈 상태 회색 점과 도는 중 점·제목·시간은 spec 001 그대로
  - `ExpandedView.swift`: 초안의 시간 고르기 단계는 제목이 채워져 있고 제목 입력을 건너뛴다(R-104). 새 할 일 입력은 그대로 빈 상태에서(R-103)
  〔단위 4〕
- [ ] T026 🔒 [US1] `App/Sources/Settings/SettingsView.swift`를 탭 셋(기본·할 일·일정) 창으로 바꾼다(시안 6번, macOS 설정 창 도구 막대 탭, 폭 460pt, 창 제목은 탭 이름). 001의 로고 줄은 뺀다. 메뉴 막대 항목은 spec 001 R-012 그대로(ADR-0005 정정 없음). 기본 탭: 기본 작업 시간(기존), 추가 시간(`default_extend_min`, 숫자 칸 + 스테퍼, 1~180, 안내 "시간이 끝났을 때 더 이어 갈 시간이에요."), 하루 시작 시각(`day_start`, 안내 "이 시각이 지나면 반복 할 일이 다시 대기로 돌아와요."). 안내 문장에 "3단계"를 쓰지 않는다 〔단위 4〕
- [ ] T027 🔒 [US1] `App/Sources/Views/TaskListView.swift`(이름은 MokaCore 타입과 겹치지 않게 `TaskListTabView` 등으로 정하고 PR "가정")에 할 일 탭을 만든다(시안 7번, R-102·R-118):
  - 위 줄: 보기 `[전체 · 오늘 · 이번 주]` 세그먼트, 오른쪽 정렬 메뉴 `만든 순 ▾ / 마감 순`. 값은 `AppState.taskListScope`·`taskListOrder`, 처음 값 `all`·`created`, 저장하지 않음(data-model §8)
  - 줄: 제목, 보조 줄(마감 "마감 11월 5일", 예상 "예상 50분", 반복 "매일"/"매주 수요일", "N번 미뤘어요"), 상태 배지(대기 / 진행 중(모카색) / 완료), 완료는 줄 긋고 흐리게. 반복 할 일의 `streak > 0`이면 잔 아이콘이 든 모카색 배지 "N일 연속 진행"(0이면 배지 없음)
  - "다음" 표시: `OldestUnpickedRule.pick`(지금 세션의 `previousTaskID`) 결과 할 일에만. 보기·정렬과 무관
  - 아래: `+`(새 할 일 시트) `−`(고른 할 일 지우기 확인), 안내 "두 번 클릭하면 고쳐요. **다음** 표시가 붙은 할 일이 노치에 떠요."
  - 버린 할 일은 보이지 않는다. 검색 없음
  〔단위 4〕
- [ ] T028 🔒 [US1] `App/Sources/Views/TaskFormView.swift`에 할 일 시트를 만든다(시안 8·9번, R-101·R-102):
  - 새로 만들기: 제목(자리표시 "무엇을 할까요?", 비면 저장 꺼짐 + 왼쪽 아래 "제목을 넣어 주세요."), 마감(체크 "마감 있음" + 날짜 고르기, 끄면 마감 없음), 반복 세그먼트 없음/매일/매주(내용 폭), 매주면 요일 줄 일~토(하나만, 기본은 등록 순간이 속한 하루의 요일, 안내 "오늘(금)이 먼저 골라져 있어요. 하나만 고를 수 있어요."), 예상 소요(비워도 됨, 1 이상 정수가 아니면 "1분 이상으로 넣어 주세요."), 취소·저장
  - 고치기(줄 두 번 클릭): 같은 칸 + "이어서 할 일"은 읽기만(안내 "멈출 때 적은 메모예요"), 왼쪽 "지우기…"
  - 지우기 확인 시트: 제목 `"<제목>"를 지울까요?`, 본문 "지우면 노치에 다시 뜨지 않아요. 지금까지 남긴 기록은 그대로 둬요."(도는 할 일이면 앞에 "지금 타이머가 도는 할 일이에요. 지우면 타이머가 멈추고"), 취소·지우기(빨강). 지우면 `dropped`(R4)
  - 도는 할 일의 제목·마감을 고치면 노치에 바로 보이고 타이머는 그대로(spec Edge Cases)
  〔단위 4〕

**확인 지점**: `swift test` PASS, storage golden PASS, 기존 golden 변경 0줄, 앱 빌드 PASS. 화면은 사람이 quickstart 6으로

---

## Phase 4: User Story 2 - 완료·미루기·바꾸기와 체크포인트 (Priority: P1) 🎯 MVP

**Goal**: 도는 중·시간 끝에서 세 버튼, 두 줄 입력(돌아가기·안 적기·등록), 체크포인트와 로그 한 줄, 이어서 할 일 표시

**Independent Test**: `moka-sim` `storage-us2-buttons.json`이 바꾸기 → 다른 할 일, 미루기 `skip_count` 1, 시간 끝의 세 버튼 → 계기 `quantum`, 버튼마다 `decision` 한 줄을 출력한다. 화면은 quickstart 6 넷째~여섯째 줄

### Tests (Red)

- [ ] T029 [P] [US2] `Tests/MokaCoreTests/NotchSessionTests.swift`에 버튼 시험을 더하고 실패를 확인한다(data-model §4.1 표, §4.2 표):
  - `FR-07 R-106`: 도는 중 바꾸기 → 할 일 `active` → `todo`, 체크포인트 `switch`(두 줄), 로그 `switch`, `previousTaskID` = 그 할 일 → 고르기가 그것을 뺌(후보 하나면 같은 할 일)
  - `FR-07 R-106`: 도는 중 미루기 → `skip_count` + 1, 체크포인트 `skip`, 로그 `skip`
  - `FR-06 R-105`: 도는 중 완료 → `done`, 반복이면 `streak` + 1, 체크포인트 없음, 로그 `done`, `previousTaskID` nil
  - `FR-07 R-107`: 시간 끝에서 완료·미루기·바꾸기·다시 시작 → 체크포인트 계기 `quantum`, 두 줄이 비어도 남음, 다시 시작은 로그 없음·`active` 유지
  - `FR-07 R-109`: "체크포인트의 다음 할 일 줄이 비어 있지 않으면 같은 쓰기에서 `first_action`을 그 줄로 바꾼다. 비어 있으면 이전 값을 둔다"
  - `FR-11 R-112`: 버튼마다 `StoreBatch` 하나, 로그 한 줄, `judgment`·`modelSnapshot` nil, `schedulerChoice` = `oldest_unpicked_v0`
  - "진행 중인 반복 할 일은 하루 판정에서 건너뛴다. 그 할 일을 완료·미루기·바꾸기로 끝낼 때 그 할 일만 먼저 판정하고(§5.3), 그 뒤에 버튼 규칙을 적용한다"
  〔단위 1〕
- [ ] T030 [P] [US2] `Tests/MokaCoreTests/CheckpointRulesTests.swift`에 경과 분·첫 행동 표시 시험을 쓰고 실패를 확인한다(data-model §5.5): `FR-07 R-108` `elapsedMinutes` = "`floor((now − startedAt) / 60)`를 `0...quantumMin`으로 자름", `now`는 "두 줄을 등록·안 적기 한 순간", 시간 끝은 `quantumMin`, 시계를 되돌린 `now`는 0. `FR-07 R-109` `showsInCollapsed` = "`0 ≤ now − pickedAt < 2초`"(1.999초 참, 2초 거짓, 음수 거짓) 〔단위 1〕
- [ ] T031 [P] [US2] 👁 `Tests/MokaCoreTests/Fixtures/sim/storage-us2-buttons.json`과 기대 출력을 둔다(quickstart 2): 할 일 하나뿐일 때 미루기 → 같은 할 일, `skip_count` 1 / 시간 끝에서 미루기·바꾸기·완료·다시 시작 → 계기 `quantum` / 두 줄 모두 건너뜀 → 빈 체크포인트, `has_first_action` 이전 값 유지 / 도는 할 일 `delete_task` → 타이머 멈춤, 다음 할 일, 로그·체크포인트 수 그대로 〔단위 3〕

### Implementation (Green)

- [ ] T032 [US2] `Sources/MokaCore/NotchSession.swift`에 완료·미루기·바꾸기·다시 시작 동작을 더하고, `Sources/MokaCore/CheckpointModel.swift`에 `Checkpoint.elapsedMinutes(startedAt:now:quantumMin:)`, `FirstActionDisplay.showsInCollapsed(pickedAt:now:)`를 둔다. 완료·미루기·바꾸기는 모두 타이머에 `.complete`를 보낸다. T029·T030 PASS 〔단위 1〕
- [ ] T033 [US2] `Sources/MokaCore/Sim/SimRunner.swift`에 `skip`·`switch`와 `start`·`complete`의 두 줄 필드를 더한다(도는 중이면 계기 `skip`/`switch`, 시간 끝이면 `quantum`, 이벤트 하나는 체크포인트·로그 최대 하나). T018(US2 몫)·T031 PASS 〔단위 3〕
- [ ] T034 [P] [US2] `Sources/MokaCore/NotchStatus.swift`에 두 줄 입력 중 상태 글자 "바꾸는 중"·"미루는 중"을 더하고 `Tests/MokaCoreTests/NotchStatusTests.swift`에 Red → Green(시안 4번). Issue #52가 같은 파일의 "N분 집중"·"시간 고르기" 줄을 바꾸므로 먼저 병합된 쪽에 맞춰 갱신한다 〔단위 4〕
- [ ] T035 🔒 [US2] `App/Sources/Views/ExpandedView.swift`에 도는 중 화면을 고친다(시안 3번): 제목 아래 "이어서 할 일 <첫 행동>" 한 줄(첫 행동이 있을 때만, 크레마색, 길면 …), 남은 시간 오른쪽에 미루기·바꾸기·완료(같은 무게, 강조 없음). 시간 고르기 단계(시안 2번)에도 같은 "이어서 할 일" 줄 〔단위 4〕
- [ ] T036 🔒 [US2] `App/Sources/Views/CheckpointNotesView.swift`에 두 줄 입력 화면을 만든다(시안 4번, R-106, C2-B·C3-B·C4-B):
  - 오른쪽 위 상태 "바꾸는 중"/"미루는 중"(T034), 제목 줄 오른쪽 "N분 했어요"(지금까지의 경과, 계속 바뀜)
  - 라벨 "어디까지 했어요?" + 칸, 라벨 "다음엔 뭐부터 할까요?" + 칸(자리표시 "비워 둬도 돼요"), 각 한 줄, 길면 칸 안에서 가로로 흐름
  - 아래 줄: 왼쪽 "돌아가기 esc", 오른쪽 "안 적기", "등록 ↵"(기본 버튼)
  - 첫 칸이 자동 포커스(사용자가 노치를 클릭해 누른 버튼이라 key를 가져와도 됨). 첫 칸 Enter·Tab = 둘째 칸, 둘째 칸 Enter = 등록
  - 돌아가기(Esc): `pendingAction` nil, `notesDraft` 비움, 아무것도 쓰지 않음, 타이머는 계속(data-model §8). 입력 중 시간이 끝나면 시간 끝 화면(T037)으로 바뀌고 적던 글자는 이어진다
  〔단위 4〕
- [ ] T037 🔒 [US2] `App/Sources/Views/ExpiredView.swift`를 고친다(시안 5번, R-107): 제목 + 빨간 0:00, 라벨 둘과 두 칸(자리표시 "비워 둬도 돼요"), 시간 칩 줄(spec 001 그대로), 아래 줄 왼쪽 미루기·바꾸기, 오른쪽 다시 시작·완료 ↵. 어떤 버튼이든 그때 두 칸 글자(비어도 됨)를 계기 `quantum`으로. Enter(C4-B): 첫 칸 = 둘째 칸으로, 둘째 칸 = 완료, 칸 밖(노치만 클릭) = 완료(spec 001 그대로). 키보드 포커스를 가져가지 않는 규칙은 spec 001 그대로. Issue #52(다시 시작 → "N분 더")가 같은 파일을 고친다: 먼저 병합된 쪽에 맞춘다 〔단위 4〕
- [ ] T038 🔒 [US2] `App/Sources/Views/CollapsedView.swift`에 이어서 할 일 2초 표시를 더한다(시안 1번 아래 줄, R-109): 노치가 할 일을 고른 순간(`pickedAt`) 첫 행동이 있으면 왼쪽 104pt에 "이어서 · <첫 행동>"(크레마색, 길면 …)을 `showsInCollapsed`가 참인 동안만, 그 뒤 C1-B 모양. 첫 행동이 없으면 바로 C1-B 〔단위 4〕
- [ ] T039 🔒 [US2] `App/Sources/AppState.swift`에 버튼과 두 줄 입력을 잇는다: 미루기·바꾸기 → `pendingAction` 켬, 등록·안 적기 → `NotchSession` 버튼 함수 → `TaskRepository.apply(StoreBatch)` → 세션 교체 → 고르기 → `pickedAt` 갱신, 완료 → 바로 같은 경로. 저장이 throw하면 세션을 바꾸지 않고 `os.Logger`에 오류 종류만 남긴다(제목·본문 없음) 〔단위 4〕

**확인 지점**: `swift test` PASS, us2 golden PASS, 앱 빌드 PASS. SC-102·SC-103은 시뮬레이터와 단위 시험으로, 화면은 사람이 quickstart 6

---

## Phase 5: User Story 3 - 앱을 끄거나 맥이 잠들어도 이어서 시작한다 (Priority: P1)

**Goal**: 종료·잠자기 체크포인트, 켤 때 복구, 이어서 할 일과 함께 대기 할 일을 띄움

**Independent Test**: `moka-sim` `storage-us3-lifecycle.json`이 도는 중 `sleep` → 체크포인트 `sleep`, 끝 시각을 넘긴 이벤트에서 `expired`, `quit` 없이 `relaunch` → `active`가 `todo`를 출력한다. 화면은 quickstart 7

### Tests (Red)

- [ ] T040 [P] [US3] `Tests/MokaCoreTests/TaskRulesTests.swift`에 복구·종료·잠자기 시험을 더하고 실패를 확인한다:
  - `FR-07 R-111`: `LaunchRecovery.revert`는 "`active`인 할 일을 모두 `todo`로 바꾼 목록(바뀐 것만)", 정상·비정상 종료를 구분하지 않음
  - `FR-07 R-110`: `running`에서 잠자기·종료 → 계기 `sleep`/`quit`, 두 줄 빈 값, 경과 분만, 할 일 상태와 타이머 그대로. `expired`·빈 상태에서는 기록 없음(research R12)
  〔단위 1〕
- [ ] T041 [P] [US3] 👁 `Tests/MokaCoreTests/Fixtures/sim/storage-us3-lifecycle.json`과 기대 출력을 둔다(quickstart 2): 잠자기(도는 중) → `sleep`, 그 뒤 끝 시각을 넘긴 이벤트에서 `expired`(체크포인트 둘) / `quit` 뒤 `relaunch` → `has_first_action` true / `quit` 없이 `relaunch` → `todo`, 타이머 없음 / 꺼짐 뒤 `start` 오류는 `errors/storage-start-after-quit.json` 〔단위 3〕

### Implementation (Green)

- [ ] T042 [US3] `Sources/MokaCore/TaskRules.swift`에 `LaunchRecovery.revert`, `Sources/MokaCore/NotchSession.swift`에 잠자기·종료 체크포인트 함수를 둔다. T040 PASS 〔단위 1〕
- [ ] T043 [US3] `Sources/MokaCore/Sim/SimRunner.swift`에 `sleep`·`quit`·`relaunch`("메모리 상태를 버리고 R-111 복구 → 하루 판정 → 고르기")를 더한다. T041 PASS 〔단위 3〕
- [ ] T044 🔒 [US3] `App/Sources/MokaApp.swift`·`App/Sources/AppState.swift`에 앱 수명을 잇는다(research R12): DB를 한 번 열어 `GRDBSettingsStore`·`GRDBTaskRepository`·`GRDBContextStore`에 나눠 줌(실제 경로는 기존 `MokaDatabase` 경로 가드 그대로), 시작 때 `LaunchRecovery` → 하루 판정(T050) → 고르기, `NSApplication.willTerminateNotification`과 `NSWorkspace.willSleepNotification`에서 `running`이면 동기 `write`로 체크포인트, `applicationShouldTerminate`로 종료를 미루지 않음. 깨어남 동작은 spec 001 R-005·R-008 그대로. 사람 확인(quickstart 7): 종료 → 다시 켬 → 대기 + 이어서 할 일, 강제 종료 → 대기. 로그아웃·시스템 종료 기록은 미확인(실제 DB 조회만 가능하면 NOT_RUN) 〔단위 5〕

**확인 지점**: `swift test` PASS, us3 golden PASS. 앱 수명은 사람이 quickstart 7

---

## Phase 6: User Story 4 - 반복 할 일은 늘 하나다 (Priority: P2)

**Goal**: 매일·매주 반복이 하루 경계 뒤 첫 활성화에서 같은 한 건으로 대기로 돌아온다

**Independent Test**: `moka-sim` `storage-us4-recurrence.json`이 매일 완료 → 다음 날 06:00 뒤 `activate` → `todo`, 연속 기록 유지, 같은 날 `activate` 두 번 → 같은 `tasks`를 출력한다

### Tests (Red)

- [ ] T045 [P] [US4] `Tests/MokaCoreTests/RecurrenceResetTests.swift`에 반복 리셋 시험을 쓰고 실패를 확인한다(data-model §5.3):
  - `FR-09 R-113`: 지금 주기 첫 하루 `c` "매일은 `today`. 매주는 `today − ((today의 요일 − weekday + 7) % 7)`일", 앞 주기 `p` "매일은 `c − 1일`, 매주는 `c − 7일`"
  - 대상 "`recurrence != .none`, `status ∈ {todo, done}`, `cycleDay < c`. `active`·`dropped`는 건드리지 않는다"
  - 표: "`status == done` 그리고 `cycleDay == p`" → `todo`, `skip_count` 0, `streak` 그대로, `cycle_day` `c` / "그 밖(`todo`, 또는 더 오래전 `done`)" → `todo`, 0, 0, `c`
  - 멱등: "두 번 돌린 결과 == 한 번 돌린 결과, 할 일 수가 그대로(SC-104), 두 시간대"
  - "하루 시작 시각을 바꿔 `today`가 앞 날로 돌아가도 `cycleDay < c`가 아니므로 되돌리지 않는다"
  - 매주 수요일: 목~화에는 그대로, 다음 수요일 06:00 뒤 `todo`
  - 새로 만들 때·반복을 새로 걸 때·요일을 바꿀 때 `cycle_day = c`, 반복을 없애면 nil. `.weekly` + `weekday` nil인 `NewTask`는 "등록 순간이 속한 하루의 요일"
  〔단위 1〕
- [ ] T046 [P] [US4] 👁 `Tests/MokaCoreTests/Fixtures/sim/storage-us4-recurrence.json`과 `storage-us4-newyork.json`, 기대 출력을 둔다(quickstart 2): 매일 완료 → 다음 날 06:00 뒤 `activate` → `todo`, 연속 기록 유지 / 하지 않은 채 하루 지남 → 0, 할 일 수 그대로 / 같은 날 `activate` 두 번 → 둘째 줄 `tasks`가 첫째와 같음 / 매주 수요일 / `set_day_start` 06:00 → 09:00(07:00에) → 이미 돈 오늘 리셋이 되돌려지지 않음 / `America/New_York` 3월 전환일을 넘는 매일 반복 〔단위 3〕

### Implementation (Green)

- [ ] T047 [US4] `Sources/MokaCore/TaskRules.swift`에 `RecurrenceReset.cycleStart(for:today:calendar:)`·`reset(_:now:dayStart:calendar:)`를 두고, 할 일 만들기·고치기에서 `cycle_day`를 채우는 경로(`insertTask(_:cycleDay:at:)` 호출 전)를 `NotchSession`·설정 창 공용 함수로 둔다. T045 PASS 〔단위 1〕
- [ ] T048 [US4] `Sources/MokaCore/Sim/SimRunner.swift`에 `activate`·`set_day_start`를 더한다("판정 결과로 노치가 빈 상태(초안 없음)면 R-104로 다시 고른다. 초안이 떠 있으면 그대로 둔다", research R11). T046 PASS 〔단위 3〕
- [ ] T049 [P] [US4] `Tests/MokaStoreTests/SimGRDBGoldenTests.swift`에서 `storage-*.json`을 `GRDBTaskRepository`(메모리 DB)로 한 번 더 돌려 같은 기대 출력과 바이트 비교한다(contracts "픽스처", P7). T013·T023 뒤 〔단위 3〕
- [ ] T050 🔒 [US4] `App/Sources/AppState.swift`에 활성화 판정을 잇는다(research R11): 앱 시작(T044의 복구 뒤), `NSWorkspace.didWakeNotification`, 노치 펼침(마우스 올림·클릭), 설정 창 열기에서 `RecurrenceReset.reset` → 바뀐 할 일 `apply` → 빈 상태면 고르기. `NSApplication.didBecomeActiveNotification`은 쓰지 않는다. 앱의 `Calendar`는 `Calendar(identifier: .gregorian)` + 시스템 시간대(ADR-0010). 사람 확인은 다음 날 아침 실제로 한 번(시스템 시계를 바꾸지 않는다) 〔단위 5〕

**확인 지점**: `swift test` PASS(메모리·GRDB golden 둘 다). SC-104는 시뮬레이터와 두 시간대 단위 시험으로

---

## Phase 7: User Story 5 - 컨텍스트와 첫 실행 온보딩 (Priority: P2)

**Goal**: 일정(컨텍스트) 탭, 온보딩 세 단계(TypeSafe 키 · 일정 한 건 · 기본값), 키는 Keychain에만

**Independent Test**: 단위 시험으로 온보딩 끝내기 규칙과 가짜 키 누출 없음. 화면은 quickstart 6 마지막 줄(새 사용자 계정), 키 단계는 quickstart 7

### Tests (Red)

- [ ] T051 [P] [US5] `Tests/MokaCoreTests/OnboardingTests.swift`에 온보딩 끝내기 시험을 쓰고 실패를 확인한다(data-model §6, research R8):
  - `FR-21 R-116`: "컨텍스트가 있으면 저장 → 세 설정 쓰기 → 마지막에 `onboarding_done = true`". 중간 실패(가짜 저장소가 throw)면 `onboarding_done`을 쓰지 않음
  - 값을 그대로 두면 기본 작업 시간 25, `default_extend_min` 10, `day_start` `06:00`
  - "키는 1단계 "다음"에서 `KeyStore.save`로만 저장하고 settings에는 아무것도 쓰지 않는다". 가짜 키 문자열이 settings 값·로그·체크포인트 어디에도 없음(메모리 저장소 전체를 훑음)
  - 키 없이 끝내도 할 일 추가·고르기가 됨(R-116 끝 문장)
  〔단위 1〕

### Implementation (Green)

- [ ] T052 [US5] `Sources/MokaCore/Onboarding.swift`에 `Onboarding.finish`를 둔다. T051 PASS 〔단위 1〕
- [ ] T053 🔒 [US5] `App/Sources/Keychain/KeychainKeyStore.swift`에 `KeyStore`를 구현한다(generic password, service `dev.dongwon.moka`, account `typesafe`, 앱 타깃만, 값 읽기 없음). 키 값을 print·`os.Logger`로 남기지 않는다. 접근성 속성과 data protection keychain 조건은 Apple 문서로 확인해 PR에 적는다(research R8 미확인). 확인 창 반복은 개인 팀 서명 빌드로 사람이 본다(ad-hoc으로는 확인 불가). 반복되면 키 단계만 마일스톤 3으로 미루고 기록한다(spec 위험 4) 〔단위 4〕
- [ ] T054 🔒 [US5] `App/Sources/Views/ContextTabView.swift`·`ContextFormView.swift`에 일정 탭을 만든다(시안 10번, R-115): 목록은 날짜순, 줄마다 이름·"11월 12일"·중요도 배지(아주=빨강 굵게, 꽤, 조금), 아래 `+`·`−`(−는 확인 없이 바로 지움), 안내 "시험·제출처럼 할 일 순서에 영향을 주는 일정이에요.". 새 일정 시트: 이름·날짜(날짜 고르기)·중요도 세그먼트 조금/꽤/아주(내용 폭, 칸 폭만큼 늘이지 않음), 셋 다 필수, 고치기 없음 〔단위 4〕
- [ ] T055 🔒 [US5] `App/Sources/Views/OnboardingView.swift`와 `App/Sources/MokaApp.swift`에 온보딩 창을 만든다(시안 11~13번, R-116, 폭 400pt, 창 제목 "Moka 시작하기", 단계 막대 1/3~3/3):
  - 1단계: "TypeSafe 키가 있나요?", "Moka가 할 일 순서를 추천할 때 써요. 지금 넣지 않아도 노치와 타이머는 다 돼요." + "키 발급받기 ↗"(TypeSafe 사이트를 기본 브라우저로, 외부 호출 아님), 가린 입력 칸, "키는 이 맥의 키체인에만 두고, 순서 추천을 켜기 전에는 쓰지 않아요.", 건너뛰기·다음(칸이 비면 꺼짐). 형식 검사 없음
  - 2단계: "다가오는 시험이나 제출이 있나요?", 이름(자리표시 "예: 중간고사")·날짜(오늘)·중요도(기본 조금), 이전·건너뛰기·다음(이름이 비면 꺼짐). 저장은 3단계에서 한꺼번에
  - 3단계: "이대로 시작할까요?", "언제든 설정에서 바꿀 수 있어요.", 기본 작업 시간·추가 시간·하루 시작 시각, 이전·시작하기 → `Onboarding.finish` → 창 닫힘 → 노치 빈 상태
  - 빨간 버튼으로 닫으면 끝내지 않은 것(다음 실행에 다시)
  - `showsOnboarding`(data-model §8)일 때만 연다. 시험·스냅샷은 `InMemoryKeyStore`
  〔단위 4〕

**확인 지점**: `swift test` PASS, 앱 빌드 PASS. SC-105는 사람이 새 사용자 계정에서

---

## Phase 8: Polish & Cross-Cutting

- [ ] T056 🔒 `App/Tests/MokaAppTests/ScreenStateSnapshotTests.swift`에 새 화면 상태 스냅샷을 라이트·다크로 더한다(ADR-0009, quickstart 5): 접힌 대기 할 일(C1-B)과 이어서 할 일 2초, 시간 고르기 + 이어서 할 일, 도는 중 + 세 버튼, 두 줄 입력(바꾸는 중·미루는 중), 시간 끝 + 두 줄, 설정 기본 탭, 할 일 탭(보기·정렬·다음·연속 배지), 할 일 시트(새로·매주·고치기·지우기 확인), 일정 탭과 시트, 온보딩 1~3단계. sanity 단언만(크기 0 아님, 단색 아님, 라이트≠다크). 출력은 `.verify/snapshots/002/`(커밋 안 함) 〔단위 4〕
- [ ] T057 🔒 모은 PNG를 `~/Dev/ai-platform/projects/moka/design/pr-<번호>/index.html`에 시안 `002-mockup.html` 같은 번호와 나란히 두고 PR "완료 증거"에 경로를 적는다(저장소 밖, 커밋 안 함) 〔단위 4〕
- [ ] T058 quickstart 3 오류 주입을 돌린다(커밋 안 함, 결과만 PR): 기대 출력 `elapsed_min` 바꿈 → golden FAIL(메모리·GRDB), `decisions_log.model_snapshot` 지움 → 스냅샷·pytest FAIL, 가짜 마이그레이션 등록 → 이름 시험 FAIL, `RecurrenceReset`의 `<`를 `!=`로 → 하루 시작 시각 변경 시험 FAIL, 고르기에서 `dropped` 제외 뺌 → R-104 FAIL, 메모리 `apply` 되돌림 뺌 → 계약 시험 FAIL 〔단위 1·2·3〕
- [ ] T059 단위 1·2·3·5 PR마다 quickstart 1~4 결과 표(PASS/FAIL/SKIP/NOT_RUN)와 기존 golden 변경 0줄 확인을 붙인다 〔단위 1·2·3·5〕
- [ ] T060 🔒 사람이 quickstart 5~7을 돌려 결과 표를 마지막 PR에 붙인다(SC-101 다시 켜기, SC-105 온보딩, Keychain 확인 창) 〔단위 4·5〕

---

## Dependencies & Execution Order

### Phase 순서

- Setup(1) → Foundational(2): 단위 1 몫(T003~T005·T009~T012)을 먼저 병합 → 단위 2(T006 GRDB·T007·T008·T013·T014)
- 단위 1의 이야기별 규칙(T015~T017·T020~T022, T029·T030·T032, T040·T042, T045·T047, T051·T052)은 단위 1 Issue 하나 또는 둘로 묶어 Foundational과 같이 간다(전부 MokaCore, 무인 가능)
- 단위 1 병합 뒤: 단위 3(시뮬레이터)과 단위 2를 병렬. 단위 2 병합 뒤 단위 5(앱 수명)와 T049(GRDB golden)
- 단위 4(화면)는 1·2·5 뒤. 단위 4 안에서는 US1(T025~T028) → US2(T034~T039) → US5(T053~T055) → Polish(T056·T057)

### 태스크 사이 의존

- T009 ← T003, T010 ← T004, T011 ← T005·T002, T012 ← T006·T009, T013 ← T006·T007·T012, T014 ← T008·T013
- T020 ← T015·T009, T021 ← T016·T010, T022 ← T017·T012·T020, T032 ← T029·T030·T022, T042 ← T040·T022, T047 ← T045·T010, T052 ← T051·T011·T012
- T023 ← T018·T019·T022, T024 ← T023, T033 ← T031·T032·T023, T043 ← T041·T042·T023, T048 ← T046·T047·T023, T049 ← T013·T048
- T044 ← T013·T042, T050 ← T044·T047
- T025·T026·T027·T028 ← T021·T022·T044, T035~T039 ← T032·T034·T044, T053~T055 ← T052, T056 ← T025~T055 화면, T057 ← T056
- Issue #52(spec 001 문구 셋)는 `Sources/MokaCore/NotchStatus.swift`(T034)와 `App/Sources/Views/ExpiredView.swift`(T037)를 같이 고친다. 단위 4 전에 병합하거나 단위 4에 묶는다

### 작업 단위 ↔ Issue (plan "작업 단위")

| 단위 | 태스크 | 무인 가능 | 먼저 할 일 |
|---|---|---|---|
| 1 MokaCore 값 타입·규칙 | T001·T002, T003~T005, T006(메모리), T009~T012, T015~T017, T020~T022, T029·T030·T032, T040·T042, T045·T047, T051·T052, T058·T059 일부 | 예 | 첫 Issue. 크면 1a(값 타입·하루 경계·저장 프로토콜: T001~T012)와 1b(규칙·세션: 나머지)로 나눈다 |
| 2 MokaStore v2 | T006(GRDB), T007·T008, T013·T014, T058·T059 일부 | 예(👁 스키마 스냅샷) | 1a 병합 뒤 |
| 3 `moka-sim` storage | T018·T019, T023·T024, T031·T033, T041·T043, T046·T048·T049, T058·T059 일부 | 예(👁 계약·픽스처) | 1 병합 뒤, T049만 2 병합 뒤 |
| 4 앱 화면 | T025~T028, T034~T039, T053~T057, T060 일부 | 아니오(사람 화면 확인) | 1·2·5 병합 뒤, #52와 순서 맞춤 |
| 5 앱 수명 연결 | T044, T050, T059·T060 일부 | 코드는 예, 확인은 사람 | 2 병합 뒤, 3과 병렬 |

### Parallel Opportunities

- T003·T004·T005·T006·T007·T008 동시(서로 다른 시험 파일)
- T015·T016·T017 동시, T029·T030·T031 동시, T040·T041, T045·T046
- 단위 1 병합 뒤 단위 2(`Sources/MokaStore`·`Tests/MokaStoreTests`·`schema/`·`tuning/`)와 단위 3(`Sources/MokaCore/Sim`·`Tests/MokaCoreTests/Fixtures/sim`)은 파일이 겹치지 않아 implementer 둘로 병렬
- 단위 4 안에서 T027·T028(할 일 탭)과 T054(일정 탭), T053(Keychain)은 겹치지 않는다

### Parallel Example: 단위 1 병합 뒤

```text
implementer A: "단위 2 — T006(GRDB 인자)·T007·T008·T013·T014 (MokaStore·Tests/MokaStoreTests·schema·tuning만)"
implementer B: "단위 3 — T018·T019·T023·T024·T031·T033·T041·T043·T046·T048 (MokaCore/Sim·Fixtures/sim·계약 원본만)"
```

---

## Implementation Strategy

### MVP First (US1 + US2 저장·버튼 경로)

1. 단위 1 → 단위 2: 할 일·체크포인트·로그가 저장되고 메모리·GRDB가 같은 계약을 지킨다
2. 단위 3(US1·US2 픽스처): 화면 없이 마일스톤 2 완료 조건 "완료/미루기/바꾸기가 로그에 쌓이고 체크포인트가 재진입 시 보인다"를 `moka-sim`으로 보인다
3. 단위 5 → 단위 4의 US1·US2 화면(T025~T028, T034~T039): 앱에서 같은 경로
4. US3(종료·잠자기) → US4(반복) → US5(일정·온보딩) → Polish
5. 일정이 밀리면(마일스톤 2는 11/3 하루) spec 위험 1대로 반복 리셋 연결(T050), 온보딩 키 단계(T053, T055 1단계), 종료·잠자기 연결(T044의 알림 몫)을 버퍼(11/8~9)로 넘기고 PR에 적는다

### 무인 실행 경계

- 밤에는 🔒 없는 태스크(MokaCore, MokaStore, `moka-sim`, pytest, 빌드)만 돈다. 🔒 태스크는 코드까지는 무인으로 쓸 수 있어도 사람 확인 전에는 끝난 것으로 보지 않는다
- 👁 태스크(T013 스키마 스냅샷, T018·T019·T023·T024·T031·T041·T046 계약·픽스처)는 PR "사람이 볼 결정"에 적는다

---

## R-ID ↔ 태스크

| R-ID / SC | 시험 | 구현 | 화면·사람 확인 |
|---|---|---|---|
| R-101 할 일 값·저장 | T003, T006, T007 | T009, T012, T013 | T028 |
| R-102 할 일 탭 | — | — | T026, T027, T028 |
| R-103 빠른 입력 저장 | T017, T019 | T022, T023 | T025 |
| R-104 노치 고르기 | T015, T017, T029 | T020, T022 | T025, T027("다음") |
| R-105 세 버튼 | T029 | T032 | T035, T037 |
| R-106 두 줄·돌아가기 | T029 | T032 | T036, T039 |
| R-107 시간 끝 두 줄 | T029, T031 | T032, T033 | T037 |
| R-108 체크포인트 | T003, T006, T007, T030 | T009, T032 | — |
| R-109 이어서 할 일 | T029, T030, T031 | T032 | T035, T038 |
| R-110 종료·잠자기 | T040, T041 | T042, T043 | T044 |
| R-111 재시작 복구 | T040, T041 | T042, T043 | T044 |
| R-112 행동 로그 | T006, T007, T029 | T032 | T039 |
| R-113 반복 리셋 | T045, T046 | T047, T048 | T050 |
| R-114 하루 경계 | T004 | T010 | T050 |
| R-115 컨텍스트 | T006, T007 | T012, T013 | T054 |
| R-116 온보딩 | T005, T051 | T011, T052 | T053, T055 |
| R-117 시뮬레이터 | T018, T019, T031, T041, T046, T049 | T023, T024, T033, T043, T048 | — |
| R-118 목록 보기·정렬 | T016 | T021 | T027 |
| SC-101 다시 켜도 남음 | T006, T007 | T013 | T044, T060 |
| SC-102 버튼 수 = 로그 수 | T029, T031 | T032, T033 | T039 |
| SC-103 이어서 할 일 재진입 | T019, T031, T041 | T033, T043 | T038, T060 |
| SC-104 반복 멱등 | T045, T046, T049 | T047, T048 | — |
| SC-105 온보딩 조작 3번 | T051 | T052 | T055, T060 |
| SC-106 실제 데이터 안 엶 | 공통 규칙, T051(가짜 키 누출) | T012(가짜 키), T023(DB 인자 없음) | T058 |
