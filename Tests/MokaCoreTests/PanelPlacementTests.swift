import MokaCore
import Testing

/// 14인치 노치 맥 비슷한 내장 화면(가짜 치수): 폭 1512, 노치 양옆 표시 영역 662씩, 노치 높이 32.
private let builtIn = ScreenGeometry(
    frame: PanelRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: PanelRect(x: 0, y: 0, width: 1512, height: 950),
    safeAreaTop: 32, auxiliaryTopLeftWidth: 662, auxiliaryTopRightWidth: 662)

/// 메뉴 막대 25pt인 외부 모니터(가짜 치수).
private let external = ScreenGeometry(
    frame: PanelRect(x: 0, y: 0, width: 1920, height: 1080),
    visibleFrame: PanelRect(x: 0, y: 0, width: 1920, height: 1055),
    safeAreaTop: 0, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)

@Test("FR-06 R-011: 노치 화면이면 노치 가운데·화면 맨 위에 노치 크기로 붙인다")
func notchAnchorAtNotch() {
    let anchor = panelAnchor(for: .notch(1), on: builtIn)
    #expect(anchor == PanelAnchor(centerX: 756, top: 982, holeWidth: 188, barHeight: 32))
}

@Test("FR-06 R-011: 노치 화면이 주 화면 왼쪽에 있어도 그 화면 좌표로 노치 가운데를 구한다")
func notchAnchorOnOffsetScreen() {
    var screen = builtIn
    screen.frame.x = -1512
    screen.frame.y = 98
    let anchor = panelAnchor(for: .notch(1), on: screen)
    #expect(anchor == PanelAnchor(centerX: -756, top: 1080, holeWidth: 188, barHeight: 32))
}

@Test("FR-06 R-011: 떠 있는 창은 노치 구멍 없이 메뉴 막대 아래 8pt, 화면 가운데에 둔다")
func floatingAnchorBelowMenuBar() {
    let anchor = panelAnchor(for: .floating(2), on: external)
    #expect(
        anchor
            == PanelAnchor(
                centerX: 960, top: 1047, holeWidth: 0, barHeight: PanelPlacementMetrics.floatingBarHeight))
}

@Test("FR-06 R-011: 떠 있는 창은 노치 화면 안내 값(노치 양옆 영역)이 있어도 쓰지 않는다")
func floatingIgnoresNotchAreas() {
    let anchor = panelAnchor(for: .floating(1), on: builtIn)
    #expect(anchor == PanelAnchor(centerX: 756, top: 942, holeWidth: 0, barHeight: 28))
}

@Test("FR-06 R-011: 떠 있는 창은 다른 화면 좌표에서도 그 화면 가운데")
func floatingAnchorOnOffsetScreen() {
    var screen = external
    screen.frame.x = 1512
    screen.visibleFrame.x = 1512
    let anchor = panelAnchor(for: .floating(2), on: screen)
    #expect(anchor.centerX == 2472)
}

@Test("FR-06 R-011: 패널 위치는 기준점 가운데·위에 붙이고 가로는 화면 픽셀 단위로 맞춘다")
func panelFrameSnapsToPixels() {
    let anchor = PanelAnchor(centerX: 756.25, top: 982, holeWidth: 188, barHeight: 32)
    let retina = panelFrame(anchor: anchor, width: 500, height: 216, scale: 2)
    #expect(retina == PanelRect(x: 506.5, y: 766, width: 500, height: 216))
    let standard = panelFrame(anchor: anchor, width: 500, height: 216, scale: 1)
    #expect(standard == PanelRect(x: 506, y: 766, width: 500, height: 216))
}
