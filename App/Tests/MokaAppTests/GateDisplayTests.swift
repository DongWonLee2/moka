import MokaCore
import XCTest

/// 노치 펼친 화면의 게이트 표시 규칙(spec 004 data-model §5, 확정 시안 4~8번). 글자는 확정 시안 그대로다.
final class GateDisplayTests: XCTestCase {
    func test_FR13_R307_startShortcutDetachedWhileAsking() {
        XCTAssertTrue(GateDisplay.detachesStartShortcut(isEnteringTitle: false, gatePhase: .asking))
        XCTAssertTrue(GateDisplay.detachesStartShortcut(isEnteringTitle: true, gatePhase: nil))
        XCTAssertFalse(GateDisplay.detachesStartShortcut(isEnteringTitle: false, gatePhase: .checking))
        XCTAssertFalse(GateDisplay.detachesStartShortcut(isEnteringTitle: false, gatePhase: .closed))
        XCTAssertFalse(GateDisplay.detachesStartShortcut(isEnteringTitle: false, gatePhase: nil))
    }

    /// 묻는 중이면 시작 버튼에서 ↵ 표시를 뺀다(확정 시안 4번). 확인하는 중은 ↵가 있다(5번).
    func test_FR13_R307_startLabelDropsReturnMarkWhileAsking() {
        XCTAssertNil(GateDisplay.startShortcutMark(gatePhase: .asking))
        XCTAssertEqual(GateDisplay.startShortcutMark(gatePhase: .checking), "↵")
        XCTAssertEqual(GateDisplay.startShortcutMark(gatePhase: .closed), "↵")
        XCTAssertEqual(GateDisplay.startShortcutMark(gatePhase: nil), "↵")
    }

    /// 확정 시안 12~14번 키 확인 한 줄.
    func test_FR14_R316_keyNoticeTexts() {
        XCTAssertEqual(GateDisplay.keyNoticeText, "키가 맞지 않아 판단 모델에 묻지 못하고 있어요.")
        XCTAssertEqual(GateDisplay.keyNoticeButton, "키 확인")
    }

    func test_FR13_R307_customMinutesEnterDoesNotStartWhileAsking() {
        XCTAssertFalse(GateDisplay.customEnterStarts(canStart: true, gatePhase: .asking))
        XCTAssertTrue(GateDisplay.customEnterStarts(canStart: true, gatePhase: .checking))
        XCTAssertTrue(GateDisplay.customEnterStarts(canStart: true, gatePhase: .closed))
        XCTAssertTrue(GateDisplay.customEnterStarts(canStart: true, gatePhase: nil))
        XCTAssertFalse(GateDisplay.customEnterStarts(canStart: false, gatePhase: nil))
    }

    func test_FR13_R311_firstActionHiddenWhileAskingOrChecking() {
        XCTAssertTrue(GateDisplay.hidesFirstAction(gatePhase: .asking))
        XCTAssertTrue(GateDisplay.hidesFirstAction(gatePhase: .checking))
        XCTAssertFalse(GateDisplay.hidesFirstAction(gatePhase: .closed))
        XCTAssertFalse(GateDisplay.hidesFirstAction(gatePhase: nil))
    }

    /// 새 할 일 제목 칸이 열린 동안은 게이트를 숨기고 닫히면 다시 보인다(시안 확정할 것 9번).
    func test_FR13_R307_gateHiddenWhileEnteringTitle() {
        XCTAssertTrue(GateDisplay.isVisible(gatePhase: .asking, isEnteringTitle: false))
        XCTAssertTrue(GateDisplay.isVisible(gatePhase: .checking, isEnteringTitle: false))
        XCTAssertFalse(GateDisplay.isVisible(gatePhase: .asking, isEnteringTitle: true))
        XCTAssertFalse(GateDisplay.isVisible(gatePhase: .closed, isEnteringTitle: false))
        XCTAssertFalse(GateDisplay.isVisible(gatePhase: nil, isEnteringTitle: false))
    }

    func test_FR13_R307_gateTexts() {
        XCTAssertEqual(GateDisplay.title, "어디서 시작할지 막연해 보여요")
        XCTAssertEqual(
            GateDisplay.subtitle(phase: .asking, submissions: 0),
            "2분 안에 바로 할 수 있는 첫 행동을 한 줄 적어 주세요. 판단 모델이 다시 확인하고, 노치를 펼치면 제목 아래 보여요.")
        XCTAssertEqual(
            GateDisplay.subtitle(phase: .checking, submissions: 1),
            "2분 안에 바로 할 수 있는 첫 행동을 한 줄 적어 주세요. 판단 모델이 다시 확인하고, 노치를 펼치면 제목 아래 보여요.")
        XCTAssertEqual(GateDisplay.subtitle(phase: .asking, submissions: 1), "방금 적은 줄이에요. 고쳐 써도 돼요.")
    }

    func test_FR13_R309_R310_gateMessages() {
        XCTAssertNil(GateDisplay.message(phase: .asking, submissions: 0, saveFailed: false))
        XCTAssertEqual(
            GateDisplay.message(phase: .checking, submissions: 1, saveFailed: false),
            GateDisplay.Message(text: "판단 모델에 다시 물어보고 있어요.", isError: false))
        XCTAssertEqual(
            GateDisplay.message(phase: .asking, submissions: 1, saveFailed: false),
            GateDisplay.Message(text: "조금 더 작게 적어 볼까요? 두 번 더 물어볼게요.", isError: false))
        XCTAssertEqual(
            GateDisplay.message(phase: .asking, submissions: 2, saveFailed: false),
            GateDisplay.Message(text: "조금 더 작게 적어 볼까요? 한 번 더 물어볼게요.", isError: false))
        XCTAssertEqual(
            GateDisplay.message(phase: .asking, submissions: 0, saveFailed: true),
            GateDisplay.Message(text: "첫 행동을 저장하지 못했어요. 다시 해 주세요.", isError: true))
        XCTAssertEqual(
            GateDisplay.message(phase: .asking, submissions: 1, saveFailed: true),
            GateDisplay.Message(text: "첫 행동을 저장하지 못했어요. 다시 해 주세요.", isError: true))
    }
}
