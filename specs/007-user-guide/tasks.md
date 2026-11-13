---

description: "spec 007 사용 안내 작업 목록"
---

# Tasks: 사용 안내 (도움말 탭과 온보딩 안내 장)

**Input**: `specs/007-user-guide/`의 plan.md, spec.md(R-701~R-718), research.md(R1~R10), data-model.md, quickstart.md. 확정 시안 `~/Dev/ai-platform/projects/moka/design/007-mockup.html` v2 화면 1~15(저장소 밖, 시안 확정 2026-11-13(사용자)). 기준 `origin/main` `fa17f19`.

**Tests**: 넣는다. 헌법 II와 AGENTS.md "실패하는 테스트를 먼저 쓰고 실패를 확인한 뒤 구현한다". 테스트 태스크마다 Red 커밋을 남기고, 구현 태스크에서 Green 커밋을 남긴다.

**Organization**: plan "작업 단위" 셋을 Phase로 둔다. 단위 하나가 Issue 하나, PR 하나다. 각 태스크 끝의 `〔단위 N〕`이 그 번호다.

**원본 규칙**: 규칙, 이름, 모양은 data-model.md, 글자는 확정 시안과 spec 표가 원본이다. 태스크는 절 번호를 가리키고 문장을 옮겨 적지 않는다.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 다른 파일을 고치고 아직 안 끝난 태스크에 기대지 않아 병렬로 할 수 있다
- **[Story]**: US1~US3(spec.md)
- **[사람]**: 사람이 확인용 빌드나 새 사용자 계정에서 봐야 끝난다

## 공통 규칙 (모든 태스크)

- 테스트 표시 이름은 R-ID로 시작한다(ADR-0003): `test_R7xx_...`. 앱 시험 번들(`MokaAppTests`)은 XCTest, MokaCore는 Swift Testing.
- 새 뷰와 규칙은 `App/Sources/Views/`에 둔다. 시험 번들이 컴파일하는 곳은 `App/Sources/Views`와 `AppState.swift`뿐이다(research R8).
- 화면 글자를 상수로 꺼낼 때 글자는 바꾸지 않는다. 기존 스냅샷 그림이 탭 줄·단계 표시 밖에서 바뀌면 멈추고 원인을 본다.
- 가짜 할 일만 쓴다(예: "가짜 할 일 A", "가짜 자료 열기"). 실제 판단 API, Keychain, 앱 DB를 시험에서 열지 않는다. 에이전트는 Keychain 값을 조회하지 않는다.
- 바꾸지 않는 것: `schema/moka-schema.sql`, 설정 키, `questions.json`, `moka-sim` 형식과 golden, `Package.swift`, `project.yml`의 타깃·소스 목록, CI. `@unchecked Sendable`을 쓰지 않는다.
- 기존 시험은 호출만 고치고 기대값은 바꾸지 않는다(`OnboardingSteps`에 `hasGuide: false`, 온보딩 스냅샷 `initialStep` +3).
- 화면 문구는 고객용 해요체이고 확정 시안 글자를 그대로 쓴다.
- 검증 명령: `swift test`, 앱 빌드 `xcodegen generate && xcodebuild build -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`, 앱 시험 quickstart 3. 결과는 PASS/FAIL/SKIP/NOT_RUN.

---

## Phase 1: Setup (단위마다 첫 태스크)

- [ ] T001 기준 상태 확인: `swift test`, 앱 빌드, quickstart 3의 앱 시험을 돌려 기존 시험이 PASS인지, 스냅샷 출력 폴더(`.verify/snapshots/001/` 또는 `MOKA_SNAPSHOT_DIR`)의 파일 목록과 해시를 PR "완료 증거"에 적는다(SC-707 비교 기준). 단위 2·3도 각 PR 첫 커밋 전에 같은 확인을 한다 〔단위 1〕

---

## Phase 2: 단위 1 - 도움말 탭 (US1, Priority: P1) MVP

**Goal**: 설정 창 넷째 탭 "도움말", 항목 여덟, 화면 상수에서 만든 글, 펼침 유지.

**Independent Test**: 도움말 글 단위 시험(따옴표, 글 고정, 문장 수), `helpExpanded` 앱 시험, 스냅샷 1~9.

### Red

- [ ] T002 [P] [US1] `Tests/MokaCoreTests/ReasonLineTests.swift`에 `ReasonText.deadline`이 `.none`·`.today`·`.left(3)`·`.overdue(2)`에 "마감 없음"·"D-day"·"D-3"·"D+2"를 돌려주는 시험(`R705_reasonDeadlineText`)을 더한다. 접근 수준이 `private`이라 컴파일 실패를 확인한다(spec R-705, research R2) 〔단위 1〕
- [ ] T003 [P] [US1] `App/Tests/MokaAppTests/HelpContentTests.swift`: `test_R703_topicOrderAndSummaries`(목차 순서, 제목·요약이 spec "도움말 목차 요약" 표), `test_R705_quotesComeFromScreenConstants`(모든 글의 큰따옴표 쌍 안 글자가 `HelpContent.quotes`에 있음, data-model §3), `test_R705_quotesSetMatchesScreenSymbols`(`quotes`가 data-model §3 출처 표의 상수·함수 결과와 같은 집합), `test_R704_R717_bodiesMatchConfirmedMockup`(항목 1~7 글이 spec "도움말 설명" 글자 그대로), `test_R708_shortcutRows`(항목 8 표가 spec "단축 동작 목록" 앞 세 열 그대로), `test_R704_sentenceCount`(본문 `요.` 수 2~5), `test_R702_guideRowTexts`, `test_R709_noHostInHelp`(어느 글에도 `api.`나 공급자 이름이 없음), `test_R716_helpExpandedAccessibilityValue`(`HelpText.value(expanded:)`가 참이면 "펼침", 거짓이면 "접힘"). 타입이 없어 컴파일 실패를 확인한다(SC-703) 〔단위 1〕
- [ ] T004 [P] [US1] `App/Tests/MokaAppTests/AppHelpTests.swift`(새): 새 `AppState`의 `helpExpanded`가 빈 집합, 둘을 넣으면 둘, 하나를 빼면 하나, 가짜 설정 저장소에 쓰기 0건(`test_R707_helpExpandedInMemory`). 실패를 확인한다(SC-702) 〔단위 1〕
- [ ] T005 [US1] `App/Tests/MokaAppTests/SettingsSnapshotTests.swift`에 `test_R701_R702_helpTabCollapsed`(라이트·다크), `test_R703_helpTopic1Notch`~`test_R703_R708_helpTopic8Shortcuts`(라이트, data-model §7)를 확정 시안 1~9번대로 쓰고 실패를 확인한다 〔단위 1〕

### Green

- [ ] T006 [US1] `Sources/MokaCore/Decision/ReasonLine.swift`의 `ReasonText.deadline`을 `public`으로. T002 PASS 〔단위 1〕
- [ ] T007 [US1] 글자 상수 꺼내기(research R2 표): `App/Sources/Views/NotchText.swift`(새, `NotchText`·`SheetText`), `GateDisplay.submit`·`skip`, `NotchText.newTask`·`otherTask`, 이미 있는 `TaskListText`에 보기·정렬 멤버 추가. `ExpandedView.swift`, `ExpiredView.swift`, `CheckpointNotesView.swift`, `GateView.swift`, `TaskListTabView.swift`, `TaskFormView.swift`, `ContextFormView.swift`, `App/Sources/Notch/NotchPanelHost.swift`, `App/Sources/MokaApp.swift`가 상수를 쓰게 한다. 화면 글자는 그대로다. 기존 스냅샷·앱 시험 PASS 〔단위 1〕
- [ ] T008 [US1] `App/Sources/Views/HelpContent.swift`(`HelpTopic`, `HelpBody`, `ShortcutRow`, `HelpContent`, `HelpText`, data-model §2·§3). T003 PASS 〔단위 1〕
- [ ] T009 [US1] `App/Sources/AppState.swift`에 `helpExpanded: Set<HelpTopic> = []`. T004 PASS 〔단위 1〕
- [ ] T010 [US1] `App/Sources/Views/HelpTabView.swift`(맨 위 줄, 접었다 펼치는 목록, 여럿 펼침, `ScrollView`, VoiceOver 펼침 상태), `App/Sources/Views/SettingsTabBar.swift`에 `help` 탭과 물음표 원 아이콘, `App/Sources/Settings/SettingsView.swift`의 `case .help`가 `HelpTabView(expanded: $appState.helpExpanded, onShowGuide: {})`를 그린다(버튼 동작은 단위 3). T005 PASS. 탭 줄이 들어간 기존 설정 창 그림은 넷째 탭만 달라진다 〔단위 1〕

### 확인

- [ ] T011 [사람] [US1] quickstart 6-1, 6-5(1~9번) 〔단위 1〕

**확인 지점**: US1 시나리오 1~7, SC-701~SC-703.

---

## Phase 3: 단위 2 - 온보딩 안내 장 (US2, Priority: P1)

**Goal**: 온보딩 맨 앞 안내 장 셋, n/6(키 단계 없으면 n/5), 안내 건너뛰기, 실제 뷰 그림.

**Independent Test**: `GuideButtons` 표와 `OnboardingSteps` 이동 단위 시험, 스냅샷 10~13.

### Red

- [ ] T012 [P] [US2] `App/Tests/MokaAppTests/GuideTests.swift`(새): `test_R712_guideButtonsTable`(data-model §4 여섯 경우), `test_R711_sixStepsWithKeyStep`(1~3 `.guide`, 4 `.key`, 5 `.context`, 6 `.defaults`, `total` 6), `test_R711_fiveStepsWithoutKeyStep`(`total` 5, 4 `.context`), `test_R712_skipGuideGoesToFirstSettingStep`(첫째·둘째 장에서 키 단계 있음이면 4 `.key`, 없음이면 4 `.context`, 설정 단계에서는 아무것도 안 함), `test_R712_thirdGuideNextGoesToFirstSettingStep`, `test_R711_guideIndex`, `test_R710_guideTexts`(제목·설명이 spec "안내 장" 표), `test_R716_guideAccessibilityLabels`(장마다 그림 설명 한 줄이 비어 있지 않고 서로 다름), `test_R705_guideQuotesComeFromScreenConstants`(안내 장 글의 따옴표 안 글자가 `NotchText.start`·`firstActionLabel`, `GateDisplay.skip`과 같음, SC-703 안내 장 절반), `test_R711_keyStepFailStaysOn4of6`·`test_R711_keyStepSaveMovesTo5of6`(`hasGuide: true`에서 4/6 키 저장 실패면 4/6에 머물고, 성공하면 5/6), `test_SC705_guidePagesNeverSaveOrFinish`(안내 장 쪽에서 `submitKey`가 `onSave`를 0번 부르고 `canFinish`가 거짓), `test_R710_illustrationDetachesShortcutAndFocus`(`GateDisplay.detachesStartShortcut(isEnteringTitle: false, gatePhase: nil, isIllustration: true)`가 참, `requestsFocus(phase: .asking, isIllustration: true)`가 거짓, 둘 다 `isIllustration: false`면 지금 값 그대로). 실패를 확인한다 〔단위 2〕
- [ ] T013 [US2] `App/Tests/MokaAppTests/OnboardingKeyStepTests.swift`의 `OnboardingSteps(...)` 호출에 `hasGuide: false`를 넣는다. 기대값은 그대로다. 새 인자가 없어 컴파일 실패를 확인한다(SC-706) 〔단위 2〕
- [ ] T014 [US2] `App/Tests/MokaAppTests/SettingsSnapshotTests.swift`에 `test_R710_guideCard1Notch`·`2Rank`·`3FirstAction`(라이트·다크), `test_R711_guideCard1WithoutKeyStep`, `test_R711_onboardingKeyStep4of6`을 확정 시안 10~13번대로 쓴다. 기존 온보딩 스냅샷(`test_R116_*`, `test_R624_*`)은 `initialStep`을 3 올린다. 실패를 확인한다 〔단위 2〕

### Green

- [ ] T015 [US2] `App/Sources/Views/GuideCardView.swift`(`GuideCard`, `GuideText`, `GuidePresentation`, `GuideButtons`, `GuideCardView`, data-model §4). `StepBar`를 `OnboardingView.swift`에서 함께 쓰도록 `private`을 뗀다(같은 타깃). T012의 버튼·글 시험 PASS 〔단위 2〕
- [ ] T016 [US2] `App/Sources/Views/GuideIllustration.swift`(research R4: `NotchContentView`에 가짜 값, 순위 장 `RankBadge`, 누를 수 없음, 접근성 설명, `.environment(\.isNotchIllustration, true)`). 환경 값 `\.isNotchIllustration`을 `Views/`에 두고, `GateDisplay.detachesStartShortcut`에 `isIllustration` 인자(기본 거짓)와 `GateDisplay.requestsFocus`를 더한다. `ExpandedView`(시작 버튼, `TitleEntryRow` 포커스), `ExpiredView`(기본 버튼), `GateView`(자동 포커스)가 환경 값을 읽어 이 함수를 쓴다. 기존 노치 스냅샷·게이트 시험 PASS. `TaskListTabView.swift`의 `RankBadge`를 `internal`로 〔단위 2〕
- [ ] T017 [US2] `App/Sources/Views/OnboardingView.swift`: `OnboardingSteps`에 `.guide(GuideCard)`, `init(hasGuide:hasKeyStep:initialStep:)`, `skipGuide()`(안내 장이 아닌 첫 쪽으로), `guideIndex`, `submitKey`는 `.key` 쪽에서만, `canFinish`(data-model §5). `OnboardingView`에 `showsGuide: Bool = true`와 안내 장 쪽 그리기. 안내 장 쪽에서는 `onSave`·`onFinish`를 부르지 않는다. `App/Sources/MokaApp.swift`의 `OnboardingWindow`는 기본값 그대로(`showsGuide: true`). T012·T013·T014 PASS 〔단위 2〕
- [ ] T018 [P] [US2] `GLOSSARY.md` onboarding 항목을 "첫 실행에 한 번 보이는 안내 장 셋과 설정 단계(키, 일정, 기본값)"로 고친다(spec 007) 〔단위 2〕

### 확인

- [ ] T019 [사람] [US2] quickstart 6-3(새 사용자 계정), 6-4, 6-5(10~13번) 〔단위 2〕

**확인 지점**: US2 시나리오 1~8, US3 시나리오 7, SC-704·SC-706.

---

## Phase 4: 단위 3 - 안내 다시 보기 시트 (US3, Priority: P2)

**Goal**: 도움말 탭 버튼으로 설정 창 위 시트, 안내 장 셋만, 쓰기 0건.

**Independent Test**: `GuideSheetView` 앱 시험과 스냅샷 14·15. 시트 띄우기는 사람 확인.

### Red

- [ ] T020 [P] [US3] `App/Tests/MokaAppTests/GuideTests.swift`에 `test_R713_sheetStartsAtFirstOfThree`, `test_R713_sheetHasNoSkip`, `test_R714_sheetLastPrimaryIsDoneAndCloses`(셋째 장 주 버튼이 "다 봤어요"이고 `GuideSheetState.primary()`가 닫으라는 참), `test_R714_sheetCancelCloses`(`cancel()`이 참)를 더한다. 시트 쪽 상태 이동은 data-model §6의 `GuideSheetState`로 시험한다. 실패를 확인한다(SC-705) 〔단위 3〕
- [ ] T021 [US3] `App/Tests/MokaAppTests/SettingsSnapshotTests.swift`에 `test_R713_guideSheetFirst`, `test_R714_guideSheetLast`(라이트·다크, 시트 내용만)를 확정 시안 14·15번대로 쓰고 실패를 확인한다 〔단위 3〕

### Green

- [ ] T022 [US3] `App/Sources/Views/GuideSheetView.swift`(data-model §6, `GuideCardView(presentation: .sheet)`, 숨은 취소 버튼). 생성 인자는 `onClose` 하나다. T020·T021 PASS 〔단위 3〕
- [ ] T023 [US3] `App/Sources/Settings/SettingsView.swift`에 `isShowingGuide`와 `.sheet`, `HelpTabView`의 `onShowGuide`가 시트를 연다. 기존 `.onDisappear`에서 `isShowingGuide = false`로 비운다(research R6). `settingsTabRequest` 처리는 바꾸지 않는다. 앱 빌드 PASS 〔단위 3〕

### 확인

- [ ] T024 [사람] [US3] quickstart 6-2(설정 창 닫기 포함), 6-2b(시트가 열린 동안 탭 요청), 6-3 (6)(온보딩 창이 열린 채 시트), 6-5(14·15번) 〔단위 3〕

**확인 지점**: US3 시나리오 1~6, SC-705.

---

## Phase 5: Polish

- [ ] T025 [P] 마지막 단위 PR에 quickstart 1~6 결과 표를 붙인다. PRD FR-21(spec 위험 5)과 추가 시간 문구(spec 위험 6)는 PR "사람이 볼 결정"에 다시 적는다 〔단위 3〕

---

## Dependencies & Execution Order

### Phase 순서

단위 1을 먼저 시작한다. 단위 2는 단위 1의 글자 상수(T007)가 병합된 뒤 시작한다(안내 장 글이 그 상수를 인용). 그 뒤로 단위 1의 나머지와 단위 2는 나란히 갈 수 있다. 단위 3은 단위 1(`HelpTabView`의 버튼)과 단위 2(`GuideCardView`)가 병합된 뒤다. Polish는 마지막 단위에.

### 태스크 사이 의존

- 단위 1: T002 다음 T006, T003 다음 T007·T008, T004 다음 T009, T005 다음 T010. T008은 T006·T007 뒤(인용 상수).
- 단위 2: 시작 전에 단위 1의 T007이 main에 있어야 한다. T012 다음 T015·T016·T017, T013 다음 T017, T014 다음 T016·T017. T017은 T015 뒤.
- 단위 3: T020·T021 다음 T022, T022 다음 T023.
- 겹치는 파일: `SettingsSnapshotTests.swift`(셋 다), `TaskListTabView.swift`(단위 1 글자 상수, 단위 2 `RankBadge`). 나중에 병합하는 쪽이 충돌을 푼다.

### 작업 단위와 Issue (plan "작업 단위")

| 단위 | 태스크 | Issue 제목 후보 |
|---|---|---|
| 1 | T001~T011 | spec 007 단위 1: 설정 창 도움말 탭 |
| 2 | T012~T019 | spec 007 단위 2: 온보딩 안내 장 |
| 3 | T020~T025 | spec 007 단위 3: 안내 다시 보기 시트 |

### Parallel Opportunities

- 단위 1 안에서 T002, T003, T004는 다른 파일이라 병렬.
- 단위 2의 T012와 T018은 병렬.
- 단위 1의 T007이 병합된 뒤 단위 1의 나머지와 단위 2는 서로 다른 implementer로 병렬.

### Parallel Example

```text
implementer A: 단위 1 (T002~T005 Red 다음 T006~T010 Green)
implementer B: 단위 1 T007 병합 뒤 단위 2 (T012~T014 Red 다음 T015~T017 Green)
둘 병합 뒤 implementer C: 단위 3 (T020·T021 Red 다음 T022·T023 Green)
```

## Implementation Strategy

### MVP First

단위 1만으로 Issue #113의 "언제든 다시 본다"가 채워진다. 단위 2는 새 사용자 첫 실행에만 보인다. 밀리면 단위 3을 먼저 넘긴다(도움말 탭이 같은 내용을 글로 준다).

### 사람 세션

moka는 2026-11-02부터 무인 실행을 하지 않는다(사용자 결정). 세 단위 모두 사람 세션에서 `implementer`로 돌릴 수 있고, [사람] 태스크는 사람이 확인용 빌드로 본다.

## R-ID와 태스크

| R-ID | Red | Green | 사람 확인 |
|---|---|---|---|
| R-701 도움말 탭 | T005 | T010 | T011 |
| R-702 맨 위 설명과 버튼 | T003, T005 | T008, T010 | T011 |
| R-703 목차와 펼침 | T003, T005 | T008, T010 | T011 |
| R-704 해요체 2~5문장 | T003 | T008 | T011 |
| R-705 인용은 화면 상수 | T002, T003, T012(안내 장) | T006, T007, T008, T015 | 없음 |
| R-706 읽기만 | T004 | T009 | 없음 |
| R-707 펼침 유지 | T004 | T009, T010 | T011 |
| R-708 단축 동작 표 | T003, T005 | T008 | T011 |
| R-709 호스트 없음 | T003 | T008 | 없음 |
| R-710 안내 장과 그림 | T012, T014 | T015, T016 | T019 |
| R-711 순서와 n/6·n/5 | T012, T013, T014 | T017 | T019 |
| R-712 버튼 규칙 | T012 | T015, T017 | T019 |
| R-713 시트, 안내 장 셋만 | T020, T021 | T022, T023 | T024 |
| R-714 닫기와 쓰기 0건 | T020, T021 | T022, T023 | T024(6-2 창 닫기, 6-2b 탭 요청, 6-3 (6) 온보딩 창과 함께) |
| R-715 기존 사용자에게 안 보임 | 기존 `AppLifecycleTests`의 `test_FR21_R116_firstLaunchShowsOnboarding`, `test_FR21_R116_finishSavesContextSettingsAndHidesOnboarding`(바꾸지 않고 PASS 유지. 설정 키를 더하지 않아 `onboarding_done` 규칙 그대로) | T017(기존 값 그대로) | T019(6-4) |
| R-716 접근성 | T003(`test_R716_helpExpandedAccessibilityValue`), T012(`test_R716_guideAccessibilityLabels`) | T008, T010, T016 | T011, T019 |
| R-717 확정 시안 글자 | T003, T005, T012, T014, T021 | T008, T010, T015, T022 | T011, T019, T024 |
| R-718 가짜만, 계약 그대로 | 공통 규칙, T001 | 모든 Green의 기존 시험 PASS | T025 |
| SC-701 | T005 | T010 | T011 |
| SC-702 | T004 | T009, T010 | T011 |
| SC-703 | T003, T012(안내 장) | T008, T015 | 없음 |
| SC-704 | T012 | T017 | T019 |
| SC-705 | T012(온보딩 절반), T020(시트 절반) | T017, T022 | T019, T024 |
| SC-706 | T012(4/6 저장 실패·성공), T013(기존 시험 `hasGuide: false`) | T017 | 없음 |
| SC-707 | T001, T005, T014, T021 | T010, T017, T022 | T011, T019, T024 |
| SC-708 | 공통 규칙 | 모든 Green | T025 |
