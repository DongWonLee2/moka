import SwiftUI
import XCTest

/// 입력 칸 테두리(data-model §6 포커스 표): 포커스 색은 패널이 key이고 칸이 실제 입력을 받을 때만.
/// 마우스를 올려 펼치기만 한 상태(패널이 key가 아님)에서는 칸이 SwiftUI 포커스를 쥐고 있어도 칠하지 않는다.
final class FieldBorderTests: XCTestCase {
    func test_R002_focusColorOnlyWhenPanelIsKeyAndFieldFocused() {
        XCTAssertEqual(FieldBorder.kind(invalid: false, focused: true, panelIsKey: true), .focus)
        XCTAssertEqual(FieldBorder.kind(invalid: false, focused: true, panelIsKey: false), .normal)
        XCTAssertEqual(FieldBorder.kind(invalid: false, focused: false, panelIsKey: true), .normal)
        XCTAssertEqual(FieldBorder.kind(invalid: false, focused: false, panelIsKey: false), .normal)
    }

    func test_R004_invalidCustomMinutesStaysRedRegardlessOfFocus() {
        XCTAssertEqual(FieldBorder.kind(invalid: true, focused: true, panelIsKey: true), .error)
        XCTAssertEqual(FieldBorder.kind(invalid: true, focused: false, panelIsKey: false), .error)
    }
}

/// hover 테두리는 펼침 끝무렵 짧게 나타나 펼침이 끝날 때 함께 완성되고, 접힐 때는 바로 사라진다. 동작 줄이기면 애니메이션 없이 바로.
final class HoverRingAnimationTests: XCTestCase {
    func test_R009_ringFadesInAfterExpansion() {
        XCTAssertEqual(
            NotchLayout.hoverRingAnimation(appearing: true, reduceMotion: false),
            .easeOut(duration: NotchLayout.hoverRingFadeDuration).delay(NotchLayout.hoverRingDelay))
    }

    func test_R009_ringCompletesWithExpansion() {
        XCTAssertEqual(
            NotchLayout.hoverRingDelay + NotchLayout.hoverRingFadeDuration, NotchLayout.expansionDuration,
            accuracy: 0.0001)
    }

    func test_R009_ringHidesImmediatelyOnCollapseOrReduceMotion() {
        XCTAssertNil(NotchLayout.hoverRingAnimation(appearing: false, reduceMotion: false))
        XCTAssertNil(NotchLayout.hoverRingAnimation(appearing: true, reduceMotion: true))
        XCTAssertNil(NotchLayout.hoverRingAnimation(appearing: false, reduceMotion: true))
    }
}
