import SwiftUI

/// 안내 장 셋. 선언 순서가 장 순서다(spec 007 R-710).
enum GuideCard: CaseIterable, Sendable {
    case notch
    case rank
    case firstAction
}

/// 안내 장 글(확정 시안 10~12번, spec "안내 장" 표). 따옴표 안 글자는 화면 상수로 만든다(R-705).
enum GuideText {
    static let skip = "안내 건너뛰기"
    static let back = "이전"
    static let next = "다음"
    static let done = "다 봤어요"

    static func title(_ card: GuideCard) -> String {
        switch card {
        case .notch: "할 일은 노치에 떠요"
        case .rank: "무엇부터 할지 Moka가 골라요"
        case .firstAction: "막연한 일은 첫 행동부터 적어요"
        }
    }

    static func message(_ card: GuideCard) -> String {
        switch card {
        case .notch:
            "마우스를 노치에 올리면 펼쳐져요. 시간을 고르고 \"\(NotchText.start)\"을 누르면 접힌 노치에 남은 시간이 보여요."
        case .rank:
            "판단 모델이 마감과 일정을 보고 순서를 정해요. 키가 없으면 마감이 가까운 순으로 떠요. 펼친 노치의 제목 아래 줄에서 왜 떴는지 볼 수 있어요."
        case .firstAction:
            "어디서 시작할지 막연해 보이는 할 일이 뜨면 노치가 첫 행동 한 줄을 물어요. 적은 줄은 제목 아래 \"\(NotchText.firstActionLabel)\"로 보여요. 바로 시작하려면 \"\(GateDisplay.skip)\"를 눌러 주세요."
        }
    }

    /// 그림마다 VoiceOver 설명 한 줄(R-716).
    static func accessibilityLabel(_ card: GuideCard) -> String {
        switch card {
        case .notch: "접힌 노치에 할 일과 남은 시간이 보이고, 펼친 노치에서 시간을 고르고 시작하는 그림이에요"
        case .rank: "펼친 노치의 제목 아래 이유 줄과, 할 일 목록의 1순위·2순위 배지 그림이에요"
        case .firstAction: "펼친 노치가 첫 행동 한 줄을 묻는 칸과 넘기기·적기 버튼 그림이에요"
        }
    }
}

enum GuidePresentation {
    case onboarding
    case sheet
}

/// 안내 장 버튼 줄 규칙(spec R-712·R-713·R-714, data-model §4). `index`는 그 안내 장의 번호다.
struct GuideButtons: Equatable {
    let showsBack: Bool
    let showsSkip: Bool
    let primary: String

    static func make(index: Int, total: Int, presentation: GuidePresentation) -> GuideButtons {
        let isLastGuide = index == GuideCard.allCases.count
        return switch presentation {
        case .onboarding:
            GuideButtons(showsBack: index > 1, showsSkip: !isLastGuide, primary: GuideText.next)
        case .sheet:
            GuideButtons(
                showsBack: index > 1, showsSkip: false, primary: index == total ? GuideText.done : GuideText.next)
        }
    }
}

struct GuideCardView: View {
    let card: GuideCard
    let index: Int
    let total: Int
    let presentation: GuidePresentation
    let onBack: () -> Void
    let onSkip: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        let buttons = GuideButtons.make(index: index, total: total, presentation: presentation)
        VStack(alignment: .leading, spacing: 0) {
            StepBar(step: index, total: total)
            OnboardingHeading(title: GuideText.title(card), message: GuideText.message(card))
            GuideIllustration(card: card)
                .padding(.top, 4)
                .padding(.bottom, 2)
            HStack(spacing: 6) {
                if buttons.showsBack {
                    SheetButton(title: GuideText.back, kind: .normal, action: onBack)
                }
                if buttons.showsSkip {
                    Button(action: onSkip) {
                        Text(GuideText.skip)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                SheetButton(title: buttons.primary, kind: .primary, action: onPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 14)
        }
    }
}
