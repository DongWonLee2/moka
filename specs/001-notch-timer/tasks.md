---

description: "spec 001 노치와 타이머 작업 목록"
---

# Tasks: 노치와 타이머 (마일스톤 1)

**Input**: `specs/001-notch-timer/`의 plan.md, spec.md(R-001~R-015), research.md(R1~R9), data-model.md, contracts/moka-sim-v1.md, quickstart.md

**Tests**: 넣는다. 헌법 II(테스트 먼저)와 AGENTS.md "실패하는 테스트를 먼저 쓰고 실패를 확인한 뒤 구현한다"를 따른다. 테스트 태스크마다 Red 커밋 → 구현 태스크에서 Green 커밋.

**Organization**: 사용자 이야기(US1~US5)별로 묶는다. 각 태스크 끝의 `〔단위 N〕`은 plan "작업 단위" 번호이고 Issue 하나가 된다.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 다른 파일을 고치고 아직 안 끝난 태스크에 기대지 않아 병렬로 할 수 있다
- **[Story]**: US1~US5(spec.md)
- **🔒**: spike(Phase 3) PASS와 시안 확정(2026-10-28, v3.4) 뒤에만 시작한다. 시안은 이미 확정됐으므로 spike PASS가 유일한 남은 조건이다

## 공통 규칙 (모든 태스크)

- 테스트 표시 이름은 `@Test("FR-06 R-005: …")`처럼 PRD FR과 R-ID로 시작한다(ADR-0003). Swift Testing을 쓴다. 앱 스냅샷 번들만 XCTest.
- 시각은 주입한 `MokaClock`과 고정 `TimeZone(identifier:)`으로 시험한다. MokaCore에서 `Date()`, `TimeZone.current`를 읽지 않는다. 실제 시간을 기다리지 않는다.
- 가짜 할 일만 쓴다(예: "가짜 할 일 A"). 실제 앱 DB 경로(`~/Library/Application Support/dev.dongwon.moka/`)를 테스트·`moka-sim`에서 열지 않는다. `eraseDatabaseOnSchemaChange`를 켜지 않는다.
- `Package.swift`는 바꾸지 않는다(plan). 픽스처와 스냅샷 파일은 `#filePath` 기준 상대 경로로 읽어 `resources:` 선언 없이 쓴다. 이 전제가 깨지면(예: 테스트 타깃 의존 추가가 필요) 멈추고 PR "사람이 볼 결정"에 올린다.
- 검증 명령: `swift test`, 앱은 `xcodegen generate && xcodebuild build -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`. 결과는 PASS/FAIL/SKIP/NOT_RUN.

---

## Phase 1: Setup

**Purpose**: 기존 골격(`Health.swift`, `MokaDatabase.swift`, `moka-sim/main.swift`) 위에 공통 파일 자리를 만든다

- [ ] T001 기준 상태 확인: `swift test`를 돌려 기존 `HealthTests`·`MokaDatabaseTests`가 PASS인지 기록한다(원래 실패와 새 회귀 구분). 결과를 PR "완료 증거"에 적는다 〔단위 1·2 공통〕
- [ ] T002 [P] `Sources/MokaCore/Defaults.swift`에 상수를 둔다: 기본 분 `25`, 범위 `1...180`, 프리셋 `[15, 25, 45, 60]`. `GLOSSARY.md`의 이름을 따른다 〔단위 1〕
- [ ] T003 [P] `Sources/MokaCore/MokaClock.swift`에 현재 시각 주입 타입을 둔다(프로토콜 또는 `() -> Date` 값). 테스트용 고정 시계를 같은 파일 또는 `Tests/MokaCoreTests/Support/FixedClock.swift`에 둔다 〔단위 1〕

---

## Phase 2: Foundational (모든 이야기가 기대는 것)

**Purpose**: 타이머 상태기계와 설정 읽기 규칙. US1~US4가 모두 이것에 기댄다

**⚠️ CRITICAL**: 이 Phase가 끝나기 전에는 이야기별 앱 작업을 시작하지 않는다

### Tests (Red)

- [ ] T004 [P] `Tests/MokaCoreTests/NotchTimerTests.swift`에 상태기계 시험을 쓰고 실패를 확인한다. data-model §2의 전이표를 하나씩 옮긴다:
  - `FR-06 R-005`: `empty --start(task, 25, at: t0)--> running`, `endsAt == t0 + 1500초`, 남은 초 = `ceil(endsAt − now)`이고 `running`에서는 항상 1 이상
  - `FR-06 R-005`: `now`가 이전 `now`보다 작아져도 끝 시각 기준으로 계산(시계 되돌림)
  - `FR-06 R-008`: `tick(now ≥ endsAt)` → `expired`, 남은 초 0. 한 번에 여러 분을 건너뛴 `tick`(잠자기)도 바로 `expired`
  - `FR-06 R-007`: `running`·`expired`에서 `complete` → `empty`
  - `FR-05 R-010`: `expired --start(45, at)--> running`, 같은 할 일 제목 유지
  - 표에 없는 이벤트(`empty`에서 `tick`·`complete`)는 상태를 바꾸지 않는다
  - 불변식: `endsAt > startedAt`, `quantumMin ∈ 1…180`(범위 밖 `start`는 거부)
  〔단위 1〕
- [ ] T005 [P] `Tests/MokaCoreTests/QuantumSettingsTests.swift`에 설정 읽기 규칙 시험을 쓰고 실패를 확인한다:
  - `FR-16 R-012`: 행 없음 → 25, `"45"` → 45, `"0"`·`"181"`·`"4.5"`·`""`·`"abc"` → 25
  - `FR-16 R-012`: 쓰기는 "1~180 정수만 받고 그 밖은 거부해 이전 값을 유지한다"(data-model §4)
  - `FR-16 R-013`: 메모리 가짜 `SettingsStore`로 기본값을 바꿔도 이미 만든 `running` 타이머의 `quantumMin`·`endsAt`는 그대로
  〔단위 1〕

### Implementation (Green)

- [ ] T006 `Sources/MokaCore/NotchTimer.swift`에 값 타입 상태기계 `empty / running / expired`를 구현한다. `running`은 할 일 제목, `quantumMin`, `startedAt`, `endsAt`을 가진다. 상태는 `start(…at:)`, `tick(now:)`, `complete(at:)`로만 바뀐다(research R1). T004 PASS 〔단위 1〕
- [ ] T007 `Sources/MokaCore/QuantumSettings.swift`에 `SettingsStore` 프로토콜(`func value(for key: String) throws -> String?`, `func setValue(_:for:) throws` 정도)과 `default_quantum_min` 읽기·쓰기 규칙, 테스트·`moka-sim`용 메모리 구현을 둔다. T005 PASS 〔단위 1〕

**Checkpoint**: `swift test` PASS. 화면 없이 타이머 규칙이 선다

---

## Phase 3: DynamicNotchKit spike (사람이 있는 낮 세션, 🔒 UI 태스크 전부의 조건)

**Purpose**: research R4의 미확인 동작 5가지를 버리는 브랜치에서 확인한다. 병합하지 않는다. 상한 반나절. 무인 실행 대상이 아니다

- [ ] T008 버리는 브랜치 `spike/dynamicnotchkit`에서 `project.yml` `packages`에 `DynamicNotchKit: {url: https://github.com/MrKai77/DynamicNotchKit, revision: cd0b3e52d537db115ad3a9d89601f20e0bee8d27}`(주석 `# 1.1.0`)을 앱 타깃에만 연결하고 아래 5가지를 PASS/FAIL로 기록한다 〔단위 3〕
  1. 앱 타깃 Swift 6 모드 빌드(실패하면 ADR-0001 32행대로 첫 실패에서 앱 타깃만 `SWIFT_VERSION: 5.0`, 두 번째 시도 없음)
  2. 노치 위에 마우스를 올리면 펼침(라이브러리에 없으면 직접 구현 전제로 기록)
  3. `LSUIElement` 앱에서 펼친 화면 `TextField`에 키 입력이 들어감(R-002)
  4. 코드로 펼칠 때 키보드 포커스를 가져가지 않음(R-009, SC-003)
  5. 노치 없는 화면에서 직접 만든 `.nonactivatingPanel` 떠 있는 창이 뜨고 펼쳐짐(R-011)
- [ ] T009 같은 세션에서 스냅샷 도우미 첫 시험: `NSHostingView` + `bitmapImageRepForCachingDisplay`·`cacheDisplay(in:to:)`로 `TextField`가 든 뷰 하나를 라이트·다크 PNG로 만든다(research R8). 결과를 T008과 함께 `research.md` R4·R8과 ADR-0001 "결정 검증"에 적는 PR을 따로 연다(spike 코드는 넣지 않음) 〔단위 3〕

**Checkpoint**: 5가지와 스냅샷 도우미 결과가 기록됐다. FAIL이 있으면 Phase 4 이후 🔒 태스크의 설계를 다시 정하고(debate) 사람 승인을 받는다

---

## Phase 4: User Story 1 - 할 일 하나를 넣고 타이머를 돌린다 (Priority: P1) 🎯 MVP

**Goal**: 빈 상태 → 제목 입력 → 기본 시간으로 시작 → 접힌 화면에 점·제목·남은 시간 → 완료 → 빈 상태

**Independent Test**: 화면 없이 `swift run moka-sim run Tests/MokaCoreTests/Fixtures/sim/us1-basic.json`이 `empty → running(1500) → expired(0) → empty`를 출력한다. 화면은 quickstart 6의 SC-001 순서로 사람이 본다

### Tests (Red)

- [ ] T010 [P] [US1] `Tests/MokaCoreTests/SimScenarioTests.swift`에 `moka-sim` v1 디코더 시험을 쓴다(contracts/moka-sim-v1.md 입력 표 그대로):
  - `version`은 정수 `1`만, `timezone`은 IANA 이름 필수, `settings` 없으면 `{}`, `events[].at`은 "ISO 8601, 오프셋 필수, 초 단위까지(소수 초 없음)", `at`은 줄어들지 않아야 함
  - 모르는 `version`·키·`type`, 필수 필드 없음, 시각 역행, 범위 밖 값, 공백뿐인 `title` → 입력 오류(종료 코드 2에 대응)
  - 상태에 맞지 않는 이벤트(예: 빈 상태에서 `start`) → 입력 오류
  〔단위 1〕
- [ ] T011 [P] [US1] `Tests/MokaCoreTests/SimGoldenTests.swift`에 golden 시험을 쓴다: `Tests/MokaCoreTests/Fixtures/sim/*.json`마다 실행기 출력을 같은 이름의 `*.expected.jsonl`과 바이트 단위로 비교한다. 출력 규칙: 키 순서 `seq, at, event, state, chip_min, remaining_s` 고정, `at`은 UTC `Z`, 제목은 출력하지 않음. 픽스처 `us1-basic.json`(기본 25분 시작 → 끝 시각 `tick`에서 `expired`, `remaining_s` 0 → `complete`)과 기대 출력을 함께 커밋한다 〔단위 1〕

### Implementation (Green)

- [ ] T012 [US1] `Sources/MokaCore/Sim/`에 시나리오 타입·디코더(`SimScenario.swift`), 실행기(`SimRunner.swift`, `NotchTimer`와 `QuantumSettings`의 메모리 저장소 사용), JSON Lines 출력(`SimOutput.swift`)을 구현한다. 결과는 출력 줄 목록 또는 `inputError`/`invariantViolation` 오류 값으로 돌려준다. T010·T011 PASS 〔단위 1〕
- [ ] T013 [US1] `Sources/moka-sim/main.swift`를 `moka-sim run <file>`로 바꾼다: 파일 읽기 → 실행기 → 표준 출력, 오류는 표준 오류 한 줄, 종료 코드 `0` 정상 / `1` 불변식 위반 / `2` 입력 오류. DB·네트워크·Keychain·환경 변수·`Date()`·`TimeZone.current`를 쓰지 않고 DB 경로 인자를 두지 않는다(기존 `MokaDatabase.inMemory()` 호출은 지운다). `swift run moka-sim run Tests/MokaCoreTests/Fixtures/sim/us1-basic.json`의 출력과 종료 코드를 PR "완료 증거"에 붙인다 〔단위 1〕
- [ ] T014 🔒 [US1] `App/Sources/AppState.swift`에 `@Observable @MainActor final class AppState`를 둔다: `NotchTimer` 값, `isExpanded`, `isPinnedOpen`, `draftTitle`, `chipMinutes`, `isEditingCustom`, `isInputFocused`(data-model §6). 1초 주기 화면 갱신 타이머와 `NSWorkspace.didWakeNotification`에서 `tick(now:)`를 부를 뿐 상태를 직접 바꾸지 않는다(research R1). `os.Logger`(subsystem `dev.dongwon.moka`)로 상태 전이 이름만 남기고 제목은 남기지 않는다(R7) 〔단위 4〕
- [ ] T015 🔒 [US1] `App/Sources/Notch/NotchHost.swift`(DynamicNotchKit을 import하는 유일한 파일)에서 접힘·펼침 뷰를 띄우고, 노치에 마우스를 올리면 펼친다. 입력칸에 포커스가 있으면 마우스가 나가도 접지 않는다(Edge Case). `project.yml`에 DynamicNotchKit 패키지(T008과 같은 revision)와 `MokaStore` 의존을 더한다 〔단위 4〕
- [ ] T016 🔒 [P] [US1] `App/Sources/Views/`에 시안 v3.4대로 뷰를 만든다. 뷰는 `AppState`가 아니라 값(상태, 제목, 남은 초, 칩 값, 콜백)을 받아 스냅샷 번들이 앱 없이 컴파일할 수 있게 한다:
  - `CollapsedView.swift`: 빈 상태 회색 점(R-001), 도는 중 점·제목·남은 시간(노치 왼쪽 폭 104pt, 넘치는 제목은 끝을 "…"로, R-006)
  - `ExpandedView.swift`: 빈 상태 입력칸(자리표시 "할 일 없음 — 무엇을 할까요?", R-001), 앞뒤 공백을 뺀 제목이 비면 Enter로 넘어가지 않음(R-002), 도는 중에는 제목(두 줄까지)·남은 시간·완료 버튼만(R-006). 판 폭 340pt, 노치 왼쪽 귀에 모카 무스 #A47864 잔 + 폼 #F5E9E1 MOKA 워드마크, 오른쪽 귀에 상태 글자
  - `MokaColors.swift`: #A47864, #85604F, 크레마 #E6C7B4, 폼 #F5E9E1, 시간 끝 #E5533D
  〔단위 4〕
- [ ] T017 🔒 [US1] `App/Sources/MokaApp.swift`에서 `AppState`를 만들고 메뉴 막대 항목을 "설정…"과 "종료"만 둔다(R-012). 메뉴 막대 아이콘은 S3 넓은 잔 + 김 단색 템플릿 이미지. 할 일과 타이머는 메모리에만 둔다(R-014) 〔단위 4〕

**Checkpoint**: `swift test` PASS, `moka-sim` us1 golden PASS, 앱 빌드 PASS. 화면은 사람이 SC-001로 확인

---

## Phase 5: User Story 2 - 작업 시간을 바꿔 고른다 (Priority: P1)

**Goal**: 칩에서 15/25/45/60분이나 직접 입력(1~180)으로 시작

**Independent Test**: 화면 없이 `us2-choose-45.json`이 `chip_min` 45, `remaining_s` 2700을 출력하고, 직접 입력 규칙 시험이 0·181·빈 값·숫자 아님·소수를 거부한다

### Tests (Red)

- [ ] T018 [P] [US2] `Tests/MokaCoreTests/QuantumChipTests.swift`에 칩 규칙 시험을 쓴다:
  - `FR-05 R-003`: 제목 입력 직후 칩 값 = `default_quantum_min`
  - `FR-05 R-004`: 프리셋은 15, 25, 45, 60. 직접 입력은 "정수 1~180. 그 밖, 빈 값, 숫자 아님, 소수는 '시작 불가'"(data-model §3). 1과 180은 받는다
  〔단위 1〕
- [ ] T019 [P] [US2] 픽스처 `Tests/MokaCoreTests/Fixtures/sim/us2-choose-45.json`과 기대 출력을 더한다: 45분 선택 → 시작(`remaining_s` 2700) → 시간 끝 → `choose_quantum` 15 → 다시 시작(R-010) → 완료. 입력 오류 픽스처 `err-unknown-type.json`, `err-time-reversed.json`은 golden이 아니라 T010 방식으로 오류 값을 확인한다 〔단위 1〕

### Implementation (Green)

- [ ] T020 [US2] `Sources/MokaCore/QuantumChip.swift`에 프리셋, 직접 입력 문자열 → `Int?` 검증, 미리 채움 규칙을 구현하고 `SimRunner`의 `choose_quantum`이 이 규칙을 쓰게 한다. T018·T019 PASS 〔단위 1〕
- [ ] T021 🔒 [US2] `App/Sources/Views/QuantumChipView.swift`에 macOS 분할 컨트롤(15분|25분|45분|60분|직접…)과 직접 입력칸을 만든다. 직접 입력이 시작 불가면 시작 버튼을 막는다. Enter나 시작 한 번으로 칩 값으로 시작한다(R-003). 버튼은 둥근 사각형 push button, 기본 버튼은 #A47864→#85604F 〔단위 4〕

**Checkpoint**: US1·US2를 함께 화면 없이 재현할 수 있다

---

## Phase 6: User Story 3 - 시간이 끝나면 알아챈다 (Priority: P1)

**Goal**: 0:00에서 멈추고 노치가 저절로 펼쳐져 "시간 끝"을 보이되 키보드 포커스를 가져가지 않는다

**Independent Test**: 화면 없이 `us3-sleep.json`(잠자기를 `at` 건너뛰기로 표현)의 깨어난 첫 `tick`이 `expired`. 화면은 quickstart 6의 1분 타이머로 SC-003(다른 앱 타이핑 0자)과 R-009(마우스 넣었다 빼도 유지)를 사람이 본다

### Tests (Red)

- [ ] T022 [P] [US3] 픽스처 `Tests/MokaCoreTests/Fixtures/sim/us3-sleep.json`과 기대 출력을 더한다: 25분 시작 → 10분 뒤 `tick`(`remaining_s` 900) → 끝 시각을 지난 시각으로 건너뛴 `tick` → `expired`, `remaining_s` 0 → `complete` → `empty`(R-008, SC-002) 〔단위 1〕

### Implementation

- [ ] T023 🔒 [US3] `App/Sources/AppState.swift`에서 `running → expired` 전이를 받으면 `isExpanded = true`, `isPinnedOpen = true`로 바꾼다. 창을 key window로 만들지 않고 앱을 활성화하지 않는다. 사용자가 노치를 클릭했을 때만 입력 포커스를 준다. `isPinnedOpen`이면 마우스가 나가도 접지 않고, 시작·완료를 누르면 `false`(R-009, data-model §6, spike 4번 결과를 따른다). 소리·시스템 알림·자동 연장은 넣지 않는다(R-008) 〔단위 4〕
- [ ] T024 🔒 [US3] `App/Sources/Views/ExpiredView.swift`에 "시간 끝"(#E5533D), 칩(기본값으로 채움, data-model §3), 시작·완료 버튼을 만든다. 시작은 같은 할 일로 다시 돈다(R-010), 완료는 빈 상태(R-007) 〔단위 4〕

**Checkpoint**: 마일스톤 1 P1 범위(US1~US3) 완성

---

## Phase 7: User Story 4 - 기본 작업 시간을 설정한다 (Priority: P2)

**Goal**: 메뉴 막대 "설정…"에서 `default_quantum_min`을 바꾸고 재시작 뒤에도 남는다

**Independent Test**: `swift test`의 `MokaStoreTests`가 마이그레이션 이름, 스키마 스냅샷, 경로 가드, 왕복을 확인한다. 화면 없이 `us4-default-change.json`이 도는 중 `set_default_quantum` 뒤에도 `remaining_s`가 그대로이고 다음 `enter_title`의 `chip_min`이 새 값임을 보인다(R-013)

### Tests (Red)

- [ ] T025 [P] [US4] `Tests/MokaStoreTests/MigrationTests.swift`에 시험을 쓴다:
  - `FR-16 R-012`: 등록된 마이그레이션 이름 배열이 정확히 `["v1_settings"]`
  - `FR-16 R-012`: 메모리 DB에 마이그레이션을 돌린 뒤 `sqlite_master`의 `sql`을 이름순으로 모은 텍스트가 `schema/moka-schema.sql`과 같다(파일은 `#filePath` 기준으로 찾는다)
  - 경로 가드: DB 열기 함수에 `dev.dongwon.moka`가 든 경로를 주면 테스트 빌드에서 거부한다(ADR-0004·0006)
  〔단위 2〕
- [ ] T026 [P] [US4] `Tests/MokaStoreTests/GRDBSettingsStoreTests.swift`에 왕복 시험을 쓴다: 임시 디렉터리 파일 DB에 45 저장 → 닫고 다시 열어 45(R-012 재시작 뒤 유지), 같은 키 두 번 저장은 UPSERT로 행 하나, seed 행 없음 〔단위 2〕
- [ ] T027 [P] [US4] 픽스처 `Tests/MokaCoreTests/Fixtures/sim/us4-default-change.json`과 기대 출력을 더한다(quickstart 2의 세 번째 시나리오) 〔단위 1〕

### Implementation (Green)

- [ ] T028 [US4] `Sources/MokaStore/Migrations.swift`에 이름 배열 상수 `["v1_settings"]`와 `DatabaseMigrator`를 둔다. `v1_settings`는 "`settings(key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)`"(data-model §4) 하나만 만들고 seed 행을 넣지 않는다. `eraseDatabaseOnSchemaChange`를 켜지 않는다 〔단위 2〕
- [ ] T029 [US4] `schema/moka-schema.sql`에 첫 스냅샷을 만든다. 리눅스 컨테이너(`docker run --rm -v "$PWD":/w -w /w swift:6.3.3-noble bash -c "apt-get update -qq && apt-get install -y -qq libsqlite3-dev >/dev/null && swift test"`)와 macOS에서 T025가 둘 다 PASS인지 확인한다(research R2 선행 확인). 텍스트가 다르면 멈추고 PR "사람이 볼 결정"에 올린다(ADR-0004 49행 재검토 트리거). 스냅샷 추가 자체도 "사람이 볼 결정"에 적는다 〔단위 2〕
- [ ] T030 [US4] `Sources/MokaStore/MokaDatabase.swift`에 경로를 주입받아 여는 함수(마이그레이션 포함)와 테스트 빌드 경로 가드를 더하고, `Sources/MokaStore/GRDBSettingsStore.swift`에 `SettingsStore` 구현(UPSERT)을 둔다. 기존 `inMemory()`·`healthCheck`는 유지한다. T025·T026 PASS 〔단위 2〕
- [ ] T031 [US4] `SimRunner`의 `set_default_quantum`을 구현해 T027 PASS(T012 뒤) 〔단위 1〕
- [ ] T032 🔒 [US4] `App/Sources/Settings/SettingsView.swift`에 기본 작업 시간 입력(1~180 정수, 밖이면 저장 안 하고 이전 값 유지)을 만들고, `MokaApp.swift`에서 `~/Library/Application Support/dev.dongwon.moka/moka.sqlite`를 `GRDBSettingsStore`로 연다. DB를 못 열면 메모리 저장소로 동작한다(25, 저장 안 남음, research R2). 앱 코드만 이 경로를 쓴다 〔단위 4〕

**Checkpoint**: 재시작 뒤 기본값 유지는 quickstart 6 마지막 줄로 사람이 확인

---

## Phase 8: User Story 5 - 노치가 없는 화면에서도 보인다 (Priority: P2)

**Goal**: 노치가 있는 내장 화면을 우선하고, 없으면 주 화면 메뉴 막대 아래 중앙 떠 있는 창

**Independent Test**: `DisplayTargetTests`가 화면 목록 → 표시 위치 규칙을 확인한다. 화면은 quickstart 6의 덮개 닫기로 사람이 SC-005를 본다

### Tests (Red)

- [ ] T033 [P] [US5] `Tests/MokaCoreTests/DisplayTargetTests.swift`에 data-model §5 표를 옮긴다(`FR-06 R-011`): 노치 있는 내장 화면 + 외부 모니터 → 내장 화면 `.notch`, 외부 모니터만 → `isMain` 화면 `.floating`, 화면 0개 → 결과 없음 〔단위 1〕

### Implementation

- [ ] T034 [US5] `Sources/MokaCore/DisplayTarget.swift`에 입력 `[(id, isBuiltIn, hasNotch, isMain)]` → `.notch(id)` / `.floating(id)` / 없음 순수 함수를 구현한다. T033 PASS 〔단위 1〕
- [ ] T035 🔒 [US5] `App/Sources/Notch/ScreenWatcher.swift`에서 `NSScreen` → T034 입력(노치 여부는 `safeAreaInsets.top > 0`)을 만들고 `NSApplication.didChangeScreenParametersNotification`에서 다시 고른다. 타이머 상태는 건드리지 않는다 〔단위 5〕
- [ ] T036 🔒 [US5] `App/Sources/Notch/FloatingHost.swift`에 직접 만든 `.nonactivatingPanel` 떠 있는 창(메뉴 막대 아래 중앙 고정, 드래그 없음)을 만들고 T016 뷰를 같이 띄운다. 접힘·펼침 둘 다 보이고 마우스를 올리면 펼친다. 시안 10번 라이트 워드마크는 #85604F 〔단위 5〕

**Checkpoint**: 다섯 이야기 모두 완성

---

## Phase 9: Polish & Cross-Cutting

- [ ] T037 🔒 `App/Tests/MokaAppTests/SnapshotHelper.swift`에 `renderPNG(view:size:appearance:) -> Data`(T009 결과)를 두고, `App/Tests/MokaAppTests/ScreenStateSnapshotTests.swift`에서 빈 상태, 입력, 칩 펼침, 도는 중, 시간 끝, 떠 있는 창을 라이트·다크로 만든다. sanity 단언만 한다(크기 0 아님, 단색 아님, 라이트≠다크). 출력은 `MOKA_SNAPSHOT_DIR` 또는 `.verify/snapshots/001/`(커밋 안 함). `project.yml`에 `MokaAppTests`(bundle.unit-test, TEST_HOST 없음, `App/Sources/Views/`를 직접 컴파일, `MokaApp.swift` 제외)를 더한다. CI job은 두지 않는다 〔단위 5〕
- [ ] T038 🔒 스냅샷 방법 ADR(다음 번호)을 `adr/`에 쓴다(D4, research R8). "생성 PASS는 화면 정합 증거가 아니다"를 적는다 〔단위 5〕
- [ ] T039 🔒 모은 PNG를 `~/Dev/ai-platform/projects/moka/design/pr-<번호>/index.html`에 시안과 나란히 두고 PR "완료 증거"에 경로를 적는다(저장소 밖, 커밋 안 함) 〔단위 4·5〕
- [ ] T040 quickstart 3 오류 주입: golden 기대값 하나와 마이그레이션 열 하나를 일부러 틀려 `swift test`가 FAIL하고 종료 코드가 0이 아닌지 확인한 뒤 되돌린다. 커밋하지 않고 결과만 PR에 적는다 〔단위 1·2〕
- [ ] T041 quickstart 1~6을 돌려 결과 표(PASS/FAIL/SKIP/NOT_RUN)를 마지막 PR에 붙인다. 6은 사람이 한다

---

## Dependencies & Execution Order

### Phase 순서

- Setup(1) → Foundational(2) → US1~US5의 MokaCore·MokaStore 태스크(🔒 없음)는 바로 진행
- Spike(3)는 사람이 있는 낮 세션. Phase 2와 무관하게 언제든 할 수 있다
- 🔒 태스크는 전부 Spike PASS 뒤. 그 안에서는 US1(T014~T017) → US2(T021)·US3(T023·T024) → US4(T032)·US5(T035·T036) → Polish(T037~T039)

### 태스크 사이 의존

- T006 ← T004, T007 ← T005
- T012 ← T006·T007·T010·T011, T013 ← T012
- T020 ← T018·T019·T012, T031 ← T027·T012, T034 ← T033
- T030 ← T025·T026·T028·T029, T032 ← T030·T017
- T015·T016 ← T014, T017 ← T014, T021 ← T016, T023 ← T014, T024 ← T021, T036 ← T016·T035
- T037 ← T016·T021·T024·T036, T038 ← T037, T039 ← T037

### 작업 단위 ↔ Issue (plan "작업 단위")

| 단위 | 태스크 | 무인 가능 | 먼저 할 일 |
|---|---|---|---|
| 1 MokaCore + `moka-sim` v1 | T001~T007, T010~T013, T018~T020, T022, T027, T031, T033, T034, T040 일부 | 예 | 첫 Issue(조언 노트의 #1 "돌아가는 뼈대" 중 Core·`moka-sim` 몫) |
| 2 MokaStore 첫 마이그레이션 | T025, T026, T028~T030, T040 일부 | 예 | 1과 파일이 겹치지 않아 병렬 |
| 3 spike + 스냅샷 도우미 첫 시험 | T008, T009 | 아니오(사람 눈·손) | 낮 세션 |
| 4 앱 노치 화면 | T014~T017, T021, T023, T024, T032, T039 일부 | 화면 확인은 사람 | 3 PASS 뒤 |
| 5 떠 있는 창 + 스냅샷 번들 + ADR | T035~T039 | 화면 확인은 사람 | 4 뒤 |

단위 1이 크면 Issue를 둘로 나눈다: 1a 상태기계·칩·설정 규칙·표시 위치(T002~T007, T018, T020, T033, T034), 1b `moka-sim` v1(T010~T013, T019, T022, T027, T031). 1b는 1a에 기댄다.

### Parallel Opportunities

- T002·T003 동시, T004·T005 동시
- 단위 1과 단위 2는 서로 다른 타깃(`Sources/MokaCore`·`Tests/MokaCoreTests` vs `Sources/MokaStore`·`Tests/MokaStoreTests`·`schema/`)이라 implementer 둘로 병렬. 단, 단위 2의 `GRDBSettingsStore`는 단위 1의 `SettingsStore` 프로토콜(T007)에 기댄다. T007을 먼저 병합하거나 단위 2가 프로토콜 모양을 Issue 본문대로 맞춘다
- T018·T019·T022·T027·T033은 서로 다른 파일이라 동시에 쓸 수 있다
- 🔒 쪽은 T016(뷰)과 T035(ScreenWatcher)가 겹치지 않는다

### Parallel Example: 단위 1·2 동시 시작

```text
implementer A: "단위 1a — T002~T007, T018, T020, T033, T034 (MokaCore만)"
implementer B: "단위 2 — T025, T026, T028~T030 (MokaStore·schema만), SettingsStore 프로토콜은 T007 모양을 따른다"
```

---

## Implementation Strategy

### MVP First

1. Phase 1~2 → 단위 1의 US1 몫(T010~T013)까지: 화면 없이 `moka-sim`으로 마일스톤 1 상태 변화를 보인다(SC-006 일부)
2. 단위 2 병렬
3. 낮 spike(Phase 3) PASS → US1 앱(T014~T017)이 마일스톤 1 완료 조건 "노치에 할 일 하나와 고른 시간의 타이머"
4. US2·US3 → US4·US5 → Polish

### 무인 실행 경계

- 밤에는 🔒 없는 태스크(MokaCore, MokaStore, `moka-sim`, 빌드)만 돈다. 🔒 태스크는 spike PASS 기록이 있어도 화면 확인은 사람이 아침에 한다
- 스키마 스냅샷(T029), 공개 계약 픽스처 추가(T011·T019·T022·T027)는 PR "사람이 볼 결정"에 적는다
