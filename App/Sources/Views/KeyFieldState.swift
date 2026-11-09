/// 키 저장·지우기 가운데 실패한 동작.
enum KeyAction: Equatable, Sendable {
    case save
    case delete
}

/// 설정 창 기본 탭 키 칸 상태 여섯(spec 003 data-model §10, R-213). AppState가 정하고 뷰는 그대로 그린다(ADR-0009).
enum KeyFieldState: Equatable, Sendable {
    case noKey
    case saved
    case savedNoTasks
    /// 401·403을 받아 키를 다시 저장하거나 지울 때까지 묻지 않는다.
    case needsCheck
    /// 저장·지우기 실패. 다음 성공까지 그 상태(키가 있는지) 위에 다시 해 달라는 문구를 보인다.
    case actionFailed(KeyAction, hasKey: Bool)
    /// 할 일을 저장할 수 없다(spec 002 R-119). 키가 있을 때만 이 상태다.
    case storageUnavailable

    /// 앞 조건이 이긴다: 실패 문구, 키 없음, 키 확인 필요, 저장 불가, 할 일 없음.
    static func make(
        hasKey: Bool, hasTasks: Bool, needsCheck: Bool, failedAction: KeyAction?, storageUnavailable: Bool
    ) -> KeyFieldState {
        if let failedAction { return .actionFailed(failedAction, hasKey: hasKey) }
        guard hasKey else { return .noKey }
        if needsCheck { return .needsCheck }
        if storageUnavailable { return .storageUnavailable }
        return hasTasks ? .saved : .savedNoTasks
    }

    /// 붙여 넣은 값이 앞뒤 공백·줄바꿈을 빼고도 남으면 저장할 수 있다(`AppState.saveKey`와 같은 규칙).
    static func canSave(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 키 값 대신 "저장되어 있어요"를 보이는지. 아니면 붙여 넣는 칸과 "저장"을 보인다.
    var showsSavedRow: Bool {
        switch self {
        case .noKey: false
        case .actionFailed(_, let hasKey): hasKey
        case .saved, .savedNoTasks, .needsCheck, .storageUnavailable: true
        }
    }

    /// 칸 아래(키 없음이면 위) 문구. 확정 시안 v2 글자 그대로다.
    var notice: KeyFieldNotice? {
        switch self {
        case .noKey:
            KeyFieldNotice(text: "키를 넣으면 판단 모델이 할 일 순서를 정해요. 키가 없으면 마감이 가까운 순으로 떠요.", isWarning: false)
        case .saved: nil
        case .savedNoTasks: KeyFieldNotice(text: "할 일을 저장하면 키가 맞는지 확인돼요.", isWarning: false)
        case .needsCheck: KeyFieldNotice(text: "키가 맞지 않아요. 키를 지우고 다시 저장해 주세요.", isWarning: true)
        case .actionFailed(.save, _): KeyFieldNotice(text: "키를 저장하지 못했어요. 다시 해 주세요.", isWarning: true)
        case .actionFailed(.delete, _): KeyFieldNotice(text: "키를 지우지 못했어요. 다시 해 주세요.", isWarning: true)
        case .storageUnavailable: KeyFieldNotice(text: "할 일을 저장할 수 없는 동안에는 다시 물을 수 없어요.", isWarning: false)
        }
    }
}

/// 키 칸 문구 한 줄. `isWarning`이면 경고색이다.
struct KeyFieldNotice: Equatable, Sendable {
    let text: String
    let isWarning: Bool
}
