import MokaCore
import SwiftUI

/// 접힌 판: 노치 구멍 양옆에 점·제목(왼쪽)과 남은 시간(오른쪽). R-001·R-006.
struct CollapsedView: View {
    let timer: NotchTimer
    let remainingSeconds: Int?
    let metrics: NotchMetrics

    var body: some View {
        HStack(spacing: 0) {
            leading
                .padding(.leading, 14)
                .frame(width: leadingWidth, alignment: .leading)
            Color.clear.frame(width: metrics.holeWidth)
            trailing
                .padding(.trailing, 14)
                .frame(width: trailingWidth, alignment: .trailing)
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

    /// 빈 상태는 점 하나 자리(28pt), 할 일이 있으면 R-006의 104pt.
    private var leadingWidth: CGFloat { isEmpty ? 28 : 104 }

    /// 시안: "18:42"는 52pt, "1:04:59"는 64pt.
    private var trailingWidth: CGFloat {
        guard !isEmpty, let remainingSeconds else { return 28 }
        return remainingSeconds >= 3600 ? 64 : 52
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
