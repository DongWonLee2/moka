import XCTest

/// spec 006 단위 5: 온보딩 키 단계 문구(시안 11~13번, 사람 확정 2026-11-12)와 "다음"·"건너뛰기" 규칙(R-624·R-625).
final class OnboardingKeyStepTests: XCTestCase {
    func test_FR21_R624_keyStepTexts() {
        XCTAssertEqual(OnboardingKeyText.title, "판단 모델 키가 있나요?")
        XCTAssertEqual(
            OnboardingKeyText.message, "TypeSafe에서 받은 키를 붙여 넣으면 판단 모델이 할 일 순서를 정해요. 키가 없으면 마감이 가까운 순으로 떠요.")
        XCTAssertEqual(OnboardingKeyText.issueLink, "TypeSafe에서 키 받기")
        XCTAssertEqual(OnboardingKeyText.otherProviders, "다른 판단 모델은 시작한 뒤 설정에서 고를 수 있어요.")
        XCTAssertEqual(OnboardingKeyText.fieldLabel, "키")
        XCTAssertEqual(OnboardingKeyText.placeholder, "키를 붙여 넣어 주세요")
        XCTAssertEqual(OnboardingKeyText.saveFailed, "키를 저장하지 못했어요. 다시 해 주세요.")
        XCTAssertEqual(OnboardingKeyText.saved, "저장되어 있어요")
    }

    func test_FR21_R624_nextIsOffUntilFieldHasKey() {
        var draft = OnboardingKeyDraft()
        XCTAssertFalse(draft.canGoNext(hasKey: false))
        draft.text = " \n "
        XCTAssertFalse(draft.canGoNext(hasKey: false), "공백만 있으면 꺼져 있다")
        draft.text = " fake-key "
        XCTAssertTrue(draft.canGoNext(hasKey: false))
        XCTAssertTrue(OnboardingKeyDraft().canGoNext(hasKey: true), "이미 있으면 칸 없이 켜져 있다")
    }

    func test_FR21_R625_failedSaveStaysAndShowsNotice() {
        var draft = OnboardingKeyDraft(text: "fake-key")
        var saved: [String] = []

        XCTAssertFalse(
            draft.submit(hasKey: false) {
                saved.append($0)
                return false
            })
        XCTAssertTrue(draft.saveFailed, "실패하면 키 단계에 머물고 문구를 보인다")
        XCTAssertEqual(draft.text, "fake-key", "다시 누를 수 있게 칸 글자를 둔다")

        XCTAssertTrue(
            draft.submit(hasKey: false) {
                saved.append($0)
                return true
            })
        XCTAssertFalse(draft.saveFailed, "다음 저장이 되면 문구를 지운다")
        XCTAssertEqual(draft.text, "", "저장한 키는 다시 보이지 않는다")
        XCTAssertEqual(saved, ["fake-key", "fake-key"])
    }

    func test_FR21_R625_existingKeyGoesNextWithoutSaving() {
        var draft = OnboardingKeyDraft()
        var called = false
        XCTAssertTrue(
            draft.submit(hasKey: true) { _ in
                called = true
                return false
            })
        XCTAssertFalse(called)
    }

    func test_FR21_R624_emptyFieldDoesNotSave() {
        var draft = OnboardingKeyDraft(text: "  ")
        var called = false
        XCTAssertFalse(
            draft.submit(hasKey: false) { _ in
                called = true
                return true
            })
        XCTAssertFalse(called)
        XCTAssertFalse(draft.saveFailed)
    }

    func test_FR21_R624_keyNextMovesToContextOnlyWhenSaved() {
        var steps = OnboardingSteps(hasGuide: false, hasKeyStep: true, initialStep: 1)
        var draft = OnboardingKeyDraft(text: "fake-key")
        XCTAssertEqual(steps.total, 3)
        XCTAssertEqual(steps.page, .key)

        steps.submitKey(&draft, hasKey: false) { _ in false }
        XCTAssertEqual(steps.step, 1, "저장에 실패하면 1/3에 머문다")
        XCTAssertEqual(steps.page, .key)
        XCTAssertTrue(draft.saveFailed)

        steps.submitKey(&draft, hasKey: false) { _ in true }
        XCTAssertEqual(steps.step, 2, "저장하면 2/3 일정으로 넘어간다")
        XCTAssertEqual(steps.page, .context)
    }

    func test_FR21_R624_existingKeyNextAndSkipMoveToContext() {
        var saved = OnboardingSteps(hasGuide: false, hasKeyStep: true, initialStep: 1)
        var draft = OnboardingKeyDraft()
        saved.submitKey(&draft, hasKey: true) { _ in false }
        XCTAssertEqual(saved.page, .context)

        var skipped = OnboardingSteps(hasGuide: false, hasKeyStep: true, initialStep: 1)
        skipped.next()
        XCTAssertEqual(skipped.page, .context, "건너뛰기는 저장 없이 2/3으로 간다")
    }

    func test_FR21_R624_threeStepsForwardAndBack() {
        var steps = OnboardingSteps(hasGuide: false, hasKeyStep: true, initialStep: 2)
        steps.next()
        XCTAssertEqual(steps.step, 3)
        XCTAssertEqual(steps.page, .defaults)
        steps.back()
        XCTAssertEqual(steps.step, 2, "\"이전\"은 3/3에서 2/3 일정으로 돌아간다")
        XCTAssertEqual(steps.page, .context)
    }

    func test_FR21_R116_twoStepsWithoutKeyStep() {
        var steps = OnboardingSteps(hasGuide: false, hasKeyStep: false, initialStep: 1)
        XCTAssertEqual(steps.total, 2)
        XCTAssertEqual(steps.page, .context)
        steps.next()
        XCTAssertEqual(steps.page, .defaults)
        steps.back()
        XCTAssertEqual(steps.page, .context)
    }
}
