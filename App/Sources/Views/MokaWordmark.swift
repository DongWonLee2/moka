import SwiftUI

/// "MOKA" 워드마크. 로고 자리(노치 왼쪽 귀, 설정 창 머리 줄)에 쓴다. 문장·메뉴의 앱 이름은 "Moka" 그대로다.
/// 자간은 글자 크기에 비례한다(노치 귀 10pt에서 1.25).
struct MokaWordmark: View {
    var size: CGFloat = ExpandedView.wordmarkSize

    var body: some View {
        Text("MOKA")
            .font(.system(size: size, weight: .bold))
            .tracking(size * 0.125)
            .accessibilityLabel("Moka")
    }
}
