import MokaCore
import SwiftUI

/// 패널 하나에 들어가는 전체 내용: 접힘·펼침 내용과 판 모양으로 자른 바탕.
/// 노치(`.notch`)는 노치 모양 검은 판, 떠 있는 창(`.floating`)은 구멍 없는 둥근 사각형이고 라이트·다크를 따른다(R-011).
/// AppState를 모르고 값과 콜백만 받는다(스냅샷 번들이 앱 없이 컴파일할 수 있게).
///
/// 구조는 DynamicNotchKit 1.1.0(MIT, Kai Azim, https://github.com/MrKai77/DynamicNotchKit
/// `Sources/DynamicNotchKit/Views/NotchView.swift`)을 참고했다: 넉넉한 검은 사각형을 노치 모양으로 마스크하고,
/// 내용 크기가 바뀌면 마스크가 같은 애니메이션으로 따라 커진다. 전환 애니메이션은 부르는 쪽의 `withAnimation`이 정한다.
struct NotchContentView: View {
    let timer: NotchTimer
    let remainingSeconds: Int?
    let isExpanded: Bool
    var isHovering = false
    /// 패널이 key window인지. 입력 칸 포커스 색에만 쓴다(data-model §6).
    var isPanelKey = false
    let metrics: NotchMetrics
    var style: PanelStyle = .notch
    let titleFocusRequest: Int
    let chip: QuantumChipInput
    let onEnterTitle: (String) -> Void
    let onStart: () -> Void
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = PanelPalette.resolve(style: style, colorScheme: colorScheme)
        let sides = NotchLayout.collapsedSideWidths(timer: timer, remainingSeconds: remainingSeconds)
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                if !isExpanded {
                    CollapsedLeadingView(timer: timer)
                        .frame(width: sides.leading, height: metrics.height)
                        .transition(sideTransition(towardHole: .trailing))
                }
                Color.clear.frame(width: metrics.holeWidth, height: metrics.height)
                if !isExpanded {
                    CollapsedTrailingView(timer: timer, remainingSeconds: remainingSeconds)
                        .frame(width: sides.trailing, height: metrics.height)
                        .transition(sideTransition(towardHole: .leading))
                }
            }
            if isExpanded {
                ExpandedView(
                    timer: timer, remainingSeconds: remainingSeconds, metrics: metrics,
                    titleFocusRequest: titleFocusRequest, chip: chip,
                    onEnterTitle: onEnterTitle, onStart: onStart, onComplete: onComplete
                )
                .transition(reduceMotion ? .opacity : .notchEntry(scaleY: 0.6, anchor: .top))
            }
        }
        .padding(.horizontal, style == .notch ? NotchShape.earRadius : 0)
        .background {
            // 스프링이 조금 넘쳐도 빈틈이 보이지 않게 마스크보다 넉넉히 칠한다.
            Rectangle().fill(palette.background).padding(-50)
        }
        .mask { shape }
        .background {
            // 판 둘레 바깥 1.5pt 테두리(시안 `.ex.hover`). 3pt 선의 안쪽 절반은 불투명한 판이 덮는다.
            // 위쪽 가장자리의 바깥 절반은 패널 창(화면 위 끝) 밖이라 보이지 않는다.
            // 펼침 애니메이션이 끝난 뒤 짧게 나타나고, 접힐 때는 바로 사라진다(전환에 붙인 애니메이션이 바깥 것을 덮는다).
            if NotchLayout.showsHoverRing(isHovering: isHovering, isExpanded: isExpanded, style: style) {
                NotchShape(bottomRadius: 18).stroke(MokaColors.mocha.opacity(0.8), lineWidth: 3)
                    // 테두리는 보이기만 한다. 클릭·hover 판정은 판 자체가 정한다.
                    .allowsHitTesting(false)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.animation(
                                NotchLayout.hoverRingAnimation(appearing: true, reduceMotion: reduceMotion)),
                            removal: .opacity.animation(
                                NotchLayout.hoverRingAnimation(appearing: false, reduceMotion: reduceMotion))))
            }
        }
        .shadow(color: palette.hasShadow ? .black.opacity(0.18) : .clear, radius: 8, y: 4)
        .environment(\.panelPalette, palette)
        .environment(\.panelIsKey, isPanelKey)
        .offset(
            x: NotchLayout.horizontalOffset(
                timer: timer, remainingSeconds: remainingSeconds, isExpanded: isExpanded, style: style))
    }

    /// 시안 v3.5: 노치는 위쪽 오목 곡선 + 아래 둥근 모서리(접힘 10pt·펼침 18pt),
    /// 떠 있는 창은 노치 모양 없는 둥근 사각형(접힘 8pt·펼침 12pt).
    @ViewBuilder
    private var shape: some View {
        switch style {
        case .notch:
            NotchShape(bottomRadius: isExpanded ? 18 : 10)
        case .floating:
            RoundedRectangle(cornerRadius: isExpanded ? 12 : 8, style: .continuous)
        }
    }

    /// 접힌 양옆 내용은 노치 쪽으로 오므라들며 사라지고 노치 쪽에서 펴지며 나온다.
    private func sideTransition(towardHole anchor: UnitPoint) -> AnyTransition {
        reduceMotion ? .opacity : .notchEntry(scaleX: 0, anchor: anchor)
    }
}
