import SwiftUI

/// 판 안 입력 칸 테두리(data-model §6 포커스 표). 포커스 색은 패널이 key이고 칸이 포커스일 때만 칠한다.
/// SwiftUI `@FocusState`는 창의 first responder를 따를 뿐 창이 key인지는 보지 않아서,
/// 마우스를 올려 펼치기만 한(key가 아닌) 패널에서도 참일 수 있다.
enum FieldBorder {
    enum Kind: Equatable {
        case normal
        case focus
        case error
    }

    static func kind(invalid: Bool, focused: Bool, panelIsKey: Bool) -> Kind {
        if invalid { return .error }
        return focused && panelIsKey ? .focus : .normal
    }
}

extension EnvironmentValues {
    /// 패널이 key window인지. 노치 패널 연결부가 넣고, 기본값은 key 아님.
    @Entry var panelIsKey = false
}
