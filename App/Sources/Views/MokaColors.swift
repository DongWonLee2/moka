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
    /// 검정 위 5.81:1(작은 글자 4.5:1 이상).
    static let notchMuted = Color(hex: 0x8F857C)
    /// 대비 높이기: 검정 위 9.09:1.
    static let notchMutedHighContrast = Color(hex: 0xB3A99F)
    static let control = Color(hex: 0xFFF0E1, opacity: 0.11)
    static let controlDisabled = Color(hex: 0xFFF0E1, opacity: 0.05)
    static let textDisabled = Color(hex: 0x625951)
    static let textOnPrimary = Color(hex: 0xFFF8F0)
    /// 분할 컨트롤의 고르지 않은 칸 글자(시안 v3.4 `.seg span`).
    static let segmentText = Color(hex: 0xE6DDD4)
    static let field = Color(hex: 0x17120F)
    static let fieldLine = Color(hex: 0x3B302A)
    /// 입력칸 바탕(#17120F) 위 4.81:1. 시안 #6C625A는 3.13:1이라 올렸다.
    static let placeholder = Color(hex: 0x8A8078)
    /// 대비 높이기: 입력칸 바탕 위 8.05:1.
    static let placeholderHighContrast = Color(hex: 0xB3A99F)
    /// 빈 상태 점, 검정 위 3.51:1(의미 있는 그래픽 3:1 이상). 시안 #5C544D는 2.83:1.
    static let idleDot = Color(hex: 0x6A625B)

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
