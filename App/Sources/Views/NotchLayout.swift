import MokaCore
import SwiftUI

/// 판의 가로 배치와 열고 접는 시간. 접힌 판은 양옆 폭이 달라서 판 가운데와 노치 구멍 가운데가 어긋난다.
/// 그래서 짧은 쪽에 투명 여백을 더해 늘 구멍이 내용 가운데에 오게 하고, 패널은 그 가운데를 노치 가운데에 둔다
/// (맞추지 않으면 왼쪽 끝 내용이 카메라 뒤로 숨는다). 여백까지 한 덩어리로 움직이므로 열고 접는 동안 판이 옆으로 튀지 않는다.
enum NotchLayout {
    /// 펼침: 반응이 빠르고 바운스가 작은 스프링(WWDC23 Animate with springs의 `.snappy`).
    static let expandAnimation = Animation.snappy(duration: 0.32)
    /// 접힘: 바운스 없이 빠르게 물러난다.
    static let collapseDuration: Double = 0.22
    static let collapseAnimation = Animation.smooth(duration: collapseDuration)
    /// 동작 줄이기: 바운스 없는 짧은 페이드만.
    static let reducedMotionAnimation = Animation.smooth(duration: 0.15)

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

    /// 판 가운데에서 구멍 가운데까지의 가로 거리(오른쪽이 +). 펼친 판은 좌우 대칭이라 0.
    static func holeCenterOffset(timer: NotchTimer, remainingSeconds: Int?, isExpanded: Bool) -> CGFloat {
        guard !isExpanded else { return 0 }
        let sides = collapsedSideWidths(timer: timer, remainingSeconds: remainingSeconds)
        return (sides.leading - sides.trailing) / 2
    }

    /// 구멍이 가운데에 오도록 짧은 쪽에 더할 투명 여백.
    static func balancingInsets(holeCenterOffset offset: CGFloat) -> EdgeInsets {
        EdgeInsets(top: 0, leading: max(-2 * offset, 0), bottom: 0, trailing: max(2 * offset, 0))
    }
}
