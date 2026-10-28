public struct ScreenInfo: Equatable, Sendable {
    public var id: UInt32
    public var hasNotch: Bool
    public var isMain: Bool

    public init(id: UInt32, hasNotch: Bool, isMain: Bool) {
        self.id = id
        self.hasNotch = hasNotch
        self.isMain = isMain
    }
}

public enum DisplayTarget: Equatable, Sendable {
    case notch(UInt32)
    case floating(UInt32)
}

public func chooseDisplayTarget(_ screens: [ScreenInfo]) -> DisplayTarget? {
    if let notched = screens.first(where: \.hasNotch) {
        return .notch(notched.id)
    }
    guard let screen = screens.first(where: \.isMain) ?? screens.first else { return nil }
    return .floating(screen.id)
}
