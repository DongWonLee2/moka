# Data Model: 사용 안내 (spec 007)

규칙의 원본이다. 결정 이유는 [research.md](research.md)다. 글자는 확정 시안(`~/Dev/ai-platform/projects/moka/design/007-mockup.html` v2, 시안 확정 2026-11-13(사용자))과 spec의 표가 원본이고 여기서는 옮겨 적지 않는다. 타입 이름은 구현 PR에서 다듬을 수 있으나 바꾸면 PR "가정"에 적는다. 저장하는 값은 없다. 스키마와 설정 키는 그대로다.

## 1. 설정 창 탭

| 타입 | 바뀌는 것 |
|---|---|
| `SettingsTab`(`SettingsTabBar.swift`) | `case basic, tasks, contexts, help`. `help.title`은 "도움말". 아이콘은 물음표 원(선 굵기 1.6, 다른 탭과 같음) |
| `SettingsView` | `case .help:`에서 `HelpTabView`를 그린다. 시트 상태 `isShowingGuide: Bool`(§6) |

## 2. 도움말 항목

| 타입 | 모양 | 비고 |
|---|---|---|
| `HelpTopic` | `enum: CaseIterable, Hashable, Sendable { notch, tasksAndContexts, rankAndNext, reasonLine, firstAction, decisionModel, destination, shortcuts }` | 선언 순서가 목차 순서다(spec R-703) |
| `HelpBody` | `enum { text(String), shortcuts([ShortcutRow]) }` | 단축 동작 항목만 표 |
| `ShortcutRow` | `action: String`, `place: String`, `effect: String` | spec "단축 동작 목록" 앞 세 열. 근거 열은 넣지 않는다 |
| `HelpContent` | `static func title(_: HelpTopic) -> String`, `static func summary(_:) -> String`, `static func body(_:) -> HelpBody`, `static let quotes: Set<String>` | 글은 §3 규칙으로 만든다 |
| `HelpText` | `guideMessage`, `guideButton`, `expandedValue`, `collapsedValue` | "노치, 순위, 첫 행동 칸 안내를 한 장씩 다시 볼 수 있어요.", "안내 다시 보기", VoiceOver 값 "펼침"·"접힘"(R-716). 항목 줄은 `accessibilityValue(HelpText.value(expanded:))`로 읽힌다 |
| `HelpTabView` | `expanded: Binding<Set<HelpTopic>>`, `onShowGuide: () -> Void` | 맨 위 줄(설명, 버튼), 그 아래 항목 여덟. 항목을 누르면 집합에서 넣고 뺀다. 여럿 펼침 가능. 본문은 `ScrollView` |
| `AppState.helpExpanded` | `Set<HelpTopic>`, 처음 빈 집합 | 메모리만(research R3). 탭을 바꿔도, 설정 창을 닫아도 앱을 켜 둔 동안 남는다 |

## 3. 인용 규칙 (spec R-705, SC-703)

- 따옴표 표기는 큰따옴표 `"…"` 하나다. 글 안의 큰따옴표 쌍 안 글자는 모두 `HelpContent.quotes`에 있어야 한다.
- `quotes`의 원소는 화면 상수나 함수 결과로만 만든다. 문자열 글자를 직접 넣지 않는다. 원소와 출처:

  | 인용 | 출처 |
  |---|---|
  | "무엇을 할까요?", "시작", "완료", "미루기", "바꾸기", "이어서 할 일" | `NotchText.titlePlaceholder`, `start`, `complete`, `skip`, `switchTask`, `firstActionLabel`(새, research R2) |
  | "적기", "지금은 넘기기" | `GateDisplay.submit`, `GateDisplay.skip`(새) |
  | "어디서 시작할지 막연해 보여요", "키가 맞지 않아 판단 모델에 묻지 못하고 있어요.", "키 확인" | `GateDisplay.title`, `keyNoticeText`, `keyNoticeButton` |
  | "전체", "오늘", "이번 주", "만든 순", "마감 순" | 이미 있는 `TaskListText`에 멤버 추가 |
  | "+ 새 할 일", "다른 할 일" | `NotchText.newTask`, `NotchText.otherTask`(새) |
  | "할 일", "일정", "기본" | `SettingsTab.tasks.title`, `contexts.title`, `basic.title` |
  | "조금", "꽤", "아주" | `ContextText.impact(.normal/.high/.critical)` |
  | "1순위", "2순위", "3순위", "다음" | `TaskRowText.rankBadge(rank: 1...3, isNext: false)`, `rankBadge(rank: nil, isNext: true)` |
  | "D-3 · 중요도 보통 · 미룬 2번" | `ReasonText.line(ReasonLine(deadline: .left(3), impact: "보통", skipCount: 2))` |
  | "D-day", "D+2" | `ReasonText.deadline(.today)`, `deadline(.overdue(2))`(접근 수준 `public`으로) |
  | "판단을 받으러 보내는 곳" | `DecisionFieldText.destinationPrefix`에서 끝 `": "`를 뗀 값 |
  | "설정…", "종료", "등록", "돌아가기" | `NotchText.settingsMenu`, `quit`, `register`, `back`(새) |
  | "저장", "취소" | `SheetText.save`, `cancel`(새) |

- 글 고정 시험의 기대값은 spec "도움말 설명"과 "단축 동작 목록"(앞 세 열) 글자 그대로다.
- 문장 수: `text` 본문의 `요.` 개수가 2 이상 5 이하.

## 4. 안내 장

| 타입 | 모양 | 비고 |
|---|---|---|
| `GuideCard` | `enum: CaseIterable, Sendable { notch, rank, firstAction }` | 순서가 장 순서다 |
| `GuideText` | `title(_:)`, `message(_:)`, `accessibilityLabel(_:)`, `skip`("안내 건너뛰기"), `back`("이전"), `next`("다음"), `done`("다 봤어요") | 제목·설명은 spec "안내 장" 표 |
| `GuidePresentation` | `enum { onboarding, sheet }` | |
| `GuideButtons` | `static func make(index: Int, total: Int, presentation: GuidePresentation) -> GuideButtons`. 값: `showsBack: Bool`, `showsSkip: Bool`, `primary: String` | 규칙 아래 |
| `GuideCardView` | `card`, `index`(1부터), `total`, `presentation`, `onBack`, `onSkip`, `onPrimary` | 단계 표시(`StepBar`), 제목, 설명, `GuideIllustration`, 버튼 줄. 주 버튼은 기본 버튼(Enter) |
| `GuideIllustration` | `card: GuideCard` | 실제 뷰에 가짜 값(research R4). 누를 수 없음. 안에 `.environment(\.isNotchIllustration, true)`를 넣는다 |
| `\.isNotchIllustration` | `EnvironmentValues`의 `Bool`, 기본 거짓 | 참이면 노치 뷰가 기본 버튼 단축키를 떼고 자동 포커스를 하지 않는다(research R4) |
| `GateDisplay.detachesStartShortcut` | `(isEnteringTitle:gatePhase:isIllustration:) -> Bool` | `isIllustration`이 참이면 늘 참. 기존 호출은 기본값 거짓 |
| `GateDisplay.requestsFocus` | `(phase: GatePhase, isIllustration: Bool) -> Bool` | `phase == .asking && !isIllustration`. `GateView`와 `TitleEntryRow`(phase 대신 `focusesOnAppear`)가 같은 규칙을 쓴다 |

`GuideButtons` 규칙(`index`는 그 안내 장의 번호, 온보딩에서는 전체 단계 번호와 같다):

| 경우 | `showsBack` | `showsSkip` | `primary` |
|---|---|---|---|
| 온보딩, 첫 장 | 거짓 | 참 | "다음" |
| 온보딩, 둘째 장 | 참 | 참 | "다음" |
| 온보딩, 셋째 장 | 참 | 거짓 | "다음" |
| 시트, 첫 장 | 거짓 | 거짓 | "다음" |
| 시트, 둘째 장 | 참 | 거짓 | "다음" |
| 시트, 셋째 장 | 참 | 거짓 | "다 봤어요" |

## 5. 온보딩 단계

`OnboardingSteps`(`OnboardingView.swift`):

- `enum Page { guide(GuideCard), key, context, defaults }`.
- `init(hasGuide: Bool, hasKeyStep: Bool, initialStep: Int)`. 쪽 목록 = (`hasGuide`이면 `GuideCard.allCases.map(.guide)`) + (`hasKeyStep`이면 `[.key]`) + `[.context, .defaults]`.
- `total`은 목록 길이다. 앱에서는 6(키 단계 있음) 또는 5(없음).
- `next()`, `back()`, `submitKey(...)`는 그대로다.
- `skipGuide()`: 지금 쪽이 안내 장이면 안내 장이 아닌 첫 쪽(첫 설정 단계)으로 간다. 아니면 아무것도 안 한다.
- `submitKey(...)`: 지금 쪽이 `.key`일 때만 저장을 시도한다. 다른 쪽에서는 `onSave`를 부르지 않는다. `hasGuide: true`에서도 키 단계(4/6) 저장이 실패하면 4/6에 머물고, 성공하면 5/6으로 간다.
- `canFinish`: 지금 쪽이 `.defaults`일 때만 참. `OnboardingView`는 이 값이 참일 때만 "시작하기"를 그리고 `onFinish`를 부른다. 그래서 안내 장 쪽에서 `onSave`·`onFinish`는 0건이다(SC-705).
- `guideIndex`: 지금 쪽이 안내 장이면 1~3, 아니면 `nil`.
- 첫 설정 단계에서 `back()`을 부르는 버튼은 화면에 없다(spec R-712). `back()` 함수 자체는 바꾸지 않는다.
- `OnboardingView`: `showsGuide: Bool = true`. `.guide(card)` 쪽은 `GuideCardView(presentation: .onboarding)`를 그린다. 저장(`onFinish`, `onSave`)은 지금 그대로이고 안내 장 쪽에서는 부르지 않는다.

## 6. 다시 보기 시트

| 타입 | 모양 | 비고 |
|---|---|---|
| `GuideSheetState` | `index: Int`(1~3), `mutating func primary() -> Bool`(셋째 장이면 닫으라는 참, 아니면 다음 장으로 가고 거짓), `back()`, `cancel() -> Bool`(늘 참) | 시트 이동 규칙. 시험이 직접 부른다 |
| `GuideSheetView` | `onClose: () -> Void`. 안쪽 `@State state = GuideSheetState()` | `GuideCardView(presentation: .sheet, total: 3)`. 셋째 장 주 버튼과 esc(숨은 취소 버튼)가 `onClose`. 저장소·키 보관함·`AppState` 인자 없음 |
| `SettingsView` 연결 | `HelpTabView(onShowGuide: { isShowingGuide = true })`, `.sheet(isPresented: $isShowingGuide) { GuideSheetView(onClose: { isShowingGuide = false }) }` | 탭 요청이 와도 `isShowingGuide`를 건드리지 않는다. `.onDisappear`(창 닫힘)에서 `isShowingGuide = false`(research R6) |

## 7. 스냅샷 이름

모두 `SettingsSnapshotTests.swift`에 더한다. 표시 이름은 R-ID로 시작한다(ADR-0003).

| 이름 | 상태 | 시안 |
|---|---|---|
| `test_R701_R702_helpTabCollapsed` | 도움말 탭, 모두 접힘, 라이트·다크 | 1 |
| `test_R703_helpTopic1Notch` … `test_R703_R708_helpTopic8Shortcuts` | 항목 하나씩 펼침, 라이트 | 2~9 |
| `test_R710_guideCard1Notch`, `test_R710_guideCard2Rank`, `test_R710_guideCard3FirstAction` | 온보딩 1/6~3/6, 라이트·다크 | 10~12 |
| `test_R711_guideCard1WithoutKeyStep` | 키 단계 없음, 1/5 | 없음(10번에서 숫자만 다름) |
| `test_R711_onboardingKeyStep4of6` | 키 단계 4/6 | 13 |
| `test_R713_guideSheetFirst`, `test_R714_guideSheetLast` | 시트 내용 1/3, 3/3 | 14·15(시트 내용만. 설정 창 위에 붙은 모양은 사람 확인) |

기존 이름 가운데 바뀌는 그림: 탭 줄이 들어간 설정 창 스냅샷(넷째 탭), `test_R116_onboardingStep1`·`Step2`·`test_R624_*`(단계 표시). 시험 코드는 `initialStep`만 3 올린다.
