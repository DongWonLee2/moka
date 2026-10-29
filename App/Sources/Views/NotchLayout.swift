import MokaCore
import SwiftUI

/// 판의 가로 배치와 열고 접는 애니메이션.
/// 패널 창은 고정 크기이고, 판 모양은 SwiftUI 마스크가 같은 스프링으로 키우고 줄인다(research R6).
enum NotchLayout {
    /// 펼침·접힘 전환은 `AppState`가 이 애니메이션으로 `withAnimation` 한 곳에서 일으킨다.
    static func expansionAnimation(expanding: Bool, reduceMotion: Bool) -> Animation {
        if reduceMotion { return .smooth(duration: 0.2) }
        return expanding ? .snappy(duration: expansionDuration) : .smooth(duration: expansionDuration)
    }

    static let expansionDuration: TimeInterval = 0.4
    static let hoverRingFadeDuration: TimeInterval = 0.15
    static let hoverRingDelay: TimeInterval = expansionDuration * 0.75 - hoverRingFadeDuration

    /// hover 테두리는 펼침의 3/4 지점(눈에 다 펼쳐진 때)에 완성되도록 짧게 나타난다. 사라질 때와 동작 줄이기에서는 애니메이션 없이 바로 바뀐다(nil).
    static func hoverRingAnimation(appearing: Bool, reduceMotion: Bool) -> Animation? {
        guard appearing, !reduceMotion else { return nil }
        return .easeOut(duration: hoverRingFadeDuration).delay(hoverRingDelay)
    }

    /// 접힌 판의 구멍 왼쪽·오른쪽 칸 폭(시안 v3.5). 빈 상태는 점 하나 자리 28pt씩,
    /// 할 일이 있으면 왼쪽 104pt(R-006), 오른쪽은 "18:42" 52pt·"1:04:59" 64pt.
    static func collapsedSideWidths(
        timer: NotchTimer, remainingSeconds: Int?
    ) -> (leading: CGFloat, trailing: CGFloat) {
        guard case .empty = timer else {
            return (104, (remainingSeconds ?? 0) >= 3600 ? 64 : 52)
        }
        return (28, 28)
    }

    /// 판을 가로로 옮길 거리. 접힌 판은 양옆 폭이 달라 그대로 가운데에 두면 구멍이 노치에서 어긋나므로
    /// 구멍 가운데가 판 자리 가운데(노치 가운데)에 오게 민다. 펼친 판은 대칭이라 0.
    /// 떠 있는 창은 맞출 노치가 없으므로 판 자체를 가운데에 둔다(0).
    static func horizontalOffset(
        timer: NotchTimer, remainingSeconds: Int?, isExpanded: Bool, style: PanelStyle
    ) -> CGFloat {
        guard !isExpanded, style == .notch else { return 0 }
        let sides = collapsedSideWidths(timer: timer, remainingSeconds: remainingSeconds)
        return (sides.trailing - sides.leading) / 2
    }

    /// 마우스가 올라가 펼친 노치 판에만 모카 테두리를 그린다(시안 v3.5 `.ex.hover`, 2·5번).
    /// 시간 끝 자동 펼침처럼 마우스가 없으면 그리지 않는다. 떠 있는 창은 시안 7번에 테두리가 없다.
    static func showsHoverRing(isHovering: Bool, isExpanded: Bool, style: PanelStyle) -> Bool {
        isHovering && isExpanded && style == .notch
    }

    /// 고정 패널 크기: 가장 넓은 접힌 판(구멍 양옆을 넓은 쪽 폭으로 맞춘 대칭 폭)과 펼친 판이 들어가고,
    /// 스프링이 조금 넘쳐도 잘리지 않게 여유를 둔다.
    static func panelSize(metrics: NotchMetrics) -> CGSize {
        let overshoot: CGFloat = 24
        let collapsedWidth = metrics.holeWidth + 2 * 104
        let width = max(collapsedWidth, ExpandedView.width) + 2 * NotchShape.earRadius + 2 * overshoot
        // 폭을 짝수로 둬야 노치 가운데에 놓을 때 왼쪽 끝이 반 포인트로 떨어지지 않는다.
        // 높이: 가장 긴 펼친 판(제목 두 줄 + 칩 + 버튼 줄 + 직접 입력 이유 줄, 노치 아래 약 156pt)에 스프링 여유.
        return CGSize(width: (width / 2).rounded(.up) * 2, height: metrics.height + 184)
    }
}

extension AnyTransition {
    /// 흐림 + 크기 + 투명도 전환. DynamicNotchKit 1.1.0(MIT, Kai Azim) `BlurModifier.swift`·`NotchView.swift`의 전환 조합을 참고했다.
    static func notchEntry(scaleX: CGFloat = 1, scaleY: CGFloat = 1, anchor: UnitPoint) -> AnyTransition {
        .modifier(
            active: NotchEntryModifier(blur: 10, scaleX: scaleX, scaleY: scaleY, anchor: anchor),
            identity: NotchEntryModifier(blur: 0, scaleX: 1, scaleY: 1, anchor: anchor)
        )
        .combined(with: .opacity)
    }
}

private struct NotchEntryModifier: ViewModifier {
    let blur: CGFloat
    let scaleX: CGFloat
    let scaleY: CGFloat
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(x: scaleX, y: scaleY, anchor: anchor)
    }
}
