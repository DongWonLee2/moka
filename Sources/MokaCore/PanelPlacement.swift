/// 화면 좌표 사각형(AppKit 좌표: 원점 왼쪽 아래, y가 위로 커진다). 리눅스 시험을 위해 CoreGraphics 대신 Double로 둔다.
public struct PanelRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// 패널 위치를 정하는 데 필요한 화면 치수(`NSScreen`에서 앱이 옮겨 담는다).
/// `auxiliaryTop*Width`는 노치 양옆 표시 영역 폭이고 노치 없는 화면에서는 nil이다.
public struct ScreenGeometry: Equatable, Sendable {
    public var frame: PanelRect
    public var visibleFrame: PanelRect
    public var safeAreaTop: Double
    public var auxiliaryTopLeftWidth: Double?
    public var auxiliaryTopRightWidth: Double?

    public init(
        frame: PanelRect, visibleFrame: PanelRect, safeAreaTop: Double,
        auxiliaryTopLeftWidth: Double?, auxiliaryTopRightWidth: Double?
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftWidth = auxiliaryTopLeftWidth
        self.auxiliaryTopRightWidth = auxiliaryTopRightWidth
    }
}

/// 판을 붙일 기준점: 가로 가운데와 위 끝, 접힌 판의 구멍 폭과 높이.
/// 떠 있는 창은 구멍이 없다(`holeWidth == 0`).
public struct PanelAnchor: Equatable, Sendable {
    public var centerX: Double
    public var top: Double
    public var holeWidth: Double
    public var barHeight: Double

    public init(centerX: Double, top: Double, holeWidth: Double, barHeight: Double) {
        self.centerX = centerX
        self.top = top
        self.holeWidth = holeWidth
        self.barHeight = barHeight
    }
}

/// 떠 있는 창 치수(시안 v3.5 7번: 접힌 판 높이 28pt, 메뉴 막대 아래 8pt).
public enum PanelPlacementMetrics {
    public static let floatingBarHeight: Double = 28
    public static let floatingGapBelowMenuBar: Double = 8
}

/// 표시 위치(R-011)에 맞는 기준점. 노치는 노치 구멍 가운데·화면 맨 위,
/// 떠 있는 창은 화면 가운데·메뉴 막대 아래(`visibleFrame` 위 끝에서 8pt 아래).
public func panelAnchor(for target: DisplayTarget, on screen: ScreenGeometry) -> PanelAnchor {
    let frame = screen.frame
    switch target {
    case .notch:
        let left = screen.auxiliaryTopLeftWidth ?? 0
        let right = screen.auxiliaryTopRightWidth ?? 0
        let hole = max(frame.width - left - right, 0)
        return PanelAnchor(
            centerX: frame.x + left + hole / 2, top: frame.y + frame.height,
            holeWidth: hole, barHeight: screen.safeAreaTop)
    case .floating:
        let visible = screen.visibleFrame
        return PanelAnchor(
            centerX: frame.x + frame.width / 2,
            top: visible.y + visible.height - PanelPlacementMetrics.floatingGapBelowMenuBar,
            holeWidth: 0, barHeight: PanelPlacementMetrics.floatingBarHeight)
    }
}

/// 고정 크기 패널을 기준점 가운데·위에 붙인 창 위치. 가로 원점은 정수가 아니라 화면 픽셀(`scale`) 단위로 맞춰
/// 노치 가운데가 반 포인트여도 어긋나지 않게 한다.
public func panelFrame(anchor: PanelAnchor, width: Double, height: Double, scale: Double) -> PanelRect {
    let x = ((anchor.centerX - width / 2) * scale).rounded() / scale
    return PanelRect(x: x, y: anchor.top - height, width: width, height: height)
}
