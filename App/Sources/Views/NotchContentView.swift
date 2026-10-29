import MokaCore
import SwiftUI

/// 패널 하나에 들어가는 전체 내용: 접힘·펼침 내용과 노치 모양으로 자른 검은 바탕.
/// AppState를 모르고 값과 콜백만 받는다(스냅샷 번들이 앱 없이 컴파일할 수 있게).
///
/// 구조는 DynamicNotchKit 1.1.0(MIT, Kai Azim, https://github.com/MrKai77/DynamicNotchKit
/// `Sources/DynamicNotchKit/Views/NotchView.swift`)을 참고했다: 넉넉한 검은 사각형을 노치 모양으로 마스크하고,
/// 내용 크기가 바뀌면 마스크가 같은 애니메이션으로 따라 커진다. 전환 애니메이션은 부르는 쪽의 `withAnimation`이 정한다.
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

    var body: some View {
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
                    titleFocusRequest: titleFocusRequest,
                    onEnterTitle: onEnterTitle, onStart: onStart, onComplete: onComplete
                )
                .transition(reduceMotion ? .opacity : .notchEntry(scaleY: 0.6, anchor: .top))
            }
        }
        .padding(.horizontal, NotchShape.earRadius)
        .background {
            // 스프링이 조금 넘쳐도 빈틈이 보이지 않게 마스크보다 넉넉히 칠한다.
            Rectangle().fill(MokaColors.notchBackground).padding(-50)
        }
        .mask {
            NotchShape(bottomRadius: isExpanded ? 18 : 10)
        }
        .offset(
            x: NotchLayout.horizontalOffset(timer: timer, remainingSeconds: remainingSeconds, isExpanded: isExpanded))
    }

    /// 접힌 양옆 내용은 노치 쪽으로 오므라들며 사라지고 노치 쪽에서 펴지며 나온다.
    private func sideTransition(towardHole anchor: UnitPoint) -> AnyTransition {
        reduceMotion ? .opacity : .notchEntry(scaleX: 0, anchor: anchor)
    }
}
