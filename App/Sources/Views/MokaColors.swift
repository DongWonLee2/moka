import SwiftUI

/// 시안 v3.5의 색. 노치 판은 화면 테마와 상관없이 늘 검정 바탕이다.
enum MokaColors {
    static let mocha = Color(hex: 0xA47864)
    static let mochaHighlight = Color(hex: 0xB68C78)
    static let mochaLow = Color(hex: 0x85604F)
    static let crema = Color(hex: 0xE6C7B4)
    static let foam = Color(hex: 0xF5E9E1)
    static let danger = Color(hex: 0xE5533D)

    static let notchBackground = Color.black
    static let notchForeground = Color(hex: 0xF5EFE9)
    static let notchMuted = Color(hex: 0x8F857C)
    static let control = Color(hex: 0xFFF0E1, opacity: 0.11)
    static let controlDisabled = Color(hex: 0xFFF0E1, opacity: 0.05)
    static let textDisabled = Color(hex: 0x625951)
    static let textOnPrimary = Color(hex: 0xFFF8F0)
    static let field = Color(hex: 0x17120F)
    static let fieldLine = Color(hex: 0x3B302A)
    static let placeholder = Color(hex: 0x6C625A)
    static let idleDot = Color(hex: 0x5C544D)

    /// 기본 버튼 세로 그라데이션 #A47864 → #85604F.
    static var primaryGradient: LinearGradient {
        LinearGradient(colors: [mocha, mochaLow], startPoint: .top, endPoint: .bottom)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}
