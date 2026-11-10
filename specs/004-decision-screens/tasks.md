---

description: "spec 004 판단 결과 화면 연결 작업 목록"
---

# Tasks: 판단 결과 화면 연결 (마일스톤 3 나머지)

**Input**: `specs/004-decision-screens/`의 plan.md, spec.md(R-301~R-319), research.md(R1~R10), data-model.md, quickstart.md. 화면 시안 `~/Dev/ai-platform/projects/moka/design/004-mockup.html`(저장소 밖, T002에서 사용자 확정)

**Tests**: 넣는다. 헌법 II와 AGENTS.md "실패하는 테스트를 먼저 쓰고 실패를 확인한 뒤 구현한다". 테스트 태스크마다 Red 커밋을 남기고, 구현 태스크에서 Green 커밋을 남긴다.

**Organization**: 사용자 이야기(US1~US4)별로 묶는다. 각 태스크 끝의 `〔단위 N〕`은 plan "작업 단위" 번호이고 Issue 하나가 된다(아래 "작업 단위와 Issue").

**원본 규칙**: 규칙, 값, 모양은 data-model.md가 원본이다. 태스크는 절 번호를 가리키고 문장을 옮겨 적지 않는다. 시험은 그 절의 규칙을 빠짐없이 덮는다.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 다른 파일을 고치고 아직 안 끝난 태스크에 기대지 않아 병렬로 할 수 있다
- **[Story]**: US1~US4(spec.md)
- **[사람]**: 화면 확정이나 실제 판단 결과, 새 사용자 첫 실행을 사람이 확인해야 끝난다
- **[화면 뒤]**: T002(시안 확정) 뒤에만 시작한다
- 이 spec에는 승인 항목이 없다(plan "승인 항목"). PR "사람이 볼 결정"에는 debate로 정한 Q1~Q3 확인과 시안 확정만 올린다
- 이 파일의 "확인 지점"은 Phase 완료 조건이다

## 공통 규칙 (모든 태스크)

- 테스트 표시 이름은 PRD FR과 R-ID로 시작한다(ADR-0003): R-301~R-305 `FR-04`, R-306~R-312 `FR-13`, R-313~R-315 `FR-21`, R-316~R-318 `FR-14`, R-319는 각 시험의 공통 조건. MokaCore는 Swift Testing, 앱 시험 번들(`MokaAppTests`)은 XCTest.
- 타입과 함수 이름, 모양은 data-model §1·§4·§5를 따른다. 거기 없는 작은 이름은 구현 PR에서 정하고 PR "가정"에 적는다.
- 시각은 주입한 값과 `GregorianCalendar.make(timeZone:)`(고정 `Asia/Seoul`)로 시험한다. 실제 시간을 기다리지 않는다. 게이트 기다림은 `FakeDecisionProvider`를 붙잡고 풀어 만든다.
- 실제 판단 API를 시험·CI·`moka-sim`에서 부르지 않는다. `FakeDecisionProvider`, `InMemoryKeyStore`, `InMemoryScoreStore`만 쓴다. 실제 Keychain과 앱 DB를 시험에서 열지 않는다. 에이전트는 Keychain 값을 조회하지 않는다.
- 가짜 할 일과 가짜 첫 행동만 쓴다(예: "가짜 할 일 A", "가짜 첫 행동").
- 바꾸지 않는 것: 스키마와 스냅샷 `schema/moka-schema.sql`, `questions.json`, `DecisionProvider`, `moka-sim` 형식과 golden, `UserAction`·`SchedulerChoice` 값, `Package.swift`, CI. 기존 스냅샷 참조 이미지도 그대로다(새 뷰 인자의 기본값으로, research R9). `@unchecked Sendable`을 쓰지 않는다.
- 게이트 줄, 넘기기, 키 값을 로그와 행동 로그에 남기지 않는다.
- 화면 문구는 고객용 해요체이고 확정 시안 글자를 그대로 쓴다.
- 검증 명령: `swift test`, `cd tuning && python3 -m pytest`, 앱 빌드 `xcodegen generate && xcodebuild build -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`, 앱 시험 quickstart 4. 결과는 PASS/FAIL/SKIP/NOT_RUN.

---

## Phase 1: Setup

- [ ] T001 기준 상태 확인: `swift test`, `cd tuning && python3 -m pytest`, 앱 빌드, quickstart 4의 앱 시험을 돌려 기존 시험이 PASS인지 기록하고, 기존 스냅샷 참조 이미지 폴더의 파일 해시 목록을 PR "완료 증거"에 적는다(SC-310 비교 기준) 〔단위 1〕
- [x] T002 [사람] 시안 `~/Dev/ai-platform/projects/moka/design/004-mockup.html`을 사용자에게 보이고 "확정할 것" 목록(이유 줄 표기, 게이트 문구와 자리, 온보딩 키 단계 문구와 발급 링크 주소, 키 확인 한 줄 문구)을 확정받는다. 확정 전에는 [화면 뒤] 태스크를 시작하지 않는다 〔단위 1〕
  - 사용자 확정 2026-11-10. 1~8번과 12~14번은 단위 3, 9~11번과 15번은 단위 4가 쓴다.
  - 게이트 문구는 사용자 의견으로 바뀌었다. 제목 "어디서 시작할지 막연해 보여요", 설명 "2분 안에 바로 할 수 있는 첫 행동을 한 줄 적어 주세요. 판단 모델이 다시 확인하고, 노치를 펼치면 제목 아래 보여요."(spec R-307, data-model §5)
  - 확정할 것 9번(사용자 확정이 아니라 시안에 값이 없어 정한 작은 가정 2026-11-10, 사람 확인 대기): 게이트가 열린 채 새 할 일 제목 칸, 다른 할 일 목록, 두 줄 입력이 열리면 그동안 게이트를 숨기고, 닫히면 다시 보인다(data-model §5)

---

## Phase 2: Foundational

없음. spec 003의 판단 결과, 질의 실행기, 보내기 장부, 키 보관함을 그대로 쓴다(plan Summary).

---

## Phase 3: User Story 1 - 노치를 펼치면 이 할 일이 왜 떴는지 보인다 (Priority: P1) MVP

**Goal**: 시작 전과 도는 중 펼친 화면에 이유 줄(D-n, 손해, 미룬 횟수).

**Independent Test**: spec US1 Independent Test.

### Tests (Red)

- [ ] T003 [P] [US1] `Tests/MokaCoreTests/ReasonLineTests.swift`: data-model §2 전체(남은 날 넷, 하루 시작 시각 전후의 오늘, `America/New_York` 일광절약시간 전환일을 사이에 둔 마감에서도 남은 날이 `LocalDay` 날짜 차와 같음(시각 차를 86400으로 나누지 않음), 손해 반올림 경계 0.24·0.25·0.74·0.75, 손해 없음 셋(키 없음으로 `usable` 빔, 판단 결과 없음, 질문 버전 다름), 미룬 횟수 0, 손해 없을 때 구분자 빠짐)를 쓰고 실패를 확인한다(`FR-04 R-302`, `FR-04 R-303`, `FR-04 R-304`, SC-301, SC-302) 〔단위 1〕
- [ ] T005 [US1] `App/Tests/MokaAppTests/AppDecisionTests.swift`: `reasonLine`이 시작 전·도는 중에만 값이 있고, 빈 상태와 시간 끝에는 `nil`, 답이 저장되면 손해가 바뀌고 노치 할 일(`session.taskID`)은 그대로(spec US1-5), 키를 지우면 손해가 빠짐. 실패를 확인한다(`FR-04 R-305`) 〔단위 2〕
- [x] T007 [US1] [화면 뒤] `App/Tests/MokaAppTests/ScreenStateSnapshotTests.swift`에 `test_R301_draftReason`, `test_R301_draftReasonNoLoss`, `test_R301_runningReason`(라이트·다크, 이어서 할 일 줄이 있는 경우 하나 포함)을 확정 시안대로 쓰고 실패를 확인한다(`FR-04 R-301`) 〔단위 3〕

### Implementation (Green)

- [ ] T004 [US1] `Sources/MokaCore/Decision/ReasonLine.swift`: `DeadlineDistance`, `ReasonLine.make(task:usable:questions:today:calendar:)`, `ReasonText.line(_:)`(data-model §1·§2). 손해 말은 `questions.questions["impact"]`의 옵션 목록에서 읽는다. T003 PASS 〔단위 1〕
- [ ] T006 [US1] `App/Sources/AppState.swift`: 계산 속성 `reasonLine: String?`(data-model §4, 오늘은 `logicalToday`, `usable`은 `input(at:)`의 `scoring`과 같은 값). T005 PASS 〔단위 2〕
- [x] T008 [US1] [화면 뒤] `App/Sources/Views/ExpandedView.swift`에 `reasonLine: String? = nil` 인자와 제목 아래 한 줄(시작 전, 도는 중), `App/Sources/Views/NotchContentView.swift`와 `App/Sources/Notch/NotchPanelHost.swift`가 AppState 값을 넘긴다(data-model §5). 기존 스냅샷 호출은 고치지 않는다. T007 PASS, 기존 스냅샷 PASS 〔단위 3〕
- [ ] T009 [사람] [US1] quickstart 6-1(확인용 빌드, 자기 키). 결과는 PASS/FAIL만 〔단위 3〕

**확인 지점**: SC-301·SC-302. 노치 펼침에서 이유 줄이 보인다.

---

## Phase 4: User Story 2 - 막연한 할 일은 첫 행동 한 줄을 적고 시작한다 (Priority: P1)

**Goal**: concrete가 임계값 미만인 할 일이 시작 전으로 뜨면 게이트, 제출, 재판정, 통과 또는 넘기기.

**Independent Test**: spec US2 Independent Test.

### Tests (Red)

- [ ] T010 [P] [US2] `Tests/MokaCoreTests/ConcreteGateTests.swift`: data-model §3 판정 1~3 전체(열림 조건, 열리지 않는 넷(시작 전 아님, 통과함, 점수 없음, 임계값 이상), 물을 수 없으면 안 열림, 기다림 중: 물을 수 없게 되면 통과, 실패 해시면 통과, 해시 같은 새 결과 이상이면 통과, 미만이면 다시 묻기, 세 번째 제출 뒤 미만이면 통과, 해시 다른 결과로는 판정하지 않음, 해시가 다시 바뀌면 새 해시를 기다림)를 쓰고 실패를 확인한다(`FR-13 R-306`, `FR-13 R-308`, `FR-13 R-309`, SC-304, SC-305) 〔단위 1〕
- [ ] T012 [US2] `App/Tests/MokaAppTests/AppGateTests.swift`(새 파일, `AppTestSupport.swift`의 `makeState`와 `FakeDecisionProvider` 붙잡기를 씀): 아래를 쓰고 실패를 확인한다(`FR-13 R-307`, `FR-13 R-308`, `FR-13 R-309`, `FR-13 R-310`, `FR-13 R-312`, SC-303~SC-306) 〔단위 2〕
  - 게이트가 `.asking`·`.checking`인 동안 노치의 이어서 할 일 표시 값이 숨김이고, 통과 뒤 다시 보임. 통과 때 접힌 3초 표시(`showsFirstActionCollapsed`)가 켜지지 않음
  - concrete 0.3 판단 결과로 시작 전이 되면 `gatePhase == .asking`, 0.7이면 `.closed`, 키 없음·`keyNeedsCheck`·판단 결과 없음이면 `.closed`
  - 시작 전으로 뜬 뒤 판단 결과가 저장되면 그때 열림, 도는 중에는 열리지 않음
  - 제출하면 첫 행동이 저장되고 질의 1건이 새 해시로 나감, 붙잡은 동안 `.checking`이고 버튼(시작, 다른 할 일)이 동작함
  - 풀어서 0.8이면 `.closed`와 `firstAction` 표시, 0.3이면 `.asking`이고 칸에 지난 줄, 세 번째 뒤 0.3이면 통과
  - 실패 일곱 종류(spec 003 SC-205 목록)와 401, 키 지움에서 그 제출로 통과, 노치 상태와 타이머 그대로
  - 같은 줄 다시 제출이면 질의 0건이고 지금 판단 결과로 판정
  - 넘기기면 통과이고 첫 행동·질의 그대로, 바꾸기로 다시 떠도 안 열림
  - 시작 버튼이면 닫히고 다음 시작 전에 남은 횟수로 다시 열림, 노치 할 일이 바뀌면 닫힘
  - 첫 행동 저장 실패면 `.asking`과 실패 표시, 횟수 그대로
  - 게이트 제출 뒤 체크포인트 다음 할 일 줄을 저장하면 그 줄이 남고, 반대 순서면 게이트 줄이 남음(spec 위험 3)
  - 행동 로그 줄 수가 제출과 넘기기 전후로 같음
  - 앱을 다시 만든 `AppState`(같은 저장소)에서는 기록이 없어 다시 열림(R-309)
- [x] T014 [US2] [화면 뒤] `App/Tests/MokaAppTests/ScreenStateSnapshotTests.swift`에 `test_R307_gateAsking`, `test_R307_gateChecking`, `test_R307_gateSaveFailed`(라이트·다크, 할 일에 첫 행동이 있는 상태로 찍어 제목 아래 이어서 할 일 줄이 숨는 것을 함께 확인, R-311)를 확정 시안대로 쓰고 실패를 확인한다(`FR-13 R-307`) 〔단위 3〕

### Implementation (Green)

- [ ] T011 [US2] `Sources/MokaCore/Decision/ConcreteGate.swift`(`GateRecord`, `GatePhase`, 판정 함수, data-model §1·§3)와 `Sources/MokaCore/Defaults.swift`의 `concreteGateMaxSubmissions = 3`. 임계값은 `questions.thresholds[questions.model]?["concrete"]`. T010 PASS 〔단위 1〕
- [ ] T013 [US2] `App/Sources/AppState.swift`: `gateRecords`, `gateWaitingTaskID`, `gatePhase`, `gateDraftText`, `gateSaveFailed`, `submitFirstAction(_:)`, `skipGate()`, `refreshGate()`와 부르는 곳(data-model §3 "판정 시점", §4), 시작과 노치 할 일 변경 때 닫기. 첫 행동 쓰기는 `write(StoreBatch(updatedTasks:))` 뒤 `reloadTasks()`이고 질의를 따로 부르지 않는다. 실패를 장부에 적는 자리에서 `refreshGate()`를 부른다. T012 PASS 〔단위 2〕
- [x] T015 [US2] [화면 뒤] `App/Sources/Views/ExpandedView.swift`에 `gate: GateInput? = nil` 인자와 게이트 화면(묻는 중, 확인하는 중, 저장 실패, "지금은 넘기기"), 시작 버튼 단축키 조건 `draftInput.isEnteringTitle || gate?.phase == .asking`이면 뗌, 게이트가 `asking`이면 "직접…" 분 칸 Enter도 시작하지 않음, `asking`·`checking`이면 이어서 할 일 줄 숨김(data-model §5). `NotchContentView`·`NotchPanelHost`가 값과 콜백을 넘긴다. 입력 칸 Enter는 제출이다. T014 PASS, 기존 스냅샷 PASS 〔단위 3〕
- [ ] T016 [사람] [US2] quickstart 6-2·6-3. 게이트가 열리지 않으면 6-2·6-3은 SKIP으로 적고 T012에 맡긴다. 입력 칸이 열린 동안 Enter가 시작하지 않는지도 이때 본다 〔단위 3〕

**확인 지점**: SC-303~SC-306. 통과한 첫 행동이 제목 아래 보인다.

---

## Phase 5: User Story 3 - 처음 켤 때 키를 넣거나 건너뛴다 (Priority: P2)

**Goal**: 온보딩 첫 단계가 키 단계.

**Independent Test**: spec US3 Independent Test.

### Tests (Red)

- [ ] T017 [US3] `App/Tests/MokaAppTests/AppDecisionTests.swift`: 온보딩이 안 끝난 상태에서 키 단계 첫 값(`hasKey`), 키 단계 저장 콜백이 실패면 `false`·성공이면 `true`를 돌려줌, 키 단계 저장이 spec 003 `saveKey`와 같은 결과(앞뒤 공백 제거, 장부 비움, 실패면 `keyActionFailure == .save`), 이미 있음, 키 없이 `finishOnboarding` 뒤 할 일을 넣으면 노치에 뜸, 키 저장 뒤 끝내기 전 다시 만든 `AppState`에서 온보딩이 다시 보이고 키는 있음, 키 값이 설정 저장소·판단 결과·행동 로그에 없음. 실패를 확인한다(`FR-21 R-314`, `FR-21 R-315`, SC-307, SC-308) 〔단위 4〕
- [ ] T018 [US3] [화면 뒤] `App/Tests/MokaAppTests/SettingsSnapshotTests.swift`에 `test_R313_onboardingKeyEmpty`, `test_R313_onboardingKeyFailed`, `test_R313_onboardingKeySaved`(라이트·다크)를 확정 시안대로 쓰고 실패를 확인한다. `onboardingKeyFailed`는 `false`를 돌려주는 `onSave`로 뷰를 만들고 저장을 눌러, 뷰가 스스로 실패 문구로 바뀌는지 찍는다(뷰를 다시 만들지 않음, data-model §5). 기존 온보딩 두 단계 스냅샷은 그대로 둔다(`FR-21 R-313`) 〔단위 4〕

### Implementation (Green)

- [ ] T019 [US3] [화면 뒤] `App/Sources/Views/OnboardingView.swift`에 `keyStep: OnboardingKeyInput? = nil`(data-model §5 표, 저장 실패는 `onSave`의 `false`를 `@State`로 들고 있음), 값이 있으면 세 단계이고 첫 단계가 키, 칸이 비면 "다음" 꺼짐, 발급 링크는 `NSWorkspace`로 연다. `nil`이면 지금 두 단계 그대로. T018 PASS, 기존 스냅샷 PASS 〔단위 4〕
- [ ] T020 [US3] `App/Sources/AppState.swift`에 온보딩 키 단계가 쓰는 값(`hasKey`)과 저장 콜백(`saveKey` 재사용, 성공 여부를 Bool로 돌려줌. 실패 문구는 뷰가 그 false로 보이고 `keyActionFailure`는 설정 창 기본 탭 문구용), `App/Sources/MokaApp.swift`가 온보딩에 `keyStep`과 발급 링크 상수(T002에서 확정한 주소, 앱 상수 한 곳)를 넘긴다. T017 PASS 〔단위 4〕
- [ ] T021 [사람] [US3] quickstart 6-4(macOS 새 사용자 계정) 〔단위 4〕

**확인 지점**: SC-307·SC-308. 키 없이 온보딩을 끝내도 노치에 할 일이 뜬다.

---

## Phase 6: User Story 4 - 키가 맞지 않으면 노치와 할 일 탭에서도 알 수 있다 (Priority: P2)

**Goal**: 401 뒤 노치 펼친 화면과 할 일 탭에 키 확인 한 줄, 누르면 기본 탭.

**Independent Test**: spec US4 Independent Test.

### Tests (Red)

- [ ] T022 [US4] `App/Tests/MokaAppTests/AppDecisionTests.swift`: 가짜 공급자 401 뒤 `showsKeyNotice == true`, 키 저장·지움 뒤 `false`, 401 뒤 키 저장이 실패하면 `showsKeyNotice`가 기본 탭 `keyFieldState == .needsCheck`와 같은 값(`false`), 키 없음이면 `false`, 키 확인 동작이 `settingsTabRequest == .basic`을 남김. 실패를 확인한다(`FR-14 R-318`, SC-309) 〔단위 2〕
- [x] T024 [US4] [화면 뒤] `App/Tests/MokaAppTests/ScreenStateSnapshotTests.swift`에 `test_R316_keyNoticeEmpty`, `test_R316_keyNoticeDraft`, `test_R316_keyNoticeRunning`(라이트·다크)과 접힌 노치에 표시가 없는 것(기존 접힌 스냅샷과 같은 그림)을 쓰고 실패를 확인한다(`FR-14 R-316`) 〔단위 3〕
- [ ] T026 [US4] [화면 뒤] `App/Tests/MokaAppTests/SettingsSnapshotTests.swift`에 `test_R317_taskTabKeyNotice`(라이트·다크)를 쓰고 실패를 확인한다(`FR-14 R-317`) 〔단위 4〕

### Implementation (Green)

- [ ] T023 [US4] `App/Sources/AppState.swift`: `showsKeyNotice`, `settingsTabRequest: SettingsTab?`, 키 확인 동작 `requestKeySettings()`(data-model §4, research R8). T022 PASS 〔단위 2〕
- [x] T025 [US4] [화면 뒤] `App/Sources/Views/ExpandedView.swift`에 `keyNotice: Bool = false`, `onOpenKeySettings` 인자와 한 줄(빈 상태, 시작 전, 도는 중, 시간 끝은 없음). `App/Sources/Notch/NotchPanelHost.swift`가 `requestKeySettings()` 뒤 기존 "설정…"과 같은 순서로 창을 연다(plan "앱 연결"). T024 PASS 〔단위 3〕
- [ ] T027 [US4] [화면 뒤] `App/Sources/Views/TaskListTabView.swift`에 `keyNotice: Bool = false`, `onOpenKeySettings` 인자와 목록 위 한 줄, `App/Sources/Settings/SettingsView.swift`가 나타날 때와 `settingsTabRequest`가 바뀔 때 탭을 바꾸고 값을 비우며, 할 일 탭 한 줄의 동작은 탭을 기본으로 바꾼다. T026 PASS 〔단위 4〕
- [ ] T028 [사람] [US4] quickstart 6-5 〔단위 4〕

**확인 지점**: SC-309. 키 확인 필요가 세 곳에서 함께 켜지고 꺼진다.

---

## Phase 7: Polish & Cross-Cutting

- [ ] T029 [P] `GLOSSARY.md`: 구체화 게이트(넘기기, 메모리 기록), 이유 줄, 첫 행동을 쓰는 곳 둘(체크포인트, 게이트), 온보딩 절의 키 단계 서술 갱신 〔단위 1〕
- [ ] T030 [P] 대체 표기: spec 002 `specs/002-storage-checkpoint/spec.md` R-116에 "spec 004 R-313이 키 단계를 더함", spec 003 `specs/003-decision-model/spec.md` Non-Goals 첫 줄에 "spec 004가 담음" 〔단위 1〕
- [ ] T031 [사람] quickstart 1~6 전체를 돌려 결과 표를 마지막 PR에 붙인다 〔단위 4〕
- [ ] T032 PRD 고칠 문장(6장 재판정 질문, FR-04 손해 옵션 말, FR-13 시작 전과 넘기기, FR-11 게이트 입력 기록 제외)을 마지막 PR "사람이 볼 결정"에 적는다. PRD는 저장소 밖이라 고치지 않는다 〔단위 4〕

---

## Dependencies & Execution Order

### Phase 순서

Setup 다음 US1·US2(단위 1, 단위 2, 단위 3), 그다음 US3·US4(단위 4, 그리고 US4의 앱 상태는 단위 2, 노치 화면은 단위 3), 마지막 Polish.

### 태스크 사이 의존

- T004는 T003 뒤, T011은 T010 뒤(단위 1).
- 단위 2(T005, T006, T012, T013, T022, T023)는 단위 1 병합 뒤.
- 단위 3(T007~T009, T014~T016, T024, T025)은 단위 2 병합과 T002 뒤.
- 단위 4(T017~T021, T026~T028, T031, T032)는 단위 2 병합과 T002 뒤. 단위 3과 나란히 할 수 있다(고치는 뷰 파일이 다르다. `AppState.swift`는 T020만 고친다).

### 작업 단위와 Issue (plan "작업 단위")

| 단위 | 태스크 | Issue 제목 후보 |
|---|---|---|
| 1 | T001~T004, T010, T011, T029, T030 | spec 004 단위 1: 이유 줄과 구체화 게이트 규칙(MokaCore) |
| 2 | T005, T006, T012, T013, T022, T023 | spec 004 단위 2: AppState 게이트·이유 줄·키 확인 연결 |
| 3 | T007~T009, T014~T016, T024, T025 | spec 004 단위 3: 노치 펼친 화면(이유 줄, 게이트, 키 확인) |
| 4 | T017~T021, T026~T028, T031, T032 | spec 004 단위 4: 온보딩 키 단계와 할 일 탭 키 확인 |

### Parallel Opportunities

- T003과 T010은 다른 파일이라 병렬.
- 단위 3과 단위 4는 단위 2와 T002 뒤 병렬.
- T029와 T030은 문서라 언제든 병렬.

### Parallel Example: 단위 2 병합 뒤

```text
implementer A: 단위 3 (T007, T014, T024 Red 다음 T008, T015, T025 Green)
implementer B: 단위 4 (T017, T018, T026 Red 다음 T019, T020, T027 Green)
```

## Implementation Strategy

### MVP First

단위 1, 2, 3까지 가면 FR-04와 FR-13 수용 기준(이유 3개가 보임, 통과한 첫 행동이 제목 아래 보임)이 선다. 단위 4는 밀리면 온보딩 키 단계(T017~T021)를 먼저 다음 spec으로 넘긴다(spec 위험 1).

### 무인 실행 경계

moka는 2026-11-02부터 무인 실행을 하지 않는다(사용자 결정). 단위 1·2는 사람 세션에서 `implementer`로 돌릴 수 있다. 단위 3·4는 시안 확정과 사람 확인([사람])이 있어 사람 세션에서 진행한다.

## R-ID와 태스크

| R-ID | Red | Green | 사람 확인 |
|---|---|---|---|
| R-301 이유 줄 자리 | T007 | T008 | T002, T009 |
| R-302 남은 날 | T003 | T004 | T009 |
| R-303 손해 | T003 | T004 | T009 |
| R-304 미룬 횟수 | T003 | T004 | T009 |
| R-305 다시 그리기 | T005 | T006 | 없음 |
| R-306 게이트 열림 | T010, T012 | T011, T013 | T016 |
| R-307 게이트 입력과 넘기기 | T012, T014 | T013, T015 | T002, T016 |
| R-308 재판정 경로와 판정 | T010, T012 | T011, T013 | T016 |
| R-309 횟수와 통과, 메모리 기록 | T010, T012 | T011, T013 | T016 |
| R-310 기다리는 동안 | T012 | T013 | 없음 |
| R-311 통과 뒤 표시 | T012, T014 | T013, T015 | T016 |
| R-312 로그 없음 | T012 | T013 | 없음 |
| R-313 온보딩 키 단계 화면 | T018 | T019 | T002, T021 |
| R-314 키 단계 저장 | T017 | T020 | T021 |
| R-315 키 없이 끝냄 | T017 | T020 | T021 |
| R-316 노치 키 확인 | T024 | T025 | T002, T028 |
| R-317 할 일 탭 키 확인 | T026 | T027 | T028 |
| R-318 켜짐과 꺼짐 | T022 | T023 | T028 |
| R-319 가짜만, 계약 그대로 | 공통 규칙, T001 | 공통 규칙 | 없음 |
| SC-301 이유 줄 글자 | T003, T007 | T004, T008 | T009 |
| SC-302 손해 없음 | T003 | T004 | 없음 |
| SC-303 게이트 통과 | T012 | T013 | T016 |
| SC-304 세 번 뒤 통과 | T010, T012 | T011, T013 | 없음 |
| SC-305 실패 통과 | T010, T012 | T011, T013 | 없음 |
| SC-306 질의 경로 하나 | T012 | T013 | 없음 |
| SC-307 키 없이 온보딩 | T017 | T020 | T021 |
| SC-308 키 값 없음 | T017 | T020 | 없음 |
| SC-309 키 확인 세 곳 | T022, T024, T026 | T023, T025, T027 | T028 |
| SC-310 실제 API 없음, 기존 출력 그대로 | 공통 규칙, T001 | 모든 Green 태스크의 기존 스냅샷 PASS | T031 |
