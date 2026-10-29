import MokaCore
import SwiftUI

/// 접힌 판: 노치 구멍 양옆에 점·제목(왼쪽)과 남은 시간(오른쪽). R-001·R-006.
struct CollapsedView: View {
    let timer: NotchTimer
    let remainingSeconds: Int?
    let metrics: NotchMetrics
    /// 펼침과 잇는 제목·남은 시간의 이름공간. nil이면 잇지 않는다(동작 줄이기).
    var namespace: Namespace.ID?

    var body: some View {
        let sides = NotchLayout.collapsedSideWidths(timer: timer, remainingSeconds: remainingSeconds)
        // 양옆 칸은 내용이 없어도 폭을 차지해야 한다(빈 ViewBuilder에 건 frame은 사라진다).
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                Color.clear
                leading.padding(.leading, 14)
            }
            .frame(width: sides.leading)
            Color.clear.frame(width: metrics.holeWidth)
            ZStack(alignment: .trailing) {
                Color.clear
                trailing.padding(.trailing, 14)
            }
            .frame(width: sides.trailing)
        }
        .frame(height: metrics.height)
        .font(.system(size: 12))
        .foregroundStyle(MokaColors.notchForeground)
    }

    @ViewBuilder
    private var leading: some View {
        switch timer {
        case .empty:
            StatusDot(active: false)
        case .running(let title, _, _, _), .expired(let title, _):
            HStack(spacing: 6) {
                StatusDot(active: true)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .matchedElement("title", in: namespace)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if let remainingSeconds, !isEmpty {
            Text(RemainingFormat.string(remainingSeconds))
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(isExpired ? MokaColors.danger : MokaColors.notchForeground)
                .matchedElement("remaining", in: namespace)
        }
    }

    private var isEmpty: Bool {
        if case .empty = timer { return true }
        return false
    }

    private var isExpired: Bool {
        if case .expired = timer { return true }
        return false
    }
}

struct StatusDot: View {
    let active: Bool

    var body: some View {
        Circle()
            .fill(active ? MokaColors.crema : MokaColors.idleDot)
            .frame(width: 6, height: 6)
            .shadow(color: active ? MokaColors.crema.opacity(0.7) : .clear, radius: 3)
    }
}
