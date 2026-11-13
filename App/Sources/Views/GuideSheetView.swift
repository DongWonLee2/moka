import SwiftUI

/// 다시 보기 시트의 장 이동 규칙(spec R-713·R-714, data-model §6). 안내 장 셋만 1/3~3/3으로 보인다.
struct GuideSheetState {
    static let total = GuideCard.allCases.count

    private(set) var index: Int

    init(index: Int = 1) {
        self.index = index
    }

    var card: GuideCard { GuideCard.allCases[index - 1] }

    /// 셋째 장이면 닫으라는 참, 아니면 다음 장으로 가고 거짓.
    mutating func primary() -> Bool {
        guard index < Self.total else { return true }
        index += 1
        return false
    }

    mutating func back() {
        if index > 1 { index -= 1 }
    }

    func cancel() -> Bool { true }
}

/// 설정 창 위 시트로 안내 장 셋을 다시 보인다. 저장소·키 보관함·`AppState`를 받지 않아 쓰기가 0건이다(SC-705).
struct GuideSheetView: View {
    let onClose: () -> Void

    @State private var state: GuideSheetState

    init(initialIndex: Int = 1, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _state = State(initialValue: GuideSheetState(index: initialIndex))
    }

    var body: some View {
        GuideCardView(
            card: state.card, index: state.index, total: GuideSheetState.total, presentation: .sheet,
            onBack: { state.back() }, onSkip: {},
            onPrimary: { if state.primary() { onClose() } }
        )
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(width: 400, alignment: .leading)
        .background {
            Button("") { if state.cancel() { onClose() } }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}
