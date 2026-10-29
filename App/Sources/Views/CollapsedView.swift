import MokaCore
import SwiftUI

/// 접힌 판 왼쪽 칸: 빈 상태는 회색 점(R-001), 할 일이 있으면 점·제목(넘치면 끝 "…", R-006).
struct CollapsedLeadingView: View {
    let timer: NotchTimer

    var body: some View {
        // 칸은 내용이 없어도 폭을 차지해야 하므로 Color.clear를 깐다(빈 ViewBuilder에 건 frame은 사라진다).
        ZStack(alignment: .leading) {
            Color.clear
            content.padding(.leading, 14)
        }
        .font(.system(size: 12))
        .foregroundStyle(MokaColors.notchForeground)
    }

    @ViewBuilder
    private var content: some View {
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
}

/// 접힌 판 오른쪽 칸: 남은 시간(R-006). 빈 상태는 비어 있다.
struct CollapsedTrailingView: View {
    let timer: NotchTimer
    let remainingSeconds: Int?

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.clear
            if let remainingSeconds, !isEmpty {
                Text(RemainingFormat.string(remainingSeconds))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(isExpired ? MokaColors.danger : MokaColors.notchForeground)
                    .padding(.trailing, 14)
            }
        }
        .font(.system(size: 12))
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
