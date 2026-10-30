---

description: "spec 002 저장과 체크포인트 작업 목록"
---

# Tasks: 저장과 체크포인트 (마일스톤 2)

**Input**: `specs/002-storage-checkpoint/`의 plan.md, spec.md(R-101~R-119), research.md(R1~R21), data-model.md, contracts/moka-sim-v1-additions.md, quickstart.md. 화면 시안 `~/Dev/ai-platform/projects/moka/design/002-mockup.html` v2(2026-10-30 사용자 확정, EGM 뒤 고침 포함, 저장소 밖)

**Tests**: 넣는다. 헌법 II(테스트 먼저)와 AGENTS.md "실패하는 테스트를 먼저 쓰고 실패를 확인한 뒤 구현한다"를 따른다. 테스트 태스크마다 Red 커밋 → 구현 태스크에서 Green 커밋.

**Organization**: 사용자 이야기(US1~US5)별로 묶는다. 각 태스크 끝의 `〔단위 N〕`은 plan "작업 단위" 번호이고 Issue 하나가 된다. 단위 1·3은 이야기마다 흩어져 있으니 Issue는 단위 번호로 모은다(아래 "작업 단위 ↔ Issue" 표).

**원본 규칙**: 규칙·값·모양은 data-model.md가 원본이다. 태스크는 절 번호(예: "data-model §5.3")를 가리키고 문장을 옮겨 적지 않는다. 시험은 그 절의 규칙과 "시험" 줄을 빠짐없이 덮는다.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 다른 파일을 고치고 아직 안 끝난 태스크에 기대지 않아 병렬로 할 수 있다
- **[Story]**: US1~US5(spec.md)
- **🔒**: 화면·앱 수명을 사람이 확인해야 끝난다(아래 "무인 실행 경계")
- **👁 사람이 볼 결정**: PR "사람이 볼 결정"에 올린다(스키마 스냅샷, `moka-sim` 계약, `scheduler_choice` 값)
- **시안 N**: `002-mockup.html`의 N번 화면
- 이 파일의 "확인 지점"은 Phase 완료 조건이다(GLOSSARY의 체크포인트와 다르다)

## 공통 규칙 (모든 태스크)

- 테스트 표시 이름은 `@Test("FR-07 R-108: …")`처럼 PRD FR과 R-ID로 시작한다(ADR-0003). R-ID와 FR: R-101·102·103·118 FR-01, R-104 FR-05, R-105 FR-06, R-106~R-111 FR-07, R-112 FR-11, R-113·R-114 FR-09, R-115 FR-02, R-116 FR-21, R-119 FR-11, 설정 키 FR-16. 시험이 R-ID를 덮으면 FR이 있는 R-ID를 쓴다(예: `FR-11 R-112:`). R-ID가 없는 ADR 결정 시험만 `ADR-0004:`, `ADR-0010:`, 시뮬레이터 계약 시험은 `ADR-0003 R-117:`로 시작한다. Swift Testing을 쓴다. 앱 스냅샷 번들만 XCTest.
- 타입·함수 이름과 모양은 data-model.md의 Swift 블록을 따른다. 거기 없는 작은 이름은 구현 PR에서 정하고 PR "가정"에 적는다.
- 시각은 주입한 값(`now`·`at`, 앱은 `MokaClock`)과 `GregorianCalendar.make(timeZone:)` + 고정 `Asia/Seoul`·`America/New_York`으로 시험한다. MokaCore에서 `Date()`, `TimeZone.current`, `Calendar.current`를 읽지 않는다. 실제 시간을 기다리지 않는다.
- 가짜 할 일만 쓴다(예: "가짜 할 일 A"). 실제 앱 DB 경로(`~/Library/Application Support/dev.dongwon.moka/`)와 실제 decision API(TypeSafe Jev, OpenRouter)를 테스트·`moka-sim`·무인 실행에서 열거나 부르지 않는다(SC-106, ADR-0006). `eraseDatabaseOnSchemaChange`를 켜지 않는다.
- `Package.swift`를 바꾸지 않는다. 새 의존성을 두지 않는다. 새 파일은 기존 타깃 폴더에 둔다(plan "Structure Decision"). `NotchTimer`와 기존 golden 기대 출력은 바꾸지 않는다. 이 전제가 깨지면 멈추고 PR "사람이 볼 결정"에 올린다.
- MokaStore 시험은 GRDB를 `TestDatabase.migratedInMemory()`로만 연다(기존 `TestDatabaseUsageTests` 가드). 저장소를 `@Test(arguments:)`로 넘길 때는 `StoreKind`(data-model §3)를 넘기고 시험 안에서 만든다. `@unchecked Sendable`을 쓰지 않는다.
- 로그(`os.Logger`)·`moka-sim` 출력에 할 일 제목, 체크포인트 두 줄 본문, 컨텍스트 이름을 남기지 않는다.
- 화면 문구는 고객용 해요체이고 시안 v2 글자를 그대로 쓴다. 화면 이름은 GLOSSARY(일정, 중요도 조금/꽤/아주, 이어서 할 일, 추가 시간, 시작 전, 다른 할 일). 끼워 넣는 값(제목, 요일, 분)은 코드가 채우고, 제목 뒤 조사는 받침에 맞춘다(을/를). 코드·스키마 이름은 그대로다.
- 검증 명령: `swift test`, `cd tuning && python3 -m pytest`, 앱은 `xcodegen generate && xcodebuild build -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`. 결과는 PASS/FAIL/SKIP/NOT_RUN.

---

## Phase 1: Setup

**Purpose**: 기준 상태와 상수 자리

- [ ] T001 기준 상태 확인: `swift test`, `cd tuning && python3 -m pytest`, 앱 빌드를 돌려 기존 시험이 PASS인지 기록한다(원래 실패와 새 회귀 구분). 기존 golden(`Tests/MokaCoreTests/Fixtures/sim/*.expected.jsonl`)의 해시를 PR "완료 증거"에 적어 둔다(contracts "원칙") 〔단위 1〕
- [ ] T002 [P] `Sources/MokaCore/Defaults.swift`에 data-model §6의 초기값 상수(`extendMin`, `extendMinRange`, `dayStart`)를 더한다. 기존 상수는 그대로 〔단위 1〕

---

## Phase 2: Foundational (모든 이야기가 기대는 것)

**Purpose**: 값 타입, 시각·날짜 문자열, 하루 경계, 저장 프로토콜·메모리 구현(단위 1a), v2 마이그레이션·GRDB 구현(단위 2)

**순서**: 단위 1a(T003~T007의 시험과 T010~T014)가 병합되기 전에는 단위 2의 구현(T015·T016)을 병합하지 않는다. 단위 2의 Red 시험(T008·T009)은 미리 써도 된다.

### Tests (Red)

- [ ] T003 [P] `Tests/MokaCoreTests/ValueTypeTests.swift`에 값 타입·값 검증 시험을 쓰고 실패를 확인한다: data-model §2(`Weekday`, `LocalDay`, `DayStart`, `TaskEdit`, 열거형 `rawValue` 전부 — `SchedulerChoice.rotateByIDV0` = `"rotate_by_id_v0"` 포함)와 §5.6 표 〔단위 1〕
- [ ] T004 [P] `Tests/MokaCoreTests/DayBoundaryTests.swift`에 하루 경계 시험을 쓰고 실패를 확인한다: data-model §5.4의 경계값·전환일·단조성 시험, `start(of:)`와 `day(containing:)` 왕복, §2.2 `GregorianCalendar.make(timeZone:)`. 같은 파일에 ADR-0010 결정 검증 시험 둘을 둔다: (1) 같은 순간을 시간대만 바꿔 넣으면 판정이 새 시간대를 따르는지(시간대를 한 번 넘겨 두는 방식과 판정마다 새로 만드는 방식 비교), (2) `make`가 늘 그레고리력을 돌려주는지(`LocalDay` 텍스트가 바뀌지 않음) 〔단위 1〕
- [ ] T005 [P] `Tests/MokaCoreTests/UTCTimestampTests.swift`에 data-model §2.1 시험을 쓰고 실패를 확인한다: `format`(초 아래 버림)·`parse`(형식 밖 nil)·`floorToSecond` 왕복, 윤년·월말 날짜 〔단위 1〕
- [ ] T006 [P] `Tests/MokaCoreTests/CoreSettingsTests.swift`에 data-model §6 읽기·쓰기 규칙 시험을 쓰고 실패를 확인한다(`FR-16`): 세 키의 읽기 규칙, `"TRUE"`·`"1"`은 온보딩을 보임, 틀린 값 쓰기는 이전 값 유지, 저장소가 throw하면 읽기 기본값 〔단위 1〕
- [ ] T007 [P] `Tests/MokaStoreTests/StorageContractTests.swift`에 공용 계약 시험을 `@Test(arguments: StoreKind.allCases)`로 쓰고 실패를 확인한다. data-model §3 "공용 계약 시험" 항목 전부(초 아래 시각 왕복, 묶음 셋 이상 뒤 id 순서·값 포함). 이 태스크에서는 `StoreKind.memory`만 통과 대상이고 `.grdb`는 T015에서 켠다 〔단위 1·2〕
- [ ] T008 [P] 👁 `Tests/MokaStoreTests/MigrationTests.swift`의 이름 시험 리터럴과 `schema/moka-schema.sql`을 data-model §7대로 먼저 고쳐 스냅샷·이름 시험이 실패하는지 확인한다(§7 "Red 단계"). `Tests/MokaStoreTests/StoreConstraintTests.swift`에 GRDB 전용 시험을 쓴다: §7 CHECK 칸 전부의 허용·거부(원시 SQL), `ON DELETE RESTRICT`(외래 키가 켜져 있는지 확인), 모르는 `user_action`·`scheduler_choice` 읽기 → `StoreError.unknownValue`. 첫 실행은 리눅스 CI에서도(`trigger` 열 이름, plan 위험 6) 〔단위 2〕
- [ ] T009 [P] `tuning/tests/test_schema_contract.py`를 research R16 범위로 쓰고 실패를 확인한다(`decisions_log` 열 이름 집합, 판단 칸 CHECK 허용·거부만). 표준 라이브러리만 〔단위 2〕

### Implementation (Green)

- [ ] T010 `Sources/MokaCore/`에 data-model §2 값 타입과 §5.6 값 검증을 둔다: `TaskModel.swift`, `ContextModel.swift`, `CheckpointModel.swift`, `DecisionLog.swift`(파일 배치는 plan "Source Code"). T003 PASS 〔단위 1〕
- [ ] T011 `Sources/MokaCore/UTCTimestamp.swift`에 `UTCTimestamp`와 내부 `GregorianCivil`을 두고, `Sources/MokaCore/Sim/SimScenario.swift`의 `SimTimestamp`가 `GregorianCivil`을 쓰게 옮긴다(data-model §2.1). T005 PASS, 기존 golden 변경 0줄(quickstart 1 명령) 〔단위 1〕
- [ ] T012 `Sources/MokaCore/LocalDay.swift`에 `LocalDay`, `DayStart`, `DayBoundary`, `GregorianCalendar`를 구현한다(data-model §2·§2.2·§5.4). T004 PASS. 리눅스 컨테이너(quickstart 1의 `docker run`)에서도 PASS인지 PR에 적는다(plan 위험 6). ADR-0010 결정 검증 결과(어느 방식을 골랐는지, 시험 이름)를 `adr/ADR-0010-day-boundary-calendar.md` 끝에 덧붙인다 〔단위 1〕
- [ ] T013 `Sources/MokaCore/CoreSettings.swift`에 data-model §6 규칙을 둔다. 기존 `QuantumSettings.swift`는 바꾸지 않는다. T006 PASS 〔단위 1〕
- [ ] T014 `Sources/MokaCore/Storage.swift`에 data-model §3의 `StoreError`, `StoreBatch`, `TaskRepository`, `ContextStore`, `InMemoryTaskRepository`, `InMemoryContextStore`를 둔다(시각 내림, 되돌림 포함). T007(`.memory`) PASS 〔단위 1〕
- [ ] T015 👁 `Sources/MokaStore/Migrations.swift`에 data-model §7 마이그레이션을 등록하고 `Sources/MokaStore/GRDBTaskRepository.swift`·`GRDBContextStore.swift`를 구현한다(시각·날짜는 `UTCTimestamp`·`LocalDay`만, 열거 값은 `rawValue`, `apply`는 `write` 한 트랜잭션). T007에 `.grdb`를 켜고 T007·T008 PASS. 스냅샷 시험 출력과 `schema/moka-schema.sql`이 바이트로 같은지 확인한다(ADR-0004). 스냅샷 변경은 PR "사람이 볼 결정" 〔단위 2〕
- [ ] T016 T009 PASS 확인(`cd tuning && python3 -m pytest`). T015의 스냅샷만으로 통과해야 한다 〔단위 2〕

**확인 지점**: `swift test`·pytest PASS. 메모리·GRDB 두 저장소가 같은 계약을 통과한다(SC-101의 저장 몫)

---

## Phase 3: User Story 1 - 할 일이 저장되고 노치가 다음 차례 할 일을 띄운다 (Priority: P1) 🎯 MVP

**Goal**: 할 일을 노치·설정 창에서 넣고 고치고 지운다. 앱을 다시 켜도 남는다. 노치는 id 순환으로 할 일을 띄우고, 시작 전 화면에서 "다른 할 일"로 넘긴다. 할 일 탭에서 보기·정렬을 고른다

**Independent Test**: 화면 없이 `swift run moka-sim run Tests/MokaCoreTests/Fixtures/sim/storage-us1-pick.json`이 할 일 셋 추가 → `relaunch` → `notch_task` 1, 시작·바꾸기 반복 → 1 → 2 → 3 → 1을 출력한다. 화면은 quickstart 6 첫째~넷째·아홉째 줄

### Tests (Red)

- [ ] T017 [P] [US1] `Tests/MokaCoreTests/TaskRulesTests.swift`에 `RotateByIDRule` 시험을 쓰고 실패를 확인한다(data-model §5.1 규칙 넷과 "시험" 줄 전부, `FR-05 R-104`) 〔단위 1〕
- [ ] T018 [P] [US1] `Tests/MokaCoreTests/TaskWriteRulesTests.swift`에 `TaskWriteRules` 시험을 쓰고 실패를 확인한다(data-model §5.8, `FR-01 R-101`·`FR-09 R-113`): `prepareNew`의 검증·요일 채움(하루 시작 06:00에 05:00 등록 → 전날 요일)·`cycleDay`, `applyEdit`의 반복·요일 규칙 다섯 줄 전부, 같은 값을 다시 주면 그대로, `dropped`는 nil, `done`은 고칠 수 있음 〔단위 1〕
- [ ] T019 [P] [US1] `Tests/MokaCoreTests/TaskListViewTests.swift`에 목록 보기 시험을 쓰고 실패를 확인한다(data-model §5.7 규칙과 경계값 전부, `FR-01 R-118`) 〔단위 1〕
- [ ] T020 [P] [US1] `Tests/MokaCoreTests/NotchSessionTests.swift`에 세션 시험(할 일 연결 몫)을 쓰고 실패를 확인한다(data-model §4.2, `FR-01 R-103`·`FR-05 R-104`): 표의 고르기·빠른 입력(빈 상태·초안)·다른 할 일·시작(`run` 채움)·지움·고침 칸과 "거부" 칸마다 하나(`SessionError.notAllowed`), 커서 수명 표 가운데 이 동작들의 줄, 고침은 제목 사본만 바뀌고 시간 값이 그대로(초안·도는 중·시간 끝), `nextMark` 세 경우, 초안의 칩은 그 순간의 기본값 〔단위 1〕
- [ ] T021 [P] [US1] 👁 `Tests/MokaCoreTests/SimScenarioTests.swift`에 storage 모드 디코딩 오류 시험을 더한다(contracts "오류 덧붙임" 종료 코드 2 줄 전부). 픽스처는 `Tests/MokaCoreTests/Fixtures/sim/errors/storage-<이름>.json`, 기대 오류 종류(`SimErrorKind`, 새 경우 포함)는 시험 코드 표에 먼저 적는다 〔단위 3〕
- [ ] T022 [P] [US1] 👁 `Tests/MokaCoreTests/Fixtures/sim/`에 storage golden 둘을 둔다(`SimGoldenTests`가 같은 이름 `.expected.jsonl`을 요구): `storage-contract-example.json`(contracts 입력 예시와 출력 아홉 줄 그대로)과 `storage-us1-pick.json`(`add_task` 셋 → `relaunch` → `notch_task` 1, 시작·바꾸기 반복 → 1 → 2 → 3 → 1, 초안에서 `enter_title` → 새 할 일이 초안). 기존 golden 파일은 고치지 않는다 〔단위 3〕

### Implementation (Green)

- [ ] T023 [US1] `Sources/MokaCore/TaskRules.swift`에 `RotateByIDRule`과 `TaskWriteRules`를 둔다(data-model §5.1·§5.8). T017·T018 PASS 〔단위 1〕
- [ ] T024 [US1] `Sources/MokaCore/TaskListView.swift`에 data-model §5.7 타입과 함수를 둔다. T019 PASS 〔단위 1〕
- [ ] T025 [US1] `Sources/MokaCore/NotchSession.swift`에 `NotchSession`, `RunInfo`, `SessionInput`, `SessionStep`, `SessionError`와 고르기·빠른 입력·다른 할 일·시작·지움·고침·`nextMark`를 둔다(data-model §4.2, `NotchTimer`는 바꾸지 않음). T020 PASS 〔단위 1〕
- [ ] T026 [US1] 👁 `Sources/MokaCore/Sim/`에 storage 모드를 더한다(contracts 전체): `SimScenario.swift`(`storage`, `settings.day_start`, 새 이벤트 여섯과 기존 `start`·`complete`의 두 줄 필드 디코딩), `SimRunner.swift`(메모리 저장소, 앱과 같은 MokaCore 함수만, 단계 × 이벤트 표, 꺼짐 단계, 쓰기는 `SessionCommit`), `SimOutput.swift`(덧붙임 키 다섯, 직접 조립), 불변식 검사(종료 코드 1 줄 전부). 이 태스크는 US1 이벤트(`add_task`·`enter_title`·`start`·`relaunch`)와 출력 형식까지. T021(US1 몫)·T022 PASS, 기존 golden 변경 0줄(quickstart 1 명령) 〔단위 3〕
- [ ] T027 [US1] 👁 `specs/001-notch-timer/contracts/moka-sim-v1.md`에 contracts/moka-sim-v1-additions.md 내용을 옮긴다. PR "사람이 볼 결정"에 계약 변경과 `scheduler_choice` 값 `rotate_by_id_v0`을 올린다 〔단위 3〕
- [ ] T028 🔒 [US1] 노치 화면을 고친다(시안 1·2번, ADR-0009 뷰는 값과 콜백만):
  - `App/Sources/Views/CollapsedView.swift`: 초안은 회색 점 + 회색 제목(C1-B, 시간 없음, 왼쪽 104pt, 길면 …). 빈 상태와 도는 중은 spec 001 그대로
  - `App/Sources/Views/ExpandedView.swift`: 시작 전 화면은 제목이 채워져 있고 제목 입력을 건너뛴다. 칩 아래 줄 왼쪽에 고스트 버튼 "다른 할 일"(세션 `nextDraft`)과 "+ 새 할 일"(누르면 제목 칸이 열리고 Enter로 빠른 입력, R-103), 오른쪽 "시작 ↵"(Enter는 늘 시작). 빈 상태의 새 할 일 입력은 그대로(시안 2번 메모)
  - `App/Sources/Views/NotchLayout.swift`: `collapsedSideWidths`에서 초안 왼쪽 폭 28 → 104pt, `panelSize` 높이를 가장 긴 판(시간 끝 + 두 줄)에 맞춤
  - `App/Sources/Views/NotchContentView.swift`·`App/Sources/Notch/NotchPanelHost.swift`(`NotchPanelRoot`): 새 값·콜백 전달(plan "앱 연결")
  - `App/Tests/MokaAppTests/ScreenStateSnapshotTests.swift`: 바뀐 `NotchContentView` 호출부를 고쳐 컴파일되게 한다(새 스냅샷은 T060)
  〔단위 4〕
- [ ] T029 🔒 [US1] `App/Sources/Settings/SettingsView.swift`를 탭 셋(기본·할 일·일정) 틀로 바꾸고, 기본 탭 내용은 `App/Sources/Views/BasicTabView.swift`(값·콜백만)로 둔다(시안 6번, 폭 460pt, 창 제목은 탭 이름, 001의 로고 줄은 뺌). 기본 탭: 기본 작업 시간(기존), 추가 시간(`default_extend_min`, 숫자 칸 + 스테퍼, 1~180, 해석·이유 안내는 `QuantumChip.parseCustom`·`customIssue` 재사용, 안내 "시간이 끝났을 때 더 이어 갈 시간이에요."), 하루 시작 시각(`day_start`, 시·분 `DatePicker`(.hourAndMinute), 안내 "이 시각이 지나면 반복 할 일이 다시 대기로 돌아와요."). 메뉴 막대 항목은 spec 001 R-012 그대로 〔단위 4〕
- [ ] T030 🔒 [US1] `App/Sources/Views/TaskListTabView.swift`에 할 일 탭을 만든다(시안 7번, R-102·R-118, 값·콜백만):
  - 위 줄: 보기 `[전체 · 오늘 · 이번 주]` 세그먼트, 오른쪽 정렬 메뉴 `만든 순 ▾ / 마감 순`(처음 값 `all`·`created`, data-model §8)
  - 줄: 제목, 보조 줄(마감 "마감 11월 5일", 예상 "예상 50분", 반복 "매일"/"매주 수요일", "N번 미뤘어요"), 상태 배지(대기 / 진행 중(모카색) / 완료), 완료는 줄 긋고 흐리게. 반복 할 일의 `streak > 0`이면 잔 아이콘이 든 모카색 배지 — 매일은 "N일 연속 진행", 매주는 "N주 연속 진행"(0이면 배지 없음)
  - "다음" 표시: `nextMark`(data-model §4.2) 할 일에만
  - 아래: `+`(새 할 일 시트) `−`(고른 할 일 지우기 확인), 안내 "두 번 클릭하면 고쳐요. **다음** 표시가 붙은 할 일이 노치에 떠요."
  - 버린 할 일은 보이지 않는다. 검색 없음
  〔단위 4〕
- [ ] T031 🔒 [US1] `App/Sources/Views/TaskFormView.swift`에 할 일 시트를 만든다(시안 8·9번, R-101·R-102, 값 검증은 `TaskWriteRules`):
  - 새로 만들기: 제목(자리표시 "무엇을 할까요?", 비면 저장 꺼짐 + 왼쪽 아래 "제목을 넣어 주세요."), 마감(체크 "마감 있음" + 날짜 고르기), 반복 세그먼트 없음/매일/매주(내용 폭), 매주면 요일 줄 일~토(하나만, 기본은 등록 순간이 속한 하루의 요일, 안내 "오늘(<요일>)이 먼저 골라져 있어요. 하나만 고를 수 있어요."), 예상 소요(비워도 됨, 1 이상 정수가 아니면 "1분 이상으로 넣어 주세요."), 취소·저장
  - 고치기(줄 두 번 클릭): 같은 칸 + "이어서 할 일"은 읽기만(안내 "멈출 때 적어 둔 줄이에요."), 왼쪽 "지우기…"
  - 지우기 확인 시트: 제목 `"<제목>"을/를 지울까요?`(받침에 맞춤), 본문 "지우면 노치에 다시 뜨지 않아요. 지금까지 남긴 기록은 그대로 둬요."(도는 할 일이면 앞에 "지금 타이머가 도는 할 일이에요. 지우면 타이머가 멈추고"), 취소·지우기(빨강). 지우면 `dropped`(research R4)
  - 노치의 할 일을 고치면 세션 `edited`로 노치에 바로 보이고 타이머는 그대로
  〔단위 4〕

**확인 지점**: `swift test` PASS, storage golden PASS, 기존 golden 변경 0줄, 앱 빌드 PASS. 화면은 사람이 quickstart 6으로

---

## Phase 4: User Story 2 - 완료·미루기·바꾸기와 체크포인트 (Priority: P1) 🎯 MVP

**Goal**: 도는 중·시간 끝에서 세 버튼, 두 줄 입력(돌아가기·안 적기·등록), 체크포인트와 로그 한 줄, 이어서 할 일 표시, 쓰기 실패 때 세션 유지

**Independent Test**: `moka-sim` `storage-us2-buttons.json`이 바꾸기 → 다른 할 일, 미루기 `skip_count` 1, 시간 끝의 네 동작(완료·미루기·바꾸기·다시 시작) → 계기 `quantum`, 칩 45분 시간 끝 → `elapsed_min` 45, 버튼마다 `decision` 한 줄을 출력한다. 화면은 quickstart 6 다섯째~일곱째 줄

### Tests (Red)

- [ ] T032 [P] [US2] `Tests/MokaCoreTests/NotchSessionTests.swift`에 버튼 시험을 더하고 실패를 확인한다(data-model §4.1 표와 그 아래 줄, §4.2 표의 버튼 칸·커서 수명·경과 분 줄, `FR-06 R-105`·`FR-07 R-106`·`R-107`·`R-109`·`FR-11 R-112`): 칩 45분·기본값 25분 시간 끝 → `elapsed_min` 45, 로그 `schedulerChoice` = `rotate_by_id_v0`, 하루 시작을 넘겨 끝낸 매일 반복 할 일(§4.1 예) 〔단위 1〕
- [ ] T033 [P] [US2] `Tests/MokaCoreTests/CheckpointRulesTests.swift`에 data-model §5.5 시험을 쓰고 실패를 확인한다(`FR-07 R-108`·`R-109`): 경과 분 자름, 시계를 되돌린 `now`는 0, `showsInCollapsed`의 1.999초 참·2초 거짓·음수 거짓 〔단위 1〕
- [ ] T034 [P] [US2] `Tests/MokaCoreTests/NotchStatusTests.swift`에 `NotchStatus.label(for:pending:)` 시험을 더하고 실패를 확인한다(`FR-07 R-106`): `pending` nil이면 지금 출력 그대로, `.switch` → "바꾸는 중", `.skip` → "미루는 중"(시안 4번) 〔단위 1〕
- [ ] T035 [P] [US2] `Tests/MokaCoreTests/SessionCommitTests.swift`에 `SessionCommit.commit` 시험을 쓰고 실패를 확인한다(data-model §4.2, `FR-11 R-119`): `apply`가 throw하는 가짜 저장소면 같은 오류를 던지고 저장소에 아무것도 남지 않음, 성공하면 `step.session` 〔단위 1〕
- [ ] T036 [P] [US2] 👁 `Tests/MokaCoreTests/Fixtures/sim/storage-us2-buttons.json`과 기대 출력을 둔다(quickstart 2의 버튼 항목: 하나뿐일 때 미루기, 시간 끝 네 동작, 칩 45분 시간 끝, 두 줄 비움) 〔단위 3〕

### Implementation (Green)

- [ ] T037 [US2] `Sources/MokaCore/NotchSession.swift`에 완료·미루기·바꾸기·다시 시작·`SessionCommit`을, `Sources/MokaCore/CheckpointModel.swift`에 `Checkpoint.elapsedMinutes`·`FirstActionDisplay.showsInCollapsed`를 둔다(data-model §4.2·§5.5). T032·T033·T035 PASS 〔단위 1〕
- [ ] T038 [US2] `Sources/MokaCore/NotchStatus.swift`에 `pending: PendingAction? = nil` 매개변수를 더한다(기존 호출부·시험은 그대로 통과). T034 PASS. Issue #52가 같은 파일의 다른 문구를 바꾸므로 먼저 병합된 쪽에 맞춘다 〔단위 1〕
- [ ] T039 [US2] `Sources/MokaCore/Sim/SimRunner.swift`에 `skip`·`switch`와 `start`·`complete`의 두 줄 필드를 더한다(contracts). T021(US2 몫)·T036 PASS 〔단위 3〕
- [ ] T040 🔒 [US2] `App/Sources/Views/ExpandedView.swift`에 도는 중 화면을 고친다(시안 3번): 제목 아래 "이어서 할 일 <첫 행동>" 한 줄(있을 때만, 크레마색, 길면 …), 남은 시간 오른쪽에 미루기·바꾸기·완료(같은 무게). 시작 전 화면(시안 2번)에도 같은 줄 〔단위 4〕
- [ ] T041 🔒 [US2] `App/Sources/Views/CheckpointNotesView.swift`에 두 줄 입력 화면을 만든다(시안 4번, R-106, 키 규칙은 data-model §8):
  - 오른쪽 위 상태 `NotchStatus.label(for:pending:)`("바꾸는 중"/"미루는 중"), 제목 줄 오른쪽 "N분 했어요"(지금까지의 경과)
  - 라벨 "어디까지 했어요?" + 칸, 라벨 "다음엔 뭐부터 할까요?" + 칸(자리표시 "비워 둬도 돼요")
  - 아래 줄: 왼쪽 "돌아가기 esc", 오른쪽 "안 적기", "등록 ↵"
  - 첫 칸 자동 포커스는 `OneShotRequest`로 한 번만
  〔단위 4〕
- [ ] T042 🔒 [US2] `App/Sources/Views/ExpiredView.swift`를 고친다(시안 5번, R-107): 제목 + 빨간 0:00, 라벨 둘과 두 칸, 시간 칩 줄(spec 001 그대로), 아래 줄 왼쪽 미루기·바꾸기, 오른쪽 다시 시작·완료 ↵. Enter 규칙은 data-model §8 마지막 줄(둘째 칸 Enter는 아무 동작 없음). 키보드 포커스를 가져가지 않는 규칙은 spec 001 그대로. Issue #52(다시 시작 → "N분 더")가 같은 파일을 고친다: 먼저 병합된 쪽에 맞춘다 〔단위 4〕
- [ ] T043 🔒 [US2] `App/Sources/Views/CollapsedView.swift`에 이어서 할 일 2초 표시를 더한다(시안 1번 아래 줄, R-109): `showsInCollapsed`가 참인 동안 왼쪽 104pt에 "이어서 · <첫 행동>"(크레마색, 길면 …), 그 뒤 C1-B. 다시 그리기는 plan "앱 연결"의 일회성 타이머 〔단위 4〕
- [ ] T044 🔒 [US2] `App/Sources/AppState.swift`에 버튼과 두 줄 입력을 잇는다(plan "앱 연결", data-model §8): 미루기·바꾸기 → `pendingAction`, 등록·안 적기·완료·다시 시작·다른 할 일 → 세션 함수 → `SessionCommit` → `tasks()` 다시 읽기 → 빈 상태면 고르기 → `pickedAt`. 두 줄 입력 중 시간 끝이면 `pendingAction` nil. 쓰기가 throw하면 세션·`tasks`를 바꾸지 않고 오류 종류만 로그 〔단위 4〕

**확인 지점**: `swift test` PASS, us2 golden PASS, 앱 빌드 PASS. SC-102·SC-103은 시뮬레이터와 단위 시험으로, 화면은 사람이 quickstart 6

---

## Phase 5: User Story 3 - 앱을 끄거나 맥이 잠들어도 이어서 시작한다 (Priority: P1)

**Goal**: `AppState` 세션 전환과 DB 열기(R-119 실패 처리 포함), 종료·잠자기 체크포인트, 켤 때 복구, 이어서 할 일과 함께 대기 할 일을 띄움

**Independent Test**: `moka-sim` `storage-us3-lifecycle.json`이 `quit` 뒤 `relaunch` → 대기 + `has_first_action` true, `quit` 없이 `relaunch` → `active`가 `todo`를 출력한다. 잠자기는 단위 시험. 화면은 quickstart 7

### Tests (Red)

- [ ] T045 [P] [US3] `Tests/MokaCoreTests/TaskRulesTests.swift`에 복구·종료·잠자기 시험을 더하고 실패를 확인한다(`FR-07 R-110`·`R-111`): data-model §5.2, §4.2 `lifecycleCheckpoint`(running만, 계기 `sleep`/`quit`, 빈 두 줄, 경과 분, 할 일 상태와 타이머 그대로, `expired`·빈 상태는 nil) 〔단위 1〕
- [ ] T046 [P] [US3] 👁 `Tests/MokaCoreTests/Fixtures/sim/storage-us3-lifecycle.json`과 기대 출력, `errors/storage-start-after-quit.json`을 둔다(quickstart 2의 `quit`·`relaunch` 항목) 〔단위 3〕

### Implementation (Green)

- [ ] T047 [US3] `Sources/MokaCore/TaskRules.swift`에 `LaunchRecovery.revert`, `Sources/MokaCore/NotchSession.swift`에 `lifecycleCheckpoint`를 둔다. T045 PASS 〔단위 1〕
- [ ] T048 [US3] `Sources/MokaCore/Sim/SimRunner.swift`에 `quit`·`relaunch`를 더한다(contracts "시작"). T046 PASS 〔단위 3〕
- [ ] T049 🔒 [US3] `App/Sources/AppState.swift`·`App/Sources/MokaApp.swift`에서 `AppState.timer`를 `session`(data-model §8)으로 바꾸고 저장소를 잇는다:
  - `AppSettings.openStore()`(기존, `App/Sources/MokaApp.swift`)가 DB를 한 번 열어 `GRDBSettingsStore`·`GRDBTaskRepository`·`GRDBContextStore`에 나눠 준다. 시험 쪽 경로 가드는 `Tests/MokaStoreTests/Support/TestDatabase.swift`에만 있고 앱 경로에는 없다(그대로 둔다)
  - R-119: 열기·마이그레이션이 실패하면 설정만 `InMemorySettingsStore`로 대체하고, 할 일·일정 저장소는 만들지 않으며 `storageUnavailable` = true. DB 파일을 지우거나 새로 만들거나 옮기지 않는다. 오류 종류만 로그
  - 시작 때 `LaunchRecovery` → 하루 판정(자리만 두고 T057에서 채움) → 고르기
  - 빠른 입력(`enterTitle`)은 `TaskWriteRules.prepareNew` → `insertTask` → `addedTask`, 시작은 세션 `start` → `SessionCommit`
  - 기존 `send(_:)`, `isPinnedOpen`, `customText`의 동작은 세션 위에서 그대로
  〔단위 5〕
- [ ] T050 🔒 [US3] `App/Sources/MokaApp.swift`·`App/Sources/AppState.swift`에 종료·잠자기를 잇는다(research R12): `NSApplication.willTerminateNotification`과 `NSWorkspace.willSleepNotification`(`queue: .main` + `MainActor.assumeIsolated`)에서 `lifecycleCheckpoint` → 동기 `apply`, `applicationShouldTerminate`로 종료를 미루지 않음. 사람 확인(quickstart 7): 메뉴 "종료" → 다시 켬 → 대기 + 이어서 할 일, 강제 종료 → 대기. 로그아웃·시스템 종료 기록은 미확인(실제 DB 조회만 가능하면 NOT_RUN) 〔단위 5〕
- [ ] T051 🔒 [US3] `App/Sources/Views/StorageUnavailableView.swift`에 저장할 수 없을 때의 노치 빈 상태 안내를 만든다(R-119, 해요체, 메뉴 막대 항목 없음). 문구 초안: "할 일을 저장할 수 없어요. 지금은 타이머만 쓸 수 있어요." — 시안에 없으므로 PR "사람이 볼 결정"에 문구를 올린다 〔단위 4〕

**확인 지점**: `swift test` PASS, us3 golden PASS. 앱 수명은 사람이 quickstart 7

---

## Phase 6: User Story 4 - 반복 할 일은 늘 하나다 (Priority: P2)

**Goal**: 매일·매주 반복이 하루 경계 뒤 첫 활성화에서 같은 한 건으로 대기로 돌아온다

**Independent Test**: `moka-sim` `storage-us4-recurrence.json`이 매일 완료 → 다음 날 06:00 뒤 `activate` → `todo`, 연속 기록 유지, 같은 하루 `activate` 두 번 → 같은 `tasks`를 출력한다

### Tests (Red)

- [ ] T052 [P] [US4] `Tests/MokaCoreTests/RecurrenceResetTests.swift`에 반복 리셋 시험을 쓰고 실패를 확인한다(data-model §5.3 전부와 §4.1의 넘겨 끝낸 예, `FR-09 R-113`): 매주 수요일은 목~화 그대로·다음 수요일 06:00 뒤 `todo`, 하루 시작 시각을 바꿔 오늘이 앞 하루로 돌아가도 되돌리지 않음, 두 시간대 〔단위 1〕
- [ ] T053 [P] [US4] 👁 `Tests/MokaCoreTests/Fixtures/sim/storage-us4-recurrence.json`과 `storage-us4-newyork.json`, 기대 출력을 둔다(quickstart 2의 반복 항목: 매일 완료·놓침·같은 하루 두 번·05:50 → 06:10, 매주 수요일, `America/New_York` 3월 전환일) 〔단위 3〕

### Implementation (Green)

- [ ] T054 [US4] `Sources/MokaCore/TaskRules.swift`에 `RecurrenceReset`을 둔다(data-model §5.3). T052 PASS 〔단위 1〕
- [ ] T055 [US4] `Sources/MokaCore/Sim/SimRunner.swift`에 `activate`를 더한다(판정 → 빈 상태면 고르기, research R11). T053 PASS 〔단위 3〕
- [ ] T056 [P] [US4] `Tests/MokaCoreTests/Fixtures/sim/errors/`의 storage 오류 픽스처가 contracts "오류 덧붙임" 종료 코드 2 줄을 모두 하나 이상 갖는지 `everyErrorFixtureIsListed`(기존)로 확인하고 빠진 것을 채운다 〔단위 3〕
- [ ] T057 🔒 [US4] `App/Sources/AppState.swift`에 활성화 판정을 잇는다(research R11, plan "앱 연결"): 앱 시작(T049의 복구 뒤 자리), 기존 `wakeObserver`, 노치 펼침 콜백, 설정 창 `onAppear`에서 같은 함수 → `RecurrenceReset.reset` → 바뀐 할 일 `apply` → 빈 상태면 고르기. `NSApplication.didBecomeActiveNotification`은 쓰지 않는다. 달력은 `GregorianCalendar.make(timeZone:)`에 ADR-0010 결정 검증(T012)에서 고른 방식으로 시간대를 넘긴다. 사람 확인은 다음 날 아침 실제로 한 번(시스템 시계를 바꾸지 않는다) 〔단위 5〕

**확인 지점**: `swift test` PASS. SC-104는 시뮬레이터와 두 시간대 단위 시험으로

---

## Phase 7: User Story 5 - 일정과 첫 실행 온보딩 (Priority: P2)

**Goal**: 일정(컨텍스트) 탭, 온보딩 두 단계(일정 한 건 · 기본값)

**Independent Test**: 단위 시험으로 온보딩 끝내기 규칙. 화면은 quickstart 6 온보딩 줄(새 사용자 계정)

### Tests (Red)

- [ ] T058 [P] [US5] `Tests/MokaCoreTests/OnboardingTests.swift`에 `Onboarding.finish` 시험을 쓰고 실패를 확인한다(data-model §6, `FR-21 R-116`): 순서(컨텍스트 → 세 설정 → `onboarding_done`), 중간 실패(가짜 저장소가 throw)면 `onboarding_done`을 쓰지 않음, 값을 그대로 두면 25·10·`06:00`, 일정 없이 끝내도 할 일 추가·고르기가 됨 〔단위 1〕

### Implementation (Green)

- [ ] T059 [US5] `Sources/MokaCore/Onboarding.swift`에 `Onboarding.finish`를 둔다. T058 PASS 〔단위 1〕
- [ ] T060 🔒 [US5] `App/Sources/Views/ContextTabView.swift`·`ContextFormView.swift`에 일정 탭을 만든다(시안 10번, R-115, 값·콜백만): 목록은 날짜순, 줄마다 이름·"11월 12일"·중요도 배지(아주=빨강 굵게, 꽤, 조금), 아래 `+`·`−`(−는 확인 없이 바로 지움), 안내 "시험·제출처럼 할 일 순서에 영향을 주는 일정이에요.". 새 일정 시트: 이름·날짜(날짜 고르기)·중요도 세그먼트 조금/꽤/아주(내용 폭), 셋 다 필수, 고치기 없음 〔단위 4〕
- [ ] T061 🔒 [US5] `App/Sources/Views/OnboardingView.swift`와 `App/Sources/MokaApp.swift`에 온보딩 창을 만든다(시안 11·12번, R-116, 폭 400pt, 창 제목 "Moka 시작하기", 단계 막대 1/2·2/2, 창 방식은 plan "앱 연결"):
  - 1단계: "다가오는 시험이나 제출이 있나요?", "하나만 넣어 두면 돼요. 나머지는 설정의 일정 탭에서 더할 수 있어요.", 이름(자리표시 "예: 중간고사")·날짜(그 순간이 속한 하루)·중요도(기본 조금), 건너뛰기·다음(이름이 비면 꺼짐). 저장은 2단계에서 한꺼번에
  - 2단계: "이대로 시작할까요?", "언제든 설정에서 바꿀 수 있어요.", 기본 작업 시간·추가 시간·하루 시작 시각, 이전·시작하기 → `Onboarding.finish` → 창 닫힘 → 노치 빈 상태
  - 빨간 버튼으로 닫으면 끝내지 않은 것(다음 실행에 다시)
  - `showsOnboarding`(data-model §8)일 때만 연다
  〔단위 4〕

**확인 지점**: `swift test` PASS, 앱 빌드 PASS. SC-105는 사람이 새 사용자 계정에서

---

## Phase 8: Polish & Cross-Cutting

- [ ] T062 🔒 `App/Tests/MokaAppTests/ScreenStateSnapshotTests.swift`에 새 화면 상태 스냅샷을 라이트·다크로 더한다(ADR-0009, quickstart 5): 접힌 초안(C1-B)과 이어서 할 일 2초, 시작 전 + 다른 할 일 + 이어서 할 일, 도는 중 + 세 버튼, 두 줄 입력(바꾸는 중·미루는 중), 시간 끝 + 두 줄, 저장할 수 없는 빈 상태, 설정 기본 탭, 할 일 탭(보기·정렬·다음·매일/매주 연속 배지), 할 일 시트(새로·매주·고치기·지우기 확인), 일정 탭과 시트, 온보딩 1·2단계. sanity 단언만(크기 0 아님, 단색 아님, 라이트≠다크). 출력 폴더는 `TEST_RUNNER_MOKA_SNAPSHOT_DIR=.verify/snapshots/002`로 준다(`SnapshotHelper` 기본값은 001, 커밋 안 함) 〔단위 4〕
- [ ] T063 🔒 모은 PNG를 `~/Dev/ai-platform/projects/moka/design/pr-<번호>/index.html`에 시안 `002-mockup.html` 같은 번호와 나란히 두고 PR "완료 증거"에 경로를 적는다(저장소 밖, 커밋 안 함) 〔단위 4〕
- [ ] T064 quickstart 3 오류 주입을 돌린다(커밋 안 함, 결과만 PR) 〔단위 1·2·3〕
- [ ] T065 단위 1·2·3·5 PR마다 quickstart 1~4 결과 표(PASS/FAIL/SKIP/NOT_RUN)와 기존 golden 변경 0줄 확인을 붙인다 〔단위 1·2·3·5〕
- [ ] T066 🔒 사람이 quickstart 5~7을 돌려 결과 표를 마지막 PR에 붙인다(SC-101 다시 켜기, SC-105 온보딩, SC-107 다음 표시, 종료) 〔단위 4·5〕

---

## Dependencies & Execution Order

### Phase 순서

- 단위 순서는 plan "작업 단위" 한 문장이 원본이다: 단위 1 → 단위 2와 단위 3을 병렬 → 단위 5(단위 2 뒤) → 단위 4(단위 2·5 뒤).
- 단위 1은 크면 1a(T001~T007의 단위 1 몫, T010~T014)와 1b(나머지 단위 1)로 나눈다. 단위 2는 1a 병합 뒤 시작한다.
- 단위 4 안에서는 US1(T028~T031) → US2(T040~T044) → US3(T051) → US5(T060·T061) → Polish(T062·T063).

### 태스크 사이 의존

- T010 ← T003, T011 ← T005, T012 ← T004·T010, T013 ← T006·T002, T014 ← T007·T010·T011, T015 ← T007·T008·T014, T016 ← T009·T015
- T023 ← T017·T018·T010·T012, T024 ← T019·T012, T025 ← T020·T014·T023, T037 ← T032·T033·T035·T025, T038 ← T034, T047 ← T045·T025, T054 ← T052·T012, T059 ← T058·T013·T014
- T026 ← T021·T022·T025·T037(`SessionCommit`), T027 ← T026, T039 ← T036·T037·T026, T048 ← T046·T047·T026, T055 ← T053·T054·T026, T056 ← T055
- T049 ← T015·T025·T037·T047, T050 ← T049, T057 ← T049·T054
- T028~T031 ← T023·T024·T025·T049, T040~T044 ← T037·T038·T049, T051 ← T049, T060·T061 ← T059·T049, T062 ← T028~T061 화면, T063 ← T062
- Issue #52(spec 001 문구 셋)는 `Sources/MokaCore/NotchStatus.swift`(T038)와 `App/Sources/Views/ExpiredView.swift`(T042)를 같이 고친다. 단위 4 전에 병합하거나 단위 4에 묶는다

### 작업 단위 ↔ Issue (plan "작업 단위")

| 단위 | 태스크 | 무인 가능 | 먼저 할 일 |
|---|---|---|---|
| 1 MokaCore 값 타입·규칙 | T001~T006, T007(메모리), T010~T014, T017~T020, T023~T025, T032~T035, T037·T038, T045·T047, T052·T054, T058·T059, T064·T065 일부 | 예(👁 `scheduler_choice` 값) | 첫 Issue. 크면 1a·1b |
| 2 MokaStore v2 | T007(GRDB), T008·T009, T015·T016, T064·T065 일부 | 예(👁 스키마 스냅샷) | 1a 병합 뒤 |
| 3 `moka-sim` storage | T021·T022, T026·T027, T036·T039, T046·T048, T053·T055·T056, T064·T065 일부 | 예(👁 계약·픽스처) | 1 병합 뒤, 2와 병렬 |
| 4 앱 화면 | T028~T031, T040~T044, T051, T060~T063, T066 일부 | 아니오(사람 화면 확인) | 2·5 병합 뒤, #52와 순서 맞춤 |
| 5 앱 수명 연결 | T049·T050, T057, T065·T066 일부 | 코드는 예, 확인은 사람 | 2 병합 뒤 |

### Parallel Opportunities

- T003~T009 동시(서로 다른 시험 파일)
- T017~T020 동시, T032~T036 동시, T045·T046, T052·T053
- 단위 1 병합 뒤 단위 2(`Sources/MokaStore`·`Tests/MokaStoreTests`·`schema/`·`tuning/`)와 단위 3(`Sources/MokaCore/Sim`·`Tests/MokaCoreTests/Fixtures/sim`·계약 원본)은 파일이 겹치지 않아 implementer 둘로 병렬
- 단위 4 안에서 T030·T031(할 일 탭)과 T060(일정 탭), T061(온보딩)은 파일이 겹치지 않는다

### Parallel Example: 단위 1 병합 뒤

```text
implementer A: "단위 2 — T007(GRDB 켜기)·T008·T009·T015·T016 (MokaStore·Tests/MokaStoreTests·schema·tuning만)"
implementer B: "단위 3 — T021·T022·T026·T027·T036·T039·T046·T048·T053·T055·T056 (MokaCore/Sim·Fixtures/sim·계약 원본만)"
```

---

## Implementation Strategy

### MVP First (US1 + US2 저장·버튼 경로)

1. 단위 1 → 단위 2: 할 일·체크포인트·로그가 저장되고 메모리·GRDB가 같은 계약을 지킨다
2. 단위 3(US1·US2 픽스처): 화면 없이 마일스톤 2 완료 조건 "완료/미루기/바꾸기가 로그에 쌓이고 체크포인트가 재진입 시 보인다"를 `moka-sim`으로 보인다
3. 단위 5(T049) → 단위 4의 US1·US2 화면(T028~T031, T040~T044): 앱에서 같은 경로
4. US3(종료·잠자기, 저장 불가 안내) → US4(반복) → US5(일정·온보딩) → Polish
5. 일정이 밀리면(마일스톤 2는 2026-11-03 하루) spec 위험 1의 덜어낼 순서(R-118 화면 T030의 보기·정렬 → US5 화면 T060·T061 → US4 연결 T057 → US3 알림 T050)대로 버퍼(2026-11-08~09)로 넘기고 PR에 적는다. 필수(US1·US2, R-111, R-119)는 넘기지 않는다

### 무인 실행 경계

- 실행 대상: 밤 무인 실행은 🔒 없는 태스크(MokaCore, MokaStore, `moka-sim`, pytest)만 집어 끝까지 간다.
- 🔒 태스크: 무인으로 코드를 쓰고 빌드까지 해도 되지만, 사람이 화면·앱 수명을 확인하기 전에는 끝난 것으로 표시하지 않는다(PR은 초안으로 둔다).
- 👁 태스크(T008·T015 스키마 스냅샷, T021·T022·T026·T027·T036·T046·T053 계약·픽스처, T017·T023·T032 `scheduler_choice` 값, T051 문구)는 PR "사람이 볼 결정"에 적는다.

---

## R-ID ↔ 태스크

| R-ID / SC | 시험 | 구현 | 화면·사람 확인 |
|---|---|---|---|
| R-101 할 일 값·저장 | T003, T007, T008, T018 | T010, T014, T015, T023 | T031 |
| R-102 할 일 탭 | T020(`nextMark`) | T025 | T029, T030, T031 |
| R-103 빠른 입력 저장 | T020, T022 | T025, T026 | T028, T049 |
| R-104 노치 고르기 순환·다른 할 일 | T017, T020, T022, T032 | T023, T025 | T028, T030("다음") |
| R-105 세 버튼 | T032 | T037 | T040, T042 |
| R-106 두 줄·돌아가기 | T032, T034 | T037, T038 | T041, T044 |
| R-107 시간 끝 두 줄·Enter | T032, T036 | T037, T039 | T042 |
| R-108 체크포인트 | T003, T007, T008, T033 | T010, T037 | — |
| R-109 이어서 할 일 | T032, T033, T036 | T037 | T040, T043 |
| R-110 종료·잠자기 | T045, T046 | T047, T048 | T050 |
| R-111 재시작 복구 | T045, T046 | T047, T048 | T049, T050 |
| R-112 행동 로그 | T007, T008, T032 | T037 | T044 |
| R-113 반복 리셋 | T018, T052, T053 | T023, T054, T055 | T057 |
| R-114 하루 경계 | T004 | T012 | T057 |
| R-115 컨텍스트 | T007, T008 | T014, T015 | T060 |
| R-116 온보딩 | T006, T058 | T013, T059 | T061 |
| R-117 시뮬레이터 | T021, T022, T036, T046, T053, T056 | T026, T027, T039, T048, T055 | — |
| R-118 목록 보기·정렬 | T019 | T024 | T030 |
| R-119 저장 실패 | T035 | T037 | T049, T051 |
| SC-101 다시 켜도 남음 | T007, T008 | T015 | T049, T066 |
| SC-102 버튼 수 = 로그 수 | T032, T036 | T037, T039 | T044 |
| SC-103 이어서 할 일 재진입 | T022, T036, T046 | T039, T048 | T043, T066 |
| SC-104 반복 멱등·매주 | T052, T053 | T054, T055 | — |
| SC-105 온보딩 조작 2번 | T058 | T059 | T061, T066 |
| SC-106 실제 데이터 안 엶 | 공통 규칙, T007(`TestDatabase`만) | T026(DB 인자 없음) | T064 |
| SC-107 목록 보기·다음 표시 | T019, T020 | T024, T025 | T030, T066 |
| SC-108 시뮬레이터 재현·기존 golden 불변 | T022, T036, T046, T053 | T011, T026 | T065 |
