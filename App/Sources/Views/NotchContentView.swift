import MokaCore
import SwiftUI

/// 패널 하나에 들어가는 전체 내용: 접힘 또는 펼침과 노치 모양 바탕.
/// AppState를 모르고 값과 콜백만 받는다(스냅샷 번들이 앱 없이 컴파일할 수 있게).
struct NotchContentView: View {
    let timer: NotchTimer
    let remainingSeconds: Int?
    let isExpanded: Bool
    let metrics: NotchMetrics
    let titleFocusRequest: Int
    let onEnterTitle: (String) -> Void
    let onStart: () -> Void
    let onComplete: () -> Void

    var body: some View {
        Group {
            if isExpanded {
                ExpandedView(
                    timer: timer, remainingSeconds: remainingSeconds, metrics: metrics,
                    titleFocusRequest: titleFocusRequest, onEnterTitle: onEnterTitle,
                    onStart: onStart, onComplete: onComplete)
            } else {
                CollapsedView(timer: timer, remainingSeconds: remainingSeconds, metrics: metrics)
            }
        }
        .padding(.horizontal, NotchShape.earRadius)
        .background(NotchShape(bottomRadius: isExpanded ? 18 : 10).fill(MokaColors.notchBackground))
        .animation(.snappy(duration: 0.18), value: isExpanded)
    }
}
