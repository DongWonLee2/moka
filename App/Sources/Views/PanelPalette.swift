import SwiftUI

/// 판을 어디에 어떤 모양으로 띄우는지(R-011). 노치는 노치 모양, 떠 있는 창은 둥근 사각형이다.
enum PanelStyle: Equatable {
    case notch
    case floating
}

/// 판 안 글자·바탕·컨트롤 색. 노치 판은 화면 테마와 상관없이 늘 검정이고,
/// 떠 있는 창은 라이트·다크를 따른다(시안 v3.5 7번 `.fl`·`.flx`).
struct PanelPalette {
    var background: Color
    var foreground: Color
    var muted: Color
    var mutedHighContrast: Color
    var wordmark: Color
    var activeDot: Color
    var activeDotGlows: Bool
    var idleDot: Color
    var field: Color
    var fieldLine: Color
    var placeholder: Color
    var placeholderHighContrast: Color
    var control: Color
    var controlDisabled: Color
    var textDisabled: Color
    var segmentText: Color
    var danger: Color
    /// 떠 있는 창은 바탕 화면 위에 뜨므로 그림자로 떼어 보인다. 노치는 그림자가 없다.
    var hasShadow: Bool

    static let notch = PanelPalette(
        background: MokaColors.notchBackground,
        foreground: MokaColors.notchForeground,
        muted: MokaColors.notchMuted,
        mutedHighContrast: MokaColors.notchMutedHighContrast,
        wordmark: MokaColors.foam.opacity(0.92),
        activeDot: MokaColors.crema,
        activeDotGlows: true,
        idleDot: MokaColors.idleDot,
        field: MokaColors.field,
        fieldLine: MokaColors.fieldLine,
        placeholder: MokaColors.placeholder,
        placeholderHighContrast: MokaColors.placeholderHighContrast,
        control: MokaColors.control,
        controlDisabled: MokaColors.controlDisabled,
        textDisabled: MokaColors.textDisabled,
        segmentText: MokaColors.segmentText,
        danger: MokaColors.danger,
        hasShadow: false)

    /// 다크 떠 있는 창: 바탕 #26201C 90%. 노치 판 색을 쓰되 바탕이 밝아진 만큼 흐린 글자와 빈 점만 올렸다.
    static let floatingDark: PanelPalette = {
        var palette = notch
        palette.background = Color(hex: 0x26201C, opacity: 0.9)
        // #26201C 위 4.82:1(노치 #8F857C는 4.45:1).
        palette.muted = Color(hex: 0x958B82)
        // #26201C 위 3.41:1(노치 #6A625B는 2.69:1).
        palette.idleDot = Color(hex: 0x7A726B)
        palette.hasShadow = true
        return palette
    }()

    /// 라이트 떠 있는 창: 바탕 #FFFCF8 88%, 글자 #1D1B19, 점은 모카 #A47864(빛 번짐 없음), "MOKA"는 #85604F.
    /// 대비는 #FFFCF8 기준.
    static let floatingLight = PanelPalette(
        background: Color(hex: 0xFFFCF8, opacity: 0.88),
        foreground: Color(hex: 0x1D1B19),
        // 5.64:1
        muted: Color(hex: 0x6E645C),
        // 9.61:1
        mutedHighContrast: Color(hex: 0x4A423C),
        // 5.43:1
        wordmark: MokaColors.mochaLow,
        // 3.77:1
        activeDot: MokaColors.mocha,
        activeDotGlows: false,
        // 3.30:1
        idleDot: Color(hex: 0x948A82),
        field: Color.white,
        fieldLine: Color(hex: 0xD9CEC5),
        // 흰 입력칸 위 5.20:1
        placeholder: Color(hex: 0x756B63),
        placeholderHighContrast: Color(hex: 0x4A423C),
        control: Color(hex: 0x3C2314, opacity: 0.08),
        controlDisabled: Color(hex: 0x3C2314, opacity: 0.04),
        textDisabled: Color(hex: 0xA39A92),
        // 12.28:1
        segmentText: Color(hex: 0x3A322C),
        // 4.95:1. 시간 끝 #E5533D는 밝은 바탕 위 3.64:1이라 작은 안내 글자에 모자라 어둡게 했다.
        danger: Color(hex: 0xC73E2A),
        hasShadow: true)

    static func resolve(style: PanelStyle, colorScheme: ColorScheme) -> PanelPalette {
        switch style {
        case .notch: notch
        case .floating: colorScheme == .light ? floatingLight : floatingDark
        }
    }
}

extension EnvironmentValues {
    @Entry var panelPalette = PanelPalette.notch
}
