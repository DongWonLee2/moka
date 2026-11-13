import XCTest

/// spec 007 단위 2: 온보딩 안내 장(R-710~R-712, R-716, data-model §4·§5). 글자는 확정 시안 10~12번 그대로다.
final class GuideTests: XCTestCase {
    func test_R712_guideButtonsTable() {
        let cases: [(GuidePresentation, Int, Int, GuideButtons)] = [
            (.onboarding, 1, 6, GuideButtons(showsBack: false, showsSkip: true, primary: "다음")),
            (.onboarding, 2, 6, GuideButtons(showsBack: true, showsSkip: true, primary: "다음")),
            (.onboarding, 3, 6, GuideButtons(showsBack: true, showsSkip: false, primary: "다음")),
            (.sheet, 1, 3, GuideButtons(showsBack: false, showsSkip: false, primary: "다음")),
            (.sheet, 2, 3, GuideButtons(showsBack: true, showsSkip: false, primary: "다음")),
            (.sheet, 3, 3, GuideButtons(showsBack: true, showsSkip: false, primary: "다 봤어요")),
        ]
        for (presentation, index, total, expected) in cases {
            XCTAssertEqual(
                GuideButtons.make(index: index, total: total, presentation: presentation), expected,
                "\(presentation) \(index)/\(total)")
        }
        XCTAssertEqual(
            GuideButtons.make(index: 3, total: 5, presentation: .onboarding),
            GuideButtons(showsBack: true, showsSkip: false, primary: "다음"), "키 단계가 없어도 셋째 장은 건너뛰기 없음")
    }

    func test_R711_sixStepsWithKeyStep() {
        var steps = OnboardingSteps(hasGuide: true, hasKeyStep: true, initialStep: 1)
        XCTAssertEqual(steps.total, 6)
        var pages: [OnboardingSteps.Page] = [steps.page]
        for _ in 2...6 {
            steps.next()
            pages.append(steps.page)
        }
        XCTAssertEqual(pages, [.guide(.notch), .guide(.rank), .guide(.firstAction), .key, .context, .defaults])
    }

    func test_R711_fiveStepsWithoutKeyStep() {
        var steps = OnboardingSteps(hasGuide: true, hasKeyStep: false, initialStep: 1)
        XCTAssertEqual(steps.total, 5)
        var pages: [OnboardingSteps.Page] = [steps.page]
        for _ in 2...5 {
            steps.next()
            pages.append(steps.page)
        }
        XCTAssertEqual(pages, [.guide(.notch), .guide(.rank), .guide(.firstAction), .context, .defaults])
    }

    func test_R712_skipGuideGoesToFirstSettingStep() {
        for start in [1, 2] {
            var withKey = OnboardingSteps(hasGuide: true, hasKeyStep: true, initialStep: start)
            withKey.skipGuide()
            XCTAssertEqual(withKey.step, 4, "\(start)/6에서 건너뛰면 4/6")
            XCTAssertEqual(withKey.page, .key)

            var withoutKey = OnboardingSteps(hasGuide: true, hasKeyStep: false, initialStep: start)
            withoutKey.skipGuide()
            XCTAssertEqual(withoutKey.step, 4, "\(start)/5에서 건너뛰면 4/5")
            XCTAssertEqual(withoutKey.page, .context)
        }
        for start in 4...6 {
            var steps = OnboardingSteps(hasGuide: true, hasKeyStep: true, initialStep: start)
            steps.skipGuide()
            XCTAssertEqual(steps.step, start, "설정 단계에서는 아무것도 안 한다")
        }
    }

    func test_R712_thirdGuideNextGoesToFirstSettingStep() {
        var withKey = OnboardingSteps(hasGuide: true, hasKeyStep: true, initialStep: 3)
        withKey.next()
        XCTAssertEqual(withKey.page, .key)

        var withoutKey = OnboardingSteps(hasGuide: true, hasKeyStep: false, initialStep: 3)
        withoutKey.next()
        XCTAssertEqual(withoutKey.page, .context)
    }

    func test_R711_guideIndex() {
        let indexes = (1...6).map { OnboardingSteps(hasGuide: true, hasKeyStep: true, initialStep: $0).guideIndex }
        XCTAssertEqual(indexes, [1, 2, 3, nil, nil, nil])
        XCTAssertNil(OnboardingSteps(hasGuide: false, hasKeyStep: true, initialStep: 1).guideIndex)
    }

    func test_R710_guideTexts() {
        XCTAssertEqual(GuideCard.allCases, [.notch, .rank, .firstAction])
        XCTAssertEqual(GuideText.title(.notch), "할 일은 노치에 떠요")
        XCTAssertEqual(GuideText.message(.notch), "마우스를 노치에 올리면 펼쳐져요. 시간을 고르고 \"시작\"을 누르면 접힌 노치에 남은 시간이 보여요.")
        XCTAssertEqual(GuideText.title(.rank), "무엇부터 할지 노치가 골라요")
        XCTAssertEqual(
            GuideText.message(.rank),
            "판단 모델이 마감과 일정을 보고 순서를 정해요. 키가 없으면 마감이 가까운 순으로 떠요. 펼친 노치의 제목 아래 줄에서 왜 떴는지 볼 수 있어요.")
        XCTAssertEqual(GuideText.title(.firstAction), "막연한 일은 첫 행동부터 적어요")
        XCTAssertEqual(
            GuideText.message(.firstAction),
            "어디서 시작할지 막연해 보이는 할 일이 뜨면 노치가 첫 행동 한 줄을 물어요. 적은 줄은 제목 아래 \"이어서 할 일\"로 보여요. 바로 시작하려면 \"지금은 넘기기\"를 눌러 주세요."
        )
        XCTAssertEqual(GuideText.skip, "안내 건너뛰기")
        XCTAssertEqual(GuideText.back, "이전")
        XCTAssertEqual(GuideText.next, "다음")
        XCTAssertEqual(GuideText.done, "다 봤어요")
    }

    func test_R716_guideAccessibilityLabels() {
        let labels = GuideCard.allCases.map(GuideText.accessibilityLabel)
        XCTAssertFalse(labels.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        XCTAssertEqual(Set(labels).count, labels.count, "장마다 다른 설명")
        XCTAssertFalse(labels.contains { $0.contains("\n") }, "한 줄")
    }

    /// SC-703 안내 장 절반: 따옴표 안 글자는 화면 상수와 같다. 화면 상수가 바뀌면 이 시험이 실패한다.
    func test_R705_guideQuotesComeFromScreenConstants() {
        XCTAssertEqual(Self.quotes(GuideText.message(.notch)), [NotchText.start])
        XCTAssertEqual(Self.quotes(GuideText.message(.rank)), [])
        XCTAssertEqual(Self.quotes(GuideText.message(.firstAction)), [NotchText.firstActionLabel, GateDisplay.skip])
        for card in GuideCard.allCases {
            XCTAssertEqual(Self.quotes(GuideText.title(card)), [], "제목에는 인용이 없다")
        }
    }

    func test_R711_keyStepFailStaysOn4of6() {
        var steps = OnboardingSteps(hasGuide: true, hasKeyStep: true, initialStep: 4)
        var draft = OnboardingKeyDraft(text: "fake-key")
        steps.submitKey(&draft, hasKey: false) { _ in false }
        XCTAssertEqual(steps.step, 4)
        XCTAssertEqual(steps.page, .key)
        XCTAssertTrue(draft.saveFailed)
    }

    func test_R711_keyStepSaveMovesTo5of6() {
        var steps = OnboardingSteps(hasGuide: true, hasKeyStep: true, initialStep: 4)
        var draft = OnboardingKeyDraft(text: "fake-key")
        steps.submitKey(&draft, hasKey: false) { _ in true }
        XCTAssertEqual(steps.step, 5)
        XCTAssertEqual(steps.page, .context)
    }

    func test_SC705_guidePagesNeverSaveOrFinish() {
        for start in 1...3 {
            var steps = OnboardingSteps(hasGuide: true, hasKeyStep: true, initialStep: start)
            var draft = OnboardingKeyDraft(text: "fake-key")
            var saves = 0
            steps.submitKey(&draft, hasKey: false) { _ in
                saves += 1
                return true
            }
            XCTAssertEqual(saves, 0, "\(start)/6 안내 장에서 키를 저장하지 않는다")
            XCTAssertEqual(steps.step, start)
            XCTAssertFalse(steps.canFinish)
        }
        XCTAssertFalse(OnboardingSteps(hasGuide: true, hasKeyStep: true, initialStep: 4).canFinish)
        XCTAssertFalse(OnboardingSteps(hasGuide: true, hasKeyStep: true, initialStep: 5).canFinish)
        XCTAssertTrue(OnboardingSteps(hasGuide: true, hasKeyStep: true, initialStep: 6).canFinish)
        XCTAssertTrue(OnboardingSteps(hasGuide: true, hasKeyStep: false, initialStep: 5).canFinish)
    }

    func test_R710_illustrationDetachesShortcutAndFocus() {
        XCTAssertTrue(GateDisplay.detachesStartShortcut(isEnteringTitle: false, gatePhase: nil, isIllustration: true))
        XCTAssertFalse(
            GateDisplay.detachesStartShortcut(isEnteringTitle: false, gatePhase: nil, isIllustration: false))
        XCTAssertTrue(
            GateDisplay.detachesStartShortcut(isEnteringTitle: false, gatePhase: .asking, isIllustration: false))

        XCTAssertFalse(GateDisplay.requestsFocus(phase: .asking, isIllustration: true))
        XCTAssertTrue(GateDisplay.requestsFocus(phase: .asking, isIllustration: false))
        XCTAssertFalse(GateDisplay.requestsFocus(phase: .checking, isIllustration: false))
        XCTAssertFalse(GateDisplay.requestsFocus(phase: .closed, isIllustration: false))

        XCTAssertFalse(GateDisplay.requestsFocus(true, isIllustration: true), "제목 칸도 그림에서는 포커스를 받지 않는다")
        XCTAssertTrue(GateDisplay.requestsFocus(true, isIllustration: false))
        XCTAssertFalse(GateDisplay.requestsFocus(false, isIllustration: false))
    }

    func test_R713_sheetStartsAtFirstOfThree() {
        let state = GuideSheetState()
        XCTAssertEqual(state.index, 1)
        XCTAssertEqual(GuideSheetState.total, 3)
        XCTAssertEqual(state.card, .notch)
    }

    func test_R713_sheetHasNoSkip() {
        var state = GuideSheetState()
        var cards: [GuideCard] = []
        repeat {
            cards.append(state.card)
            let buttons = GuideButtons.make(index: state.index, total: GuideSheetState.total, presentation: .sheet)
            XCTAssertFalse(buttons.showsSkip, "\(state.index)/3")
            XCTAssertEqual(buttons.showsBack, state.index > 1, "\(state.index)/3")
        } while !state.primary()
        XCTAssertEqual(cards, GuideCard.allCases, "시트에는 안내 장 셋만 보인다")
    }

    func test_R714_sheetLastPrimaryIsDoneAndCloses() {
        var state = GuideSheetState()
        XCTAssertFalse(state.primary())
        XCTAssertEqual(state.index, 2)
        XCTAssertFalse(state.primary())
        XCTAssertEqual(state.index, 3)
        XCTAssertEqual(state.card, .firstAction)
        XCTAssertEqual(
            GuideButtons.make(index: state.index, total: GuideSheetState.total, presentation: .sheet).primary,
            GuideText.done)
        XCTAssertTrue(state.primary(), "셋째 장 주 버튼은 시트를 닫는다")
        XCTAssertEqual(state.index, 3)

        state.back()
        XCTAssertEqual(state.index, 2)
        state.back()
        state.back()
        XCTAssertEqual(state.index, 1, "첫 장에서 이전은 머문다")
    }

    func test_R714_sheetCancelCloses() {
        for index in 1...GuideSheetState.total {
            let state = GuideSheetState(index: index)
            XCTAssertTrue(state.cancel(), "\(index)/3에서 esc는 닫는다")
        }
    }

    private static func quotes(_ text: String) -> [String] {
        let parts = text.components(separatedBy: "\"")
        return stride(from: 1, to: parts.count, by: 2).map { parts[$0] }
    }
}
