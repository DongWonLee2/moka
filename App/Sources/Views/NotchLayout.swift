import CoreGraphics
import MokaCore

/// 판의 가로 배치. 접힌 판은 양옆 폭이 달라서 판 가운데와 노치 구멍 가운데가 어긋난다.
/// 패널은 판 가운데가 아니라 구멍 가운데를 실제 노치 가운데에 맞춰야 한다(맞추지 않으면 왼쪽 끝 내용이 카메라 뒤로 숨는다).
enum NotchLayout {
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

    /// 구멍 가운데가 `notchCenterX`에 오도록 한 패널 왼쪽 x.
    static func panelMinX(contentWidth: CGFloat, holeCenterOffset: CGFloat, notchCenterX: CGFloat) -> CGFloat {
        notchCenterX - holeCenterOffset - contentWidth / 2
    }
}
