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

public enum PanelPlacementMetrics {
    public static let floatingBarHeight: Double = 28
}

public func panelAnchor(for target: DisplayTarget, on screen: ScreenGeometry) -> PanelAnchor {
    PanelAnchor(centerX: 0, top: 0, holeWidth: 0, barHeight: 0)
}

public func panelFrame(anchor: PanelAnchor, width: Double, height: Double, scale: Double) -> PanelRect {
    PanelRect(x: 0, y: 0, width: 0, height: 0)
}
