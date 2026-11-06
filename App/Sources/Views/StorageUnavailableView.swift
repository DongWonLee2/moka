import SwiftUI

/// 앱 DB를 열지 못했을 때 노치 빈 상태의 안내(R-119). 메뉴 막대에는 항목을 더하지 않는다.
struct StorageUnavailableView: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.panelPalette) private var palette

    var body: some View {
        Text("할 일을 저장할 수 없어요. 지금은 타이머만 쓸 수 있어요.")
            .font(.system(size: 11))
            .foregroundStyle(contrast == .increased ? palette.mutedHighContrast : palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
