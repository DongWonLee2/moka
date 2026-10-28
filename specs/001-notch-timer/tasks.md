---

description: "spec 001 노치와 타이머 작업 목록"
---

# Tasks: 노치와 타이머 (마일스톤 1)

**Input**: `specs/001-notch-timer/`의 plan.md, spec.md(R-001~R-015), research.md(R1~R9), data-model.md, contracts/moka-sim-v1.md, quickstart.md

**Tests**: 넣는다. 헌법 II(테스트 먼저)와 AGENTS.md "실패하는 테스트를 먼저 쓰고 실패를 확인한 뒤 구현한다"를 따른다. 테스트 태스크마다 Red 커밋 → 구현 태스크에서 Green 커밋.

**Organization**: 사용자 이야기(US1~US5)별로 묶는다. 각 태스크 끝의 `〔단위 N〕`은 plan "작업 단위" 번호이고 Issue 하나가 된다(단위 1은 1a·1b 둘).

EGM 금붕어 리뷰(2026-10-28)와 승인 항목 토론 뒤 보강했다. 보고서와 토론 기록은 `.audit/egm/`, `.audit/debate/20261028-1225-spec001-egm-approvals.md`(커밋 안 함).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 다른 파일을 고치고 아직 안 끝난 태스크에 기대지 않아 병렬로 할 수 있다
- **[Story]**: US1~US5(spec.md)
- **🔒**: spike(Phase 3) PASS 뒤에만 시작한다(시안 v3.4 확정(완료) → v3.5(위쪽 오목 모서리, 2026-10-28)). 무인 실행 대상이 아니다
- 이 파일의 "확인 지점"은 Phase 완료 조건이다(GLOSSARY의 체크포인트와 다르다)

## 공통 규칙 (모든 태스크)

- 테스트 표시 이름은 `@Test("FR-06 R-005: …")`처럼 PRD FR과 R-ID로 시작한다(ADR-0003). FR이 없는 것은 `ADR-0003 R-015:`, `ADR-0004:`처럼 근거 ADR로 시작한다. Swift Testing을 쓴다. 앱 스냅샷 번들만 XCTest.
- 타입·함수 이름과 모양은 data-model.md의 Swift 블록을 따른다. 거기 없는 작은 이름은 구현 PR에서 정하고 PR "가정"에 적는다.
- 시각은 주입한 값(`apply(_:at:…)`의 `at`, 앱은 `MokaClock`)과 고정 `TimeZone(identifier:)`으로 시험한다. MokaCore에서 `Date()`, `TimeZone.current`를 읽지 않는다. 실제 시간을 기다리지 않는다.
- 가짜 할 일만 쓴다(예: "가짜 할 일 A"). 실제 앱 DB 경로(`~/Library/Application Support/dev.dongwon.moka/`)를 테스트·`moka-sim`에서 열지 않는다. `eraseDatabaseOnSchemaChange`를 켜지 않는다.
- `Package.swift` 내부 의존 정리(`moka-sim`→`MokaStore` 제거, `MokaStoreTests`에 `MokaCore` 명시)는 spec PR에 들어 있다. 구현 Issue에서는 `Package.swift`를 더 바꾸지 않는다. 픽스처와 스냅샷 파일은 `#filePath` 기준 상대 경로로 읽어 `resources:` 선언 없이 쓴다(SwiftPM의 미처리 파일 경고는 실패가 아니다). 이 전제가 깨지면 멈추고 PR "사람이 볼 결정"에 올린다.
- 검증 명령: `swift test`, 앱은 `xcodegen generate && xcodebuild build -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`. 결과는 PASS/FAIL/SKIP/NOT_RUN.

---

## Phase 1: Setup

**Purpose**: 기존 골격(`Health.swift`, `MokaDatabase.swift`, `moka-sim/main.swift`) 위에 공통 파일 자리를 만든다

- [ ] T001 기준 상태 확인: `swift test`를 돌려 기존 `HealthTests`·`MokaDatabaseTests`가 PASS인지 기록한다(원래 실패와 새 회귀 구분). 결과를 PR "완료 증거"에 적는다 〔단위 1a·2 공통〕
- [ ] T002 [P] `Sources/MokaCore/Defaults.swift`에 상수를 둔다: `Defaults.quantumMin = 25`, `Defaults.quantumMinRange = 1...180`, `Defaults.quantumPresets = [15, 25, 45, 60]` 〔단위 1a〕
- [ ] T003 [P] `Sources/MokaCore/MokaClock.swift`에 data-model §2의 `MokaClock`(`now: @Sendable () -> Date`, `static func fixed(_:)`)을 둔다. 단위 1에서는 정의만 하고 쓰는 곳은 앱(T014)이다 〔단위 1a〕

---

## Phase 2: Foundational (모든 이야기가 기대는 것)

**Purpose**: 타이머 값 타입과 설정 읽기 규칙. US1~US4가 모두 이것에 기댄다

**⚠️ CRITICAL**: 이 Phase가 끝나기 전에는 이야기별 앱 작업을 시작하지 않는다

### Tests (Red)

- [ ] T004 [P] `Tests/MokaCoreTests/NotchTimerTests.swift`에 시험을 쓰고 실패를 확인한다. data-model §2 전이표의 칸마다 하나씩(4단계 × 5이벤트, rejected 칸 포함) 옮긴다. 특히:
  - `FR-05 R-003`: `empty(nil)` + `enterTitle` → `empty(draft)`, 칩 = `defaultQuantumMin`. 공백뿐인 제목은 rejected
  - `FR-06 R-005`: `empty(draft 25)` + `start` at t0 → `running`, `endsAt == t0 + 1500초`, 남은 초 = `ceil(endsAt − now)`, `running`에서 항상 1 이상
  - `FR-06 R-005`: 시계를 되돌린 `now`(t0 − 3600초)에서도 남은 초는 1500을 넘지 않는다
  - `FR-06 R-008`: 끝 시각 이후 `tick` → `expired(title, defaultQuantumMin)`, 남은 초 0. 여러 분을 건너뛴 `tick`(잠자기)도 바로 `expired`
  - 암묵 tick: 끝 시각 이후 `complete` → `empty(nil)`, 끝 시각 이후 `chooseQuantum` → `expired`에서 칩 변경
  - `FR-06 R-007`: `running`·`expired`에서 `complete` → `empty(nil)`
  - `FR-05 R-010`: `expired` + `chooseQuantum(45)` + `start` → `running`, 같은 제목
  - `invariantViolation(at:)`: 정상 값은 nil, 깨진 값(`endsAt ≤ startedAt`, 칩 0)은 nil이 아님
  〔단위 1a〕
- [ ] T005 [P] `Tests/MokaCoreTests/QuantumSettingsTests.swift`에 설정 읽기 규칙 시험을 쓰고 실패를 확인한다:
  - `FR-16 R-012`: 행 없음 → 25, `"45"` → 45, `"0"`·`"181"`·`"4.5"`·`""`·`"abc"` → 25, 저장소가 throw하면 25
  - `FR-16 R-012`: `writeDefault`는 1~180 정수만 받고 그 밖은 `QuantumSettingsError.outOfRange`로 거부해 이전 값을 유지한다(data-model §4)
  - `FR-16 R-013`: `InMemorySettingsStore`의 기본값을 바꿔도 이미 만든 `running`의 `quantumMin`·`endsAt`는 그대로
  〔단위 1a〕

### Implementation (Green)

- [ ] T006 `Sources/MokaCore/NotchTimer.swift`에 data-model §2의 `Draft`, `NotchTimer`, `TimerEvent`, `TransitionResult`, `apply(_:at:defaultQuantumMin:)`, `remainingSeconds(at:)`, `invariantViolation(at:)`를 구현한다. T004 PASS 〔단위 1a〕
- [ ] T007 `Sources/MokaCore/QuantumSettings.swift`에 data-model §4의 `SettingsStore`(`func value(for key: String) throws -> String?`, `func setValue(_ value: String, for key: String) throws`), `QuantumSettings.readDefault(from:)`·`writeDefault(_:to:)`, `QuantumSettingsError.outOfRange`, `InMemorySettingsStore`를 둔다. T005 PASS 〔단위 1a〕

**확인 지점**: `swift test` PASS. 화면 없이 타이머 규칙이 시험된다. 단위 1a PR은 단위 1b·2보다 먼저 병합한다

---

## Phase 3: 노치 spike (사람이 있는 낮 세션, 🔒 UI 태스크 전부의 조건, 완료 2026-10-28)

**Purpose**: research R4의 미확인 동작을 버리는 브랜치에서 확인한다. 병합하지 않는다. 상한 반나절. 무인 실행 대상이 아니다

- [x] T008 버리는 브랜치에서 DynamicNotchKit 1.1.0(`cd0b3e52d537db115ad3a9d89601f20e0bee8d27`)을 앱 타깃에만 연결하고 6가지를 사람이 확인했다(2026-10-28). 결과: 1 Swift 6 빌드 PASS / 2 hover 펼침 PASS(라이브러리에 없어 `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)`로 직접) / 3 `LSUIElement` 입력칸 한글 포함 첫 클릭 PASS / 4 코드로 펼쳐도 key를 가져가지 않음 PASS("key window=없음, 앱 활성=false", `.nonactivatingPanel` + `orderFrontRegardless()`) / 5 직접 만든 떠 있는 창 PASS(노치 화면), 외부 모니터 NOT_RUN / 6 직접 만든 노치 모양 패널 PASS / 노치 옆 메뉴 클릭 가로채지 않음 PASS. 시작·완료 뒤 key가 이전 앱으로 돌아가는지는 기록이 없어 T015 사람 확인으로 넘긴다. 사람이 spike 끝에 결정했다. 2는 직접 구현이고, 4는 라이브러리 기본 동작이지만 같은 동작을 직접 만든 패널에서도 확인했다(spike 5·6). DynamicNotchKit은 뺐다(ADR-0008, research R4 표) 〔단위 3〕
- [x] T009 같은 세션에서 스냅샷 도우미 첫 시험: `NSHostingView` + `bitmapImageRepForCachingDisplay`·`cacheDisplay(in:to:)`로 `TextField`가 든 뷰 하나를 라이트·다크(`NSAppearance(named: .aqua)`·`.darkAqua`) PNG로 만들고, `TEST_RUNNER_MOKA_SNAPSHOT_DIR`로 넘긴 절대 경로에 파일이 생기는지 본다(research R8). 결과 PASS(2026-10-28, research R8 "결정 검증"). 라이트·다크 PNG 생성, `TEST_RUNNER_MOKA_SNAPSHOT_DIR`가 `MOKA_SNAPSHOT_DIR`로 전달됨. 다크 위쪽 밝은 띠는 배경을 `.frame` 뒤에 칠해 막는다(T037). 기록 위치 정정: ADR-0001이 아니라 research R8에 적었다(ADR-0001 본문은 고치지 않음) 〔단위 3〕

**확인 지점**: 6가지와 스냅샷 도우미 결과가 기록됐다(완료, research R4·R8, ADR-0008). FAIL이 있으면 Phase 4 이후 🔒 태스크의 설계를 다시 정하고(debate) 사람 승인을 받는다. PASS여도 🔒 태스크의 뷰 입력·`SettingsStore` 주입 모양을 Issue 본문에 확정한 뒤 시작한다

---

## Phase 4: User Story 1 - 할 일 하나를 넣고 타이머를 돌린다 (Priority: P1) 🎯 MVP

**Goal**: 빈 상태 → 펼친 판 클릭 → 제목 입력 → 기본 시간으로 시작 → 접힌 화면에 점·제목·남은 시간 → 완료 → 빈 상태

**Independent Test**: 화면 없이 `swift run moka-sim run Tests/MokaCoreTests/Fixtures/sim/us1-basic.json`이 `empty → running(1500) → expired(0) → empty`를 출력한다. 화면은 quickstart 6의 SC-001 순서로 사람이 본다

### Tests (Red)

- [ ] T010 [P] [US1] `Tests/MokaCoreTests/SimScenarioTests.swift`에 `moka-sim` v1 디코더·실행기 오류 시험을 쓴다(contracts/moka-sim-v1.md "입력"·"오류" 절):
  - `version`은 JSON 정수 `1`만, `timezone`은 필수이고 `TimeZone(identifier:)`가 nil이면 오류, `settings` 없으면 `{}`, `events[].at`은 ISO 8601·오프셋 필수(`Z` 허용)·초 단위(소수 초는 오류), `at`은 줄어들지 않아야 함
  - 모르는 `version`·`type`, 어느 깊이든 모르는 키(그 `type`에 없는 필드 포함, `JSONDecoder`는 모르는 키를 무시하므로 따로 검사), 필수 필드 없음, `45.0`·`"45"` 같은 정수 아님, 범위 밖 값, 공백뿐인 `title` → 입력 오류
  - 상태 표의 "2" 칸(예: 빈 상태에서 `start`) → 입력 오류
  - 오류 픽스처는 `Tests/MokaCoreTests/Fixtures/sim/errors/`에 두고, 파일마다 기대 오류 종류를 시험 코드의 표로 둔다
  〔단위 1b〕
- [ ] T011 [P] [US1] `Tests/MokaCoreTests/SimGoldenTests.swift`에 golden 시험을 쓴다: `Tests/MokaCoreTests/Fixtures/sim/` 바로 아래(`errors/` 제외)의 `*.json`마다 같은 이름의 `*.expected.jsonl`이 **반드시 있어야 하고**(없으면 FAIL), 실행기 출력을 그것과 바이트 단위로 비교한다. 출력 규칙은 계약 "출력" 절(키 순서 `seq, at, event, timer_state, chip_min, remaining_s`, 공백 없음, `null` 리터럴, 줄마다 `\n`, `at`은 UTC `Z`, 제목 출력 안 함). 픽스처 `us1-basic.json`(기본 25분 시작 → 끝 시각 `tick`에서 `expired`, `remaining_s` 0, `chip_min` 기본값 → `complete`)과 기대 출력을 함께 커밋한다 〔단위 1b〕

### Implementation (Green)

- [ ] T012 [US1] `Sources/MokaCore/Sim/`에 시나리오 타입·디코더(`SimScenario.swift`, 날짜 파싱은 지역 `ISO8601DateFormatter` 또는 `Date.ISO8601FormatStyle`), 실행기(`SimRunner.swift`: 모든 입력 이벤트에 대해 먼저 `apply(.tick, at:)`(암묵 tick, `set_default_quantum` 포함), 그다음 타이머 이벤트는 `NotchTimer.apply`, rejected는 입력 오류, `set_default_quantum`은 `QuantumSettings.writeDefault`로 `InMemorySettingsStore`에 쓰기, 이벤트 뒤 `invariantViolation`). 정수 판정(`45`는 받고 `45.0`·`1.0`은 거부)은 `JSONDecoder`에 맡기지 않고 숫자 원문 토큰으로 한다(예: `JSONSerialization` 뒤 원문 검사 또는 작은 자체 스캐너), 출력(`SimOutput.swift`: 문자열 직접 조립, `JSONEncoder` 안 씀), 종료 코드 매핑 순수 함수(`SimExitCode.swift`)를 구현한다. 결과는 출력 줄 전체 또는 오류 값 하나다(오류면 출력 없음). `SimExitCode`에 깨진 상태로 만든 불변식 위반을 넣어 1이 나오는 단위 시험을 더한다. T010·T011 PASS 〔단위 1b〕
- [ ] T013 [US1] `Sources/moka-sim/main.swift`를 `moka-sim run <file>`로 바꾼다: 파일 읽기 → 실행기 → 성공이면 표준 출력, 오류면 표준 오류 한 줄 → `SimExitCode`로 종료(인자 없음·모르는 하위 명령·파일 없음도 2). DB·네트워크·Keychain·환경 변수·`Date()`·`TimeZone.current`를 쓰지 않고 DB 경로 인자를 두지 않는다. `swift run moka-sim run Tests/MokaCoreTests/Fixtures/sim/us1-basic.json`의 출력과 종료 코드를 PR "완료 증거"에 붙인다 〔단위 1b〕
- [ ] T014 🔒 [US1] `App/Sources/AppState.swift`에 `@Observable @MainActor final class AppState`를 둔다(data-model §6). `running` 동안만 도는 1초 주기 화면 갱신 타이머와 `NSWorkspace.shared.notificationCenter`의 `didWakeNotification`에서 `apply(.tick, …)`를 부를 뿐 상태를 직접 바꾸지 않는다(research R1). 현재 시각은 `MokaClock`, 기본값은 주입받은 `SettingsStore`에서 읽는다. 화면에 남은 초를 쓰기 전에 `apply(.tick, …)`를 먼저 부른다(tick 없이 끝 시각이 지난 `running`을 그리면 `0:00`인데 시간 끝이 아닌 상태가 된다, #13). `os.Logger`(subsystem `dev.dongwon.moka`)로 상태 전이 이름만 남기고 제목은 남기지 않는다(R7) 〔단위 4〕
- [ ] T015 🔒 [US1] `App/Sources/Notch/NotchPanelHost.swift`에 직접 만든 패널 하나를 두고 접힘·펼침 뷰를 띄운다(ADR-0008, 노치 화면과 노치 없는 화면이 같은 패널을 쓴다. 이 태스크는 노치 화면 배치까지). 패널 구성(research R6): `NSPanel` 하위 클래스(`canBecomeKey = true`), styleMask `[.borderless, .nonactivatingPanel]`, `backgroundColor = .clear`, `hasShadow = false`, `collectionBehavior = [.canJoinAllSpaces, .stationary]`, level은 노치 위치 `.screenSaver`·떠 있는 창 `.statusBar`(둘 다 spike PASS 설정). 패널 프레임은 내용 크기(접힘 크기 ↔ 펼침 크기)로 `setFrame(_:display:animate:)`를 쓰고 큰 투명 패널을 두지 않는다. 띄우기는 `orderFrontRegardless()`(key를 가져가지 않음). 처음 띄울 화면은 `App/Sources/Notch/ScreenWatcher.swift`를 이 태스크에서 만들어 고른다: 현재 `NSScreen` 목록 → `[ScreenInfo]`(data-model §5 출처 규칙) → `chooseDisplayTarget`(T034)까지만. `NSScreen.screens.first`를 화면 선택에 직접 쓰지 않는다. `didChangeScreenParametersNotification` 구독은 T035. 노치 모양은 시안 v3.5 치수대로 직접 그린다(위쪽 양 끝 안쪽 오목 곡선 8pt, 아래 둥근 모서리. DynamicNotchKit `NotchShape`(MIT)를 옮기면 출처 주석). 애니메이션은 SwiftUI 크기 전환으로 시작한다. hover는 전역 모니터 대신 호스팅 뷰의 `NSTrackingArea`(`.mouseEnteredAndExited`, `.activeAlways`, `.inVisibleRect`)로 받는다(접힌 패널이 노치 자리에 늘 있으므로 들어옴·나감을 같은 방식으로 받는다). 마우스가 들어오면 펼치되 key window로 만들지 않는다. 펼친 판을 클릭하면 `makeKey()`하고 빈 상태면 제목 칸에 포커스를 준다(data-model §6 포커스 표). 시작·완료 뒤에는 `resignKey()`. 접힘은 `shouldStayExpanded`로 정한다. `project.yml`에는 `MokaStore` 의존만 더한다(노치 라이브러리 패키지 없음). 사람 확인: 노치 모양이 시안 v3.5와 같은지, 펼침·접힘이 바로 보이는지(SC-004), 시작·완료 뒤 key가 이전 앱으로 돌아가는지. 모양·애니메이션이 같은 원인으로 두 번 미달하면 ADR-0008 되돌림 조건대로 멈추고 사람 승인을 받는다 〔단위 4〕
- [ ] T016 🔒 [P] [US1] `App/Sources/Views/`에 시안 v3.5대로 뷰를 만든다. 뷰는 `AppState`가 아니라 값(`NotchTimer`, 남은 초, 콜백)을 받아 스냅샷 번들이 앱 없이 컴파일할 수 있게 한다. 남은 시간 글자는 `RemainingFormat.string`:
  - `CollapsedView.swift`: 빈 상태 회색 점(R-001), 도는 중 점·제목·남은 시간(접힌 화면에서 노치 왼쪽 표시 영역 폭 104pt, 넘치는 제목은 끝을 "…"로, R-006)
  - `ExpandedView.swift`: 빈 상태 입력칸(자리표시 "할 일 없음 — 무엇을 할까요?", R-001), 앞뒤 공백을 뺀 제목이 비면 Enter로 넘어가지 않음(R-002), 도는 중에는 제목(두 줄까지)·남은 시간·완료 버튼만(R-006). 판 폭 340pt. 노치 왼쪽 귀: 잔 아이콘(#A47864)과 "MOKA" 글자(#F5E9E1). 오른쪽 귀: 상태 글자(새 할 일 / 시간 고르기 / N분 집중 / 시간 끝)
  - 우클릭 메뉴("설정…"·"종료", T032)는 R-006의 보이는 요소에 들지 않는다. 뷰에는 넣지 않고 `NotchPanelHost`가 붙인다
  - `MokaColors.swift`: 주색 #A47864, 기본 버튼 세로 그라데이션 #A47864→#85604F, 보조색(크레마) #E6C7B4, 밝은 바탕색(폼) #F5E9E1, 시간 끝 #E5533D
  〔단위 4〕
- [ ] T017 🔒 [US1] `App/Sources/MokaApp.swift`에서 `AppState`를 만들고 메뉴 막대 항목을 "설정…"과 "종료"만 둔다(R-012). 메뉴 막대 아이콘은 시안의 넓은 잔 + 김 한 줄(S3) 단색 템플릿 이미지(`App/Sources/Assets.xcassets`, 원본은 시안 HTML의 SVG에서 옮김). 할 일과 타이머는 메모리에만 둔다(R-014) 〔단위 4〕

**확인 지점**: `swift test` PASS, `moka-sim` us1 golden PASS, 앱 빌드 PASS. 화면은 사람이 SC-001로 확인

---

## Phase 5: User Story 2 - 작업 시간을 바꿔 고른다 (Priority: P1)

**Goal**: 칩에서 15/25/45/60분이나 직접 입력(1~180)으로 시작

**Independent Test**: 화면 없이 `us2-choose-45.json`이 `chip_min` 45, `remaining_s` 2700을 출력하고, 직접 입력 규칙 시험이 0·181·빈 값·숫자 아님·소수를 거부한다

### Tests (Red)

- [ ] T018 [P] [US2] `Tests/MokaCoreTests/QuantumChipTests.swift`에 시험을 쓴다:
  - `FR-05 R-004`: 프리셋은 15, 25, 45, 60. `parseCustom`은 `Int(_:)`가 1~180이면 값: `"1"`·`"180"`·`"90"`·`"+45"`는 받고, `"0"`·`"181"`·`""`·`"abc"`·`"4.5"`·`" 45"`는 nil
  - `FR-06 R-006`: `RemainingFormat.string`: 1500→`25:00`, 599→`9:59`, 3599→`59:59`, 3600→`1:00:00`, 5400→`1:30:00`, 0→`0:00`
  - `FR-06 R-009`: `shouldStayExpanded(pinned:focused:hovering:)`는 셋 중 하나라도 참이면 참, 모두 거짓이면 거짓
  〔단위 1a〕
- [ ] T019 [P] [US2] 픽스처 `Tests/MokaCoreTests/Fixtures/sim/us2-choose-45.json`과 기대 출력을 더한다: 45분 선택 → 시작(`remaining_s` 2700) → 시간 끝(`chip_min` 기본값) → `choose_quantum` 15 → 다시 시작(R-010) → 완료. 오류 픽스처 `errors/unknown-type.json`, `errors/time-reversed.json`, `errors/unknown-key.json`, `errors/start-in-empty.json`은 T010 방식으로 오류 값을 확인한다 〔단위 1b〕

### Implementation (Green)

- [ ] T020 [US2] `Sources/MokaCore/QuantumChip.swift`에 data-model §3의 `QuantumChip`, `RemainingFormat`, `shouldStayExpanded`를 구현한다. T018 PASS 〔단위 1a〕
- [ ] T021 🔒 [US2] `App/Sources/Views/QuantumChipView.swift`에 macOS 분할 컨트롤(15분|25분|45분|60분|직접…)과 직접 입력칸을 만든다. `parseCustom`이 nil이면 시작 버튼을 막는다. Enter나 시작 한 번으로 칩 값으로 시작한다(R-003). 버튼은 둥근 사각형 push button, 기본 버튼은 #A47864→#85604F 세로 그라데이션 〔단위 4〕

**확인 지점**: US1·US2를 함께 화면 없이 재현할 수 있다

---

## Phase 6: User Story 3 - 시간이 끝나면 알아챈다 (Priority: P1)

**Goal**: 0:00에서 멈추고 노치가 자동으로 펼쳐져 "시간 끝"을 보이되 키보드 포커스를 가져가지 않는다

**Independent Test**: 화면 없이 `us3-sleep.json`(잠자기를 `at` 건너뛰기로 표현)의 깨어난 첫 `tick`이 `expired`. 화면은 quickstart 6의 1분 타이머로 SC-003(다른 앱 타이핑 0자)과 R-009(마우스 넣었다 빼도 유지)를 사람이 본다

### Tests (Red)

- [ ] T022 [P] [US3] 픽스처 `Tests/MokaCoreTests/Fixtures/sim/us3-sleep.json`과 기대 출력을 더한다: 25분 시작 → 10분 뒤 `tick`(`remaining_s` 900) → 끝 시각을 지난 시각으로 건너뛴 `tick` → `expired`, `remaining_s` 0 → `complete` → `empty`(R-008, SC-002 (a)). 끝 시각 뒤 바로 `complete`가 오는 줄(암묵 tick)도 하나 넣는다 〔단위 1b〕

### Implementation

- [ ] T023 🔒 [US3] `App/Sources/AppState.swift`에서 `running → expired` 전이를 받으면 `isExpanded = true`, `isPinnedOpen = true`로 바꾼다. 창을 key window로 만들지 않고 앱을 활성화하지 않는다. 사용자가 펼친 판을 클릭했을 때만 입력 포커스를 준다(data-model §6 포커스 표, spike 4번 결과를 따른다). 시작·완료를 누르면 `isPinnedOpen = false`(R-009). 소리·시스템 알림·자동 연장은 넣지 않는다(R-008) 〔단위 4〕
- [ ] T024 🔒 [US3] `App/Sources/Views/ExpiredView.swift`에 "시간 끝"(#E5533D), 칩(기본값으로 채움, data-model §2), 시작·완료 버튼을 만든다. 시작은 같은 할 일로 다시 돈다(R-010), 완료는 빈 상태(R-007) 〔단위 4〕

**확인 지점**: 마일스톤 1 P1 범위(US1~US3) 완성

---

## Phase 7: User Story 4 - 기본 작업 시간을 설정한다 (Priority: P2)

**Goal**: 메뉴 막대 "설정…"에서 `default_quantum_min`을 바꾸고 재시작 뒤에도 남는다

**Independent Test**: `swift test`의 `MokaStoreTests`가 마이그레이션 이름, 스키마 스냅샷, 테스트 DB 경로 가드, 왕복을 확인한다. 화면 없이 `us4-default-change.json`이 도는 중 `set_default_quantum` 뒤에도 `remaining_s`가 그대로이고 다음 `enter_title`의 `chip_min`이 새 값임을 보인다(R-013)

### Tests (Red)

- [ ] T025 [P] [US4] `Tests/MokaStoreTests/MigrationTests.swift`와 `Tests/MokaStoreTests/Support/TestDatabase.swift`에 시험을 쓴다:
  - `ADR-0004 FR-16`: 시험 파일 안의 리터럴 `["v1_settings"]` == `MokaMigrations.migrator.migrations`(등록에 쓰는 상수와 비교하지 않는다, ADR-0007)
  - `ADR-0004 FR-16`: 메모리 DB에 마이그레이션을 돌린 뒤 `MokaDatabase.schemaSQL`(data-model §4 질의·형식)이 `schema/moka-schema.sql`과 같다(파일은 `#filePath` 기준). 다르면 실제 텍스트를 `Issue.record`로 출력한다
  - `ADR-0004`: 테스트 DB 경로 가드 — `TestDatabase`가 돌려주는 경로는 `:memory:`이거나 `FileManager.default.temporaryDirectory` 아래이고 `dev.dongwon.moka`를 포함하지 않는다. 모든 MokaStore 시험은 이 도우미로만 DB를 연다
  〔단위 2〕
- [ ] T026 [P] [US4] `Tests/MokaStoreTests/GRDBSettingsStoreTests.swift`에 왕복 시험을 쓴다: 임시 디렉터리 아래 **없는 하위 폴더** 경로로 `MokaDatabase.open(at:)` → 폴더가 생기고 열림, 45 저장 → 닫고 다시 열어 45(R-012 재시작 뒤 유지), 같은 키 두 번 저장은 UPSERT로 행 하나, seed 행 없음 〔단위 2〕
- [ ] T027 [P] [US4] 픽스처 `Tests/MokaCoreTests/Fixtures/sim/us4-default-change.json`과 기대 출력을 더한다(quickstart 2의 세 번째 시나리오) 〔단위 1b〕

### Implementation (Green)

- [ ] T028 [US4] `Sources/MokaStore/Migrations.swift`에 `MokaMigrations.migrator`를 둔다. `v1_settings`는 raw SQL 한 문장 `CREATE TABLE settings(key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)`(data-model §4)만 실행하고 seed 행을 넣지 않는다. `eraseDatabaseOnSchemaChange`를 켜지 않는다 〔단위 2〕
- [ ] T029 [US4] `schema/moka-schema.sql`에 첫 스냅샷을 만든다(T025가 `Issue.record`로 낸 텍스트를 그대로 옮긴다). macOS `swift test` PASS는 필수다. 리눅스는 docker(`docker run --rm -v "$PWD":/w -w /w swift:6.3.3-noble bash -c "apt-get update -qq && apt-get install -y -qq --no-install-recommends libsqlite3-dev >/dev/null && swift test --scratch-path /tmp/.build-linux"`)로 보고, docker를 못 쓰면 NOT_RUN과 이유를 적고 PR CI `core-test` 결과로 갈음한다(research R2 선행 확인). 텍스트가 다르면 멈추고 PR "사람이 볼 결정"에 올린다(ADR-0004 재검토 트리거). 스냅샷 추가 자체도 "사람이 볼 결정"에 적는다 〔단위 2〕
- [ ] T030 [US4] `Sources/MokaStore/MokaDatabase.swift`에 `open(at:)`(상위 폴더 생성 → 열기 → 마이그레이션, 경로는 받은 그대로)과 `schemaSQL(_:)`을 더하고, `Sources/MokaStore/GRDBSettingsStore.swift`에 `SettingsStore` 구현(UPSERT)을 둔다. 제품 코드에 테스트 빌드 판별 분기를 두지 않는다. 기존 `inMemory()`·`healthCheck`는 유지한다. T025·T026 PASS 〔단위 2〕
- [ ] T031 [US4] T027 golden이 T012 실행기로 PASS하는지 확인한다(`set_default_quantum`은 T012에서 구현) 〔단위 1b〕
- [ ] T032 🔒 [US4] `App/Sources/Settings/SettingsView.swift`를 SwiftUI `Settings` scene으로 만든다(메뉴의 "설정…"은 `SettingsLink`, 창을 앞으로 가져오려 `NSApp.activate`). 기본 작업 시간 입력은 제출(Enter)이나 포커스를 잃을 때 `QuantumSettings.writeDefault`로 저장하고, 범위 밖이면 칸을 이전 값으로 되돌린다. `MokaApp.swift`에서 `MokaDatabase.open(at:)`으로 `~/Library/Application Support/dev.dongwon.moka/moka.sqlite`를 열어 `GRDBSettingsStore`로 쓴다. 못 열면 `InMemorySettingsStore`로 동작하고 `os.Logger`에 오류 종류를 남긴다(research R2). 앱 코드만 이 경로를 쓴다. 펼친 판에 우클릭 메뉴로 "설정…"과 "종료"를 둔다(R-012, 메뉴 막대가 넘쳐 아이콘이 노치 뒤로 숨을 때 대비). `.contextMenu`는 `NotchPanelHost`가 뷰를 감쌀 때 붙인다(뷰는 값·콜백만 받는 원칙 유지). 빈 상태·도는 중·시간 끝 모두에 둔다. "설정…"은 `@Environment(\.openSettings)`(macOS 14+)로 열고 `NSApp.activate()`를 부른다. 사람 확인: 우클릭이 key를 가져가는지, nonactivating 패널에서 우클릭 메뉴가 뜨는지, 거기서 연 설정 창이 앞으로 오는지. FAIL이면 두 번째 시도 없이 우클릭 메뉴를 빼고 spec "대안과 위험"의 알려진 위험으로 기록한다 〔단위 4〕

**확인 지점**: 재시작 뒤 기본값 유지는 quickstart 6 마지막 줄로 사람이 확인

---

## Phase 8: User Story 5 - 노치가 없는 화면에서도 보인다 (Priority: P2)

**Goal**: 노치가 있는 화면을 우선하고, 없으면 주 화면 메뉴 막대 아래 중앙 떠 있는 창

**Independent Test**: `DisplayTargetTests`가 화면 목록 → 표시 위치 규칙을 확인한다. 화면은 quickstart 6의 덮개 닫기로 사람이 SC-005를 본다

### Tests (Red)

- [ ] T033 [P] [US5] `Tests/MokaCoreTests/DisplayTargetTests.swift`에 data-model §5 표를 옮긴다(`FR-06 R-011`): 노치 화면 + 외부 모니터 → 노치 화면 `.notch`, 외부 모니터만 → `isMain` 화면 `.floating`, `isMain`이 없으면 첫 화면 `.floating`, 노치 화면 둘 → 목록 첫 노치 화면, 화면 0개 → nil 〔단위 1a〕

### Implementation

- [ ] T034 [US5] `Sources/MokaCore/DisplayTarget.swift`에 data-model §5의 `ScreenInfo`, `DisplayTarget`, `chooseDisplayTarget(_:)`를 구현한다. T033 PASS 〔단위 1a〕
- [ ] T035 🔒 [US5] `App/Sources/Notch/ScreenWatcher.swift`(T015에서 만든 화면 고르기)에 `NSApplication.didChangeScreenParametersNotification` 구독을 더한다. 입력 규칙은 data-model §5(`id`는 `NSScreenNumber`, `hasNotch`는 `safeAreaInsets.top > 0`, `isMain`은 `NSScreen.screens.first`이고 `NSScreen.main`이 아니다). 알림마다 새 `DisplayTarget`을 계산해 `NotchPanelHost.move(to:)`를 부르고, 호스트는 `setFrame`으로 옮긴다(창을 다시 만들지 않는다 — ADR-0008 결함 사유). 타이머 상태와 `isPinnedOpen`은 건드리지 않는다 〔단위 5〕
- [ ] T036 🔒 [US5] `App/Sources/Notch/NotchPanelHost.swift`(T015)에 노치 없는 화면 배치를 더한다: `move(to:)`가 `.floating`을 받으면 같은 패널을 노치 모양 없이 level `.statusBar`로 메뉴 막대 아래 중앙에 고정(드래그 없음)한다. 옮기기는 T035와 같이 `setFrame`이고 창을 다시 만들지 않는다. 접힘·펼침·hover·포커스 규칙은 T015 그대로다. 라이트 모드의 "MOKA" 글자는 #85604F. 사람 확인: 덮개를 닫고 외부 모니터만 쓸 때(spike 5 외부 모니터 NOT_RUN 몫) 〔단위 5〕

**확인 지점**: 다섯 이야기 모두 완성

---

## Phase 9: Polish & Cross-Cutting

- [ ] T037 🔒 `App/Tests/MokaAppTests/SnapshotHelper.swift`에 `renderPNG(view:size:appearance:) -> Data`(T009 결과, 배경은 `.frame` 뒤에 칠해 다크 위쪽 투명 띠를 막는다)를 두고, `App/Tests/MokaAppTests/ScreenStateSnapshotTests.swift`에서 빈 상태, 입력, 칩 펼침, 도는 중, 시간 끝, 떠 있는 창을 라이트·다크로 만든다. sanity 단언만 한다(크기 0 아님, 단색 아님, 라이트≠다크). 출력은 `TEST_RUNNER_MOKA_SNAPSHOT_DIR`(xcodebuild가 접두사를 떼고 넘김) 또는 `#filePath`로 구한 저장소 루트의 `.verify/snapshots/001/`(커밋 안 함, 도우미가 폴더 생성). `project.yml`에 `MokaAppTests`(type `bundle.unit-test`, platform macOS, sources `App/Sources/Views`·`App/Tests/MokaAppTests`, dependencies `- package: Moka, product: MokaCore`, settings `SWIFT_VERSION: "6.0"`·`GENERATE_INFOPLIST_FILE: YES`, TEST_HOST 없음)를 더하고 `Moka` 타깃에 `scheme: { testTargets: [MokaAppTests] }`를 둔다. CI job은 두지 않는다. 마일스톤 1 완료 조건이 아니며 밀리면 버퍼(11/8~9)로 간다 〔단위 5〕
- [ ] T038 🔒 스냅샷 방법 ADR(그때의 다음 번호)을 `adr/`에 쓴다(D4, research R8). "생성 PASS는 화면 정합 증거가 아니다"와, ADR-0003의 "앱 UI 테스트는 XCUITest" 문구와 다른 점(XCTest 단위 번들)을 적는다 〔단위 5〕
- [ ] T039 🔒 모은 PNG를 `~/Dev/ai-platform/projects/moka/design/pr-<번호>/index.html`에 시안과 나란히 두고 PR "완료 증거"에 경로를 적는다(저장소 밖, 커밋 안 함) 〔단위 5〕
- [ ] T040 quickstart 3 오류 주입: golden 기대값 하나, 마이그레이션 열 하나, 가짜 마이그레이션 등록 하나를 일부러 넣어 `swift test`가 FAIL하고 종료 코드가 0이 아닌지 확인한 뒤 되돌린다. 커밋하지 않고 결과만 PR에 적는다 〔단위 1·2〕
- [ ] T041 단위 1a·1b·2 PR마다 quickstart 1~3 결과 표(PASS/FAIL/SKIP/NOT_RUN)를 붙인다 〔단위 1·2〕
- [ ] T042 🔒 사람이 quickstart 4~6을 돌려 결과 표를 마지막 PR에 붙인다(R-014 재시작 뒤 빈 상태 포함) 〔단위 4·5〕

---

## Dependencies & Execution Order

### Phase 순서

- Setup(1) → Foundational(2) = 단위 1a(+T018·T020·T033·T034) → 병합 → 단위 1b와 단위 2를 병렬
- Spike(3)는 사람이 있는 낮 세션(완료 2026-10-28, T008·T009 PASS)
- 🔒 태스크는 전부 Spike PASS 뒤. 그 안에서는 US1(T014~T017) → US2(T021)·US3(T023·T024) → US4(T032)·US5(T035·T036) → Polish(T037~T039, T042)

### 태스크 사이 의존

- T006 ← T004, T007 ← T005, T020 ← T018, T034 ← T033
- T012 ← T006·T007·T010·T011, T013 ← T012, T031 ← T027·T012
- T025·T026·T030 ← T007(1a 병합), T030 ← T025·T026·T028·T029, T032 ← T030·T017
- T015·T016·T017 ← T014, T015 ← T034, T021 ← T016, T023 ← T014, T024 ← T021, T036 ← T015·T016·T035
- T037 ← T016·T021·T024·T036, T038 ← T037, T039 ← T037

### 작업 단위 ↔ Issue (plan "작업 단위")

| 단위 | 태스크 | 무인 가능 | 먼저 할 일 |
|---|---|---|---|
| 1a MokaCore 값 타입·규칙 | T001~T007, T018, T020, T033, T034, T040·T041 일부 | 예 | 첫 Issue(조언 노트의 #1 "돌아가는 뼈대" 중 Core 몫) |
| 1b `moka-sim` v1 | T010~T013, T019, T022, T027, T031, T040·T041 일부 | 예 | 1a 병합 뒤 |
| 2 MokaStore 첫 마이그레이션 | T025, T026, T028~T030, T040·T041 일부 | 예 | 1a 병합 뒤, 1b와 병렬 |
| 3 spike + 스냅샷 도우미 첫 시험 | T008, T009 | 아니오(사람 눈·손) | 낮 세션 |
| 4 앱 노치 화면 | T014~T017, T021, T023, T024, T032, T042 일부 | 아니오 | 3 PASS와 2 병합 뒤 |
| 5 떠 있는 창 + 스냅샷 번들 + ADR | T035~T039, T042 일부 | 아니오 | 4 뒤 |

### Parallel Opportunities

- T002·T003 동시, T004·T005 동시, T018·T033 동시
- 1a 병합 뒤 1b와 단위 2는 서로 다른 곳(`Sources/MokaCore/Sim`·`Sources/moka-sim`·`Tests/MokaCoreTests` vs `Sources/MokaStore`·`Tests/MokaStoreTests`·`schema/`)을 고쳐 implementer 둘로 병렬
- T019·T022·T027은 서로 다른 파일이라 동시에 쓸 수 있다
- 🔒 쪽은 T016(뷰)과 T035(ScreenWatcher)가 겹치지 않는다

### Parallel Example: 1a 병합 뒤

```text
implementer A: "단위 1b — T010~T013, T019, T022, T027, T031 (MokaCore/Sim·moka-sim·Fixtures만)"
implementer B: "단위 2 — T025, T026, T028~T030 (MokaStore·Tests/MokaStoreTests·schema만)"
```

---

## Implementation Strategy

### MVP First

1. 1a → 1b: 화면 없이 `moka-sim`으로 마일스톤 1 상태 변화를 보인다(SC-006)
2. 단위 2를 1b와 병렬
3. 낮 spike(Phase 3) PASS → US1 앱(T014~T017)이 마일스톤 1 완료 조건 "노치에 할 일 하나와 고른 시간의 타이머"
4. US2·US3 → US4·US5 → Polish(스냅샷은 밀리면 버퍼)

### 무인 실행 경계

- 밤에는 🔒 없는 태스크(MokaCore, MokaStore, `moka-sim`, 빌드)만 돈다. 🔒 태스크는 spike PASS 뒤에도 무인으로 돌리지 않는다
- 스키마 스냅샷(T029), 공개 계약 픽스처 추가(T011·T019·T022·T027)는 PR "사람이 볼 결정"에 적는다
