import MokaCore
import SwiftUI

/// 패널 하나에 들어가는 전체 내용: 접힘 또는 펼침과 노치 모양 바탕.
/// AppState를 모르고 값과 콜백만 받는다(스냅샷 번들이 앱 없이 컴파일할 수 있게).
/// 바깥 크기는 구멍이 가운데에 오도록 투명 여백을 더한 크기다(`NotchLayout.balancingInsets`).
struct NotchContentView: View {
    let timer: NotchTimer
    let remainingSeconds: Int?
    let isExpanded: Bool
    let metrics: NotchMetrics
    let titleFocusRequest: Int
    let onEnterTitle: (String) -> Void
    let onStart: () -> Void
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace

    var body: some View {
        // 동작 줄이기에서는 판 크기는 바로 바꾸고 내용만 짧게 페이드한다.
        let shapeAnimation: Animation? =
            reduceMotion ? nil : (isExpanded ? NotchLayout.expandAnimation : NotchLayout.collapseAnimation)
        let contentAnimation = shapeAnimation ?? NotchLayout.reducedMotionAnimation
        // 접힘과 펼침에 함께 있는 제목·남은 시간은 지웠다 다시 그리지 않고 새 자리로 옮긴다.
        let matchedNamespace = reduceMotion ? nil : namespace

        ZStack(alignment: .top) {
            if isExpanded {
                ExpandedView(
                    timer: timer, remainingSeconds: remainingSeconds, metrics: metrics,
                    titleFocusRequest: titleFocusRequest, namespace: matchedNamespace,
                    onEnterTitle: onEnterTitle, onStart: onStart, onComplete: onComplete
                )
                .transition(.opacity)
            } else {
                CollapsedView(
                    timer: timer, remainingSeconds: remainingSeconds, metrics: metrics, namespace: matchedNamespace
                )
                .transition(.opacity)
            }
        }
        .animation(contentAnimation, value: isExpanded)
        .padding(.horizontal, NotchShape.earRadius)
        .background(NotchShape(bottomRadius: isExpanded ? 18 : 10).fill(MokaColors.notchBackground))
        .padding(
            NotchLayout.balancingInsets(
                holeCenterOffset: NotchLayout.holeCenterOffset(
                    timer: timer, remainingSeconds: remainingSeconds, isExpanded: isExpanded))
        )
        .animation(shapeAnimation, value: isExpanded)
    }
}

extension View {
    /// 이름공간이 있을 때만 접힘·펼침 사이에서 같은 요소로 잇는다.
    @ViewBuilder
    func matchedElement(_ id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}
