# Research: 사용 안내 (spec 007)

결정마다 결정, 이유, 검토한 대안을 적는다. spec "확정한 것" Q1~Q12는 2026-11-12 debate와 사용자 결정, 2026-11-13 시안 확정으로 정했다. 여기 R1 이후는 그 답을 코드로 옮기는 방법이고 에이전트가 정했다. 구현 PR "가정"에 다시 적는다. 기준은 `origin/main` `fa17f19`다.

## R1. 도움말 글을 화면 상수에서 만든다 (spec R-705, SC-703)

- 결정: 도움말 글은 `App/Sources/Views/HelpContent.swift` 한 곳에서 Swift 문자열 보간으로 만든다. 따옴표 안 글자는 손으로 적지 않고 화면이 쓰는 상수나 함수 결과를 넣는다(예: `"\(q(GateDisplay.title))"`). `HelpContent.quotes`는 도움말이 인용해도 되는 화면 글자 집합이고, 같은 상수를 가리킨다.
- 시험 셋:
  1. 따옴표 검사: 모든 항목 글에서 큰따옴표 쌍 안의 글자를 뽑아, 하나도 빠짐없이 `HelpContent.quotes`에 들어 있는지 본다. 손으로 친 인용이 들어오면 실패한다.
  2. 글 고정: 항목 여덟의 글 전체를 확정 시안 글자와 비교한다. 화면 상수가 바뀌면 도움말 글이 저절로 바뀌고 이 시험이 실패해, 사람이 바뀐 도움말을 시안과 다시 맞춘다. SC-703의 "화면 상수를 바꾸고 도움말을 그대로 두면 실패"를 이 시험이 맡는다.
  3. 문장 수: 항목마다 해요체 문장 끝(`요.`)을 세어 2~5개인지 본다(R-704). 단축 동작 항목은 표라 뺀다.
- 이유: 화면과 도움말이 같은 기호를 쓰면 글자가 어긋날 수 없고, 글 고정 시험이 "동작 설명이 낡았는지"를 사람에게 다시 보게 한다(spec 위험 1).
- 대안: 도움말을 `Localizable.strings`나 JSON에 따로 둠(화면 상수와 연결이 끊김), 따옴표 검사만 둠(상수가 바뀌어도 시험이 조용히 통과해 사람이 모름).

## R2. 뷰 안에 글자로만 있는 문구를 상수로 꺼낸다 (spec R-705)

- 결정: 도움말이 인용하는데 상수가 없는 문구를 앱 타깃 상수로 꺼낸다. 화면 글자는 그대로다. 그래서 기존 스냅샷 그림은 바뀌지 않는다.

  | 문구 | 지금 자리 | 새 자리 |
  |---|---|---|
  | "무엇을 할까요?", "시작", "완료", "미루기", "바꾸기", "이어서 할 일" | `ExpandedView.swift`, `ExpiredView.swift` 글자 | `NotchText`(새 파일 `App/Sources/Views/NotchText.swift`) |
  | "등록", "돌아가기" | `CheckpointNotesView.swift`, `ExpandedView.swift` 글자 | `NotchText.register`, `NotchText.back` |
  | "설정…", "종료" | `MokaApp.swift`(`OpenSettingsButton`, 메뉴), `NotchPanelHost.swift` 우클릭 메뉴 글자 | `NotchText.settingsMenu`, `NotchText.quit`(`Views/`에 두어 시험 번들이 읽음. 메뉴 두 곳이 이것을 씀) |
  | "저장", "취소" | `TaskFormView.swift`, `ContextFormView.swift` 글자 | `SheetText.save`, `SheetText.cancel` |
  | "적기", "지금은 넘기기" | `GateView.swift` 글자 | `GateDisplay.submit`, `GateDisplay.skip` |
  | "전체", "오늘", "이번 주", "만든 순", "마감 순" | `TaskListTabView.swift` 글자 | `TaskListText`(같은 파일 맨 위 `enum`) |
  | "D-day", "D+2" | `ReasonText.deadline`(MokaCore, `private`) | 접근 수준만 `public`으로 |

- 이미 상수인 것: `GateDisplay.title`·`keyNoticeText`·`keyNoticeButton`, `DecisionFieldText.destinationPrefix`, `SettingsTab.basic.title`, `ContextText.impact(_:)`, `TaskRowText.rankBadge(rank:isNext:)`, `ReasonText.line(_:)`.
- "판단을 받으러 보내는 곳"은 `destinationPrefix`에서 끝의 `": "`를 뗀 값으로 만든다. 새 상수를 두지 않는다.
- 대안: 도움말이 인용하는 문구만 새로 적고 화면은 그대로 둠(R1 따옴표 검사가 손 인용을 막으므로 불가).

## R3. 도움말 펼침 상태의 자리 (spec R-707)

- 결정: `AppState.helpExpanded: Set<HelpTopic>`(메모리만). `SettingsView`가 바인딩으로 넘긴다.
- 이유: 할 일 탭 보기·정렬(`taskListScope`, `taskListOrder`)이 이미 같은 자리에 같은 규칙(앱을 켜 둔 동안만, 저장 안 함, spec 002 R-118)으로 있다. 앱 시험 번들은 `SettingsView.swift`를 컴파일하지 않고 `AppState.swift`는 컴파일하므로(`project.yml` `MokaAppTests.sources`), 탭을 오가도 남는지를 앱 시험으로 지킬 수 있다.
- 결과: 설정 창을 닫았다 열어도 앱을 켜 둔 동안은 펼친 채다.
- 대안: `SettingsView`의 `@State`(설정 창을 닫으면 사라지고, 시험 번들 밖이라 자동 시험이 없음).

## R4. 안내 장 그림을 실제 노치 뷰로 그린다 (spec R-710, Q8)

- 결정: `App/Sources/Views/GuideIllustration.swift`가 안내 장마다 실제 뷰에 가짜 값을 넣어 그린다.
  - 노치 장: `NotchContentView` 둘. 접힘은 `timer: .running(title: "가짜 할 일 A", quantumMin: 25, startedAt:endsAt:)`, `remainingSeconds: 1122`, `isExpanded: false`. 펼침은 `timer: .empty(초안 "가짜 할 일 A")`, `isExpanded: true`, 칩 25분.
  - 순위 장: 펼친 `NotchContentView`에 `reasonLine: ReasonText.line(ReasonLine(deadline: .left(3), impact: "보통", skipCount: 2))`, 그 아래 할 일 탭 줄 둘(`RankBadge`에 `TaskRowText.rankBadge(rank: 1, isNext: true)`와 `rank: 2`).
  - 첫 행동 칸 장: 펼친 `NotchContentView`에 `gate: GateInput(phase: .asking, text: .constant("가짜 자료 열기"), ...)`.
  - 콜백은 모두 빈 함수다. 그림 전체에 `.allowsHitTesting(false)`, `.focusable(false)`을 걸고, 접근성은 `.accessibilityElement(children: .ignore)`와 장마다 설명 한 줄이다(R-716).
- 근거: `NotchContentView`는 AppState를 모르고 값과 콜백만 받는다(`NotchContentView.swift:6`, ADR-0009). 스냅샷 시험(`ScreenStateSnapshotTests.swift:305`)이 이미 같은 방법으로 그린다. 그래서 도형 그림으로 낮출 필요가 없다.
- 바꾸는 접근 수준: `TaskListTabView.swift`의 `private struct RankBadge`를 `internal`로. 같은 앱 타깃 안이라 모듈 경계는 바뀌지 않는다.
- 노치 판 크기: `NotchMetrics(holeWidth: 120, height: 32)`로 줄여 400pt 창 안에 들게 한다(시안 10~12번의 300pt 판). 실제 화면 노치 크기와 다르다는 것은 그림의 한계로 받아들인다.
- 대안: 그림을 PNG로 넣음(화면이 바뀌어도 그림은 옛 모양, Q8에서 버림), 도형으로 다시 그림(손그림, Q8에서 버림).

## R5. 온보딩 단계 확장 (spec R-711·R-712, Q1·Q2·Q4)

- 결정: `OnboardingSteps.Page`에 `.guide(GuideCard)`를 더한다. 쪽 목록은 `hasGuide`이면 안내 장 셋을 맨 앞에 두고, 그 뒤는 지금과 같다(`hasKeyStep`이면 키, 일정, 기본값, 아니면 일정, 기본값). 단계 표시는 이 목록 그대로 세므로 n/6 또는 n/5가 된다. `skipGuide()`는 첫 설정 단계로 간다.
- 초기화: `init(hasGuide: Bool, hasKeyStep: Bool, initialStep: Int)`. 기존 시험은 `hasGuide: false`를 넣어 호출만 고치고 기대값은 그대로 둔다(SC-706). 앱(`MokaApp.swift`의 `OnboardingWindow`)은 늘 `true`다.
- `OnboardingView`는 `showsGuide: Bool = true`를 받는다. 안내 장 쪽은 `GuideCardView`(R7)를 그리고 단계 표시 `StepBar`는 그대로 쓴다. 기존 온보딩 스냅샷 시험은 `initialStep`을 3 올려 같은 설정 단계를 찍는다. 그림 안 단계 표시가 1/3에서 4/6으로 바뀐다(SC-707).
- 첫 설정 단계에는 "이전"을 두지 않는다(spec R-712, 지금 코드 그대로).
- 대안: 안내 장을 별도 뷰 흐름으로 두고 `OnboardingSteps`는 그대로(단계 표시를 한 줄로 세는 Q2와 어긋남).

## R6. 다시 보기 시트 (spec R-713·R-714, Q3·Q9·Q12)

- 결정: `SettingsView`에 `@State private var isShowingGuide = false`와 `.sheet(isPresented:)`를 더하고, 시트 내용은 `GuideSheetView(onClose:)`다. `GuideSheetView`는 `App/Sources/Views/`에 두어 시험 번들이 컴파일한다.
  - 안내 장 셋만, 1/3~3/3, "안내 건너뛰기" 없음, 마지막 장 "다 봤어요".
  - esc는 숨은 취소 버튼(`.keyboardShortcut(.cancelAction)`)으로 `onClose`를 부른다. 설정 창을 닫으면 SwiftUI가 시트를 함께 닫는다.
  - `GuideSheetView`는 저장소, 키 보관함, `AppState`를 인자로 받지 않는다. 쓰기 0건(SC-705)을 타입으로 막는다.
  - 탭 요청(`settingsTabRequest`)이 와도 시트를 닫지 않는다. 지금 `onChange(of: appState.settingsTabRequest)`는 `tab`만 바꾸므로 그대로 둔다.
  - 온보딩 창(`OnboardingWindow`, 별도 `NSWindow`)과는 아무것도 나누지 않는다.
- 이유: Q9 사용자 결정. 시트는 설정 창에 붙어 "이미 열려 있으면 앞으로 올림"과 빨간 버튼 처리가 필요 없다.
- 대안: `NSWindow` 별도 창(Q9에서 버림).

## R7. 안내 장 뷰 하나를 온보딩과 시트가 함께 쓴다

- 결정: `GuideCardView(card: GuideCard, index: Int, total: Int, presentation: GuidePresentation, onBack:onSkip:onNext:)`. 버튼 규칙은 순수 함수 `GuideButtons.make(index:total:presentation:)`가 정한다(data-model §4). 온보딩은 `onNext`로 `steps.next()`, 시트는 마지막 장에서 `onClose`.
- 이유: 두 곳의 글과 그림이 어긋날 수 없고, 버튼 규칙을 리눅스가 아닌 앱 시험 번들의 단위 시험으로 지킨다.

## R8. 시험 번들 경계

- `MokaAppTests`는 `App/Sources/Views`와 `AppState.swift`만 컴파일한다. 그래서 새 뷰와 규칙(`HelpContent`, `HelpTabView`, `GuideCardView`, `GuideSheetView`, `GuideButtons`, `GuideIllustration`, `OnboardingSteps`)은 모두 `Views/`에 둔다.
- `SettingsView.swift`(탭 연결, 시트 띄우기)와 `MokaApp.swift`(온보딩에 `showsGuide: true`)는 시험 번들 밖이다. 이 연결은 앱 빌드와 사람 확인(quickstart 6)으로 본다.
- MokaCore에서 바뀌는 것은 `ReasonText.deadline`의 접근 수준 하나다. 리눅스 `swift test`에 시험 하나를 더한다.

## R9. 스냅샷 목록

- 새 상태(라이트·다크): 도움말 탭 접힘, 항목 1~8 펼침(라이트만, 확정 시안과 같음), 온보딩 안내 장 1/6·2/6·3/6, 키 단계가 없을 때 1/5, 시트 1/3·3/3. 이름은 data-model §7.
- 바뀌는 기존 상태: 설정 창 탭 줄이 들어간 모든 설정 창 스냅샷(넷째 탭), 온보딩 설정 단계 스냅샷(단계 표시 4/6~6/6). 그 밖의 스냅샷은 그대로다(SC-707).
- 스냅샷 시험은 기준 이미지와 비교하지 않고 sanity만 본다(`ScreenStateSnapshotTests.swift` 머리말). 시안과 맞는지는 비교 페이지(`~/Dev/ai-platform/projects/moka/design/pr-<번호>/index.html`)에서 사람이 본다.

## R10. 승인 항목

- 결정: 없음. 공개 계약(DecisionProvider, `questions.json`, `moka-sim` 시나리오 형식), 스키마, 의존성, CI, 모듈 경계(타깃·제품·`project.yml` 소스 목록)를 바꾸지 않는다. 설정 키도 더하지 않는다(Q10).
- 접근 수준 변경 둘(`ReasonText.deadline`의 `public`, `RankBadge`의 `internal`)은 같은 모듈 안 공개 범위 조정이다. MokaCore 공개 API가 하나 늘지만 공개 계약 목록(AGENTS.md)에 들지 않는다. 구현 PR "가정"에 적는다.
