import MokaCore
import SwiftUI

extension EnvironmentValues {
    /// 안내 장 그림 안의 노치 뷰인지(research R4). 참이면 기본 버튼 단축키를 떼고 자동 포커스를 하지 않는다.
    @Entry var isNotchIllustration = false
}

/// 안내 장 그림(spec R-710, research R4). 손그림이 아니라 실제 노치 뷰 부품에 가짜 값을 넣어 그린다.
/// 누를 수 없고, VoiceOver에는 장마다 설명 한 줄로 읽힌다(R-716).
struct GuideIllustration: View {
    let card: GuideCard

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            switch card {
            case .notch:
                Self.notch(
                    timer: .running(
                        title: Self.taskA, quantumMin: 25, startedAt: Self.startedAt,
                        endsAt: Self.startedAt.addingTimeInterval(25 * 60)), remaining: 1122, expanded: false)
                Self.notch(timer: .empty(draft: Draft(title: Self.taskA, chipMin: 25)), expanded: true)
            case .rank:
                Self.notch(
                    timer: .empty(draft: Draft(title: Self.taskA, chipMin: 25)), expanded: true,
                    reasonLine: ReasonText.line(ReasonLine(deadline: .left(3), impact: "보통", skipCount: 2)))
                VStack(spacing: 6) {
                    GuideTaskRow(title: Self.taskA, rank: 1, isNext: true)
                    GuideTaskRow(title: "가짜 할 일 B", rank: 2, isNext: false)
                }
            case .firstAction:
                Self.notch(
                    timer: .empty(draft: Draft(title: "가짜 할 일 C", chipMin: 25)), expanded: true,
                    gate: GateInput(phase: .asking, text: .constant("가짜 자료 열기")))
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(background, in: RoundedRectangle(cornerRadius: 8))
        .environment(\.isNotchIllustration, true)
        .allowsHitTesting(false)
        .focusable(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GuideText.accessibilityLabel(card))
        .accessibilityAddTraits(.isImage)
    }

    private static let taskA = "가짜 할 일 A"
    private static let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
    /// 400pt 창 안에 들게 줄인 노치 크기(research R4). 실제 화면 노치와 다르다.
    private static let metrics = NotchMetrics(holeWidth: 120, height: 32)

    private static func notch(
        timer: NotchTimer, remaining: Int? = nil, expanded: Bool, reasonLine: String? = nil, gate: GateInput? = nil
    ) -> NotchContentView {
        NotchContentView(
            timer: timer, remainingSeconds: remaining, isExpanded: expanded, metrics: metrics, reasonLine: reasonLine,
            gate: gate, titleFocusRequest: 0,
            chip: QuantumChipInput(
                customText: nil, canStart: true, onChoose: { _ in }, onBeginCustom: {}, onEditCustom: { _ in },
                takeFocusRequest: { false }),
            onEnterTitle: { _ in }, onStart: {}, onComplete: {})
    }

    /// 시안 `.pic` 바탕(바탕 화면 느낌의 기울어진 그러데이션).
    private var background: LinearGradient {
        let stops: [Color] =
            colorScheme == .dark
            ? [Color(hex: 0x1D2236), Color(hex: 0x2A2030), Color(hex: 0x3A2A22)]
            : [Color(hex: 0xD6DCEF), Color(hex: 0xECDFE8), Color(hex: 0xF6E9DB)]
        return LinearGradient(
            stops: [
                .init(color: stops[0], location: 0), .init(color: stops[1], location: 0.55),
                .init(color: stops[2], location: 1),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// 순위 장의 할 일 탭 줄(시안 `.mini`). 순위 배지는 할 일 탭과 같은 `RankBadge`다.
private struct GuideTaskRow: View {
    let title: String
    let rank: Int
    let isNext: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            RankBadge(text: TaskRowText.rankBadge(rank: rank, isNext: isNext), isNext: isNext)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(width: 300)
        .background(colorScheme == .dark ? Color(hex: 0x221E1B) : .white, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    colorScheme == .dark ? Color(hex: 0xFFF0E1, opacity: 0.14) : Color(hex: 0x3C2314, opacity: 0.2),
                    lineWidth: 0.5)
        }
    }
}
