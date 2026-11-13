import MokaCore

/// 도움말 목차 항목(spec 007 R-703). 선언 순서가 목차 순서다.
enum HelpTopic: CaseIterable, Hashable, Sendable {
    case notch, tasksAndContexts, rankAndNext, reasonLine, firstAction, decisionModel, destination, shortcuts
}

enum HelpBody: Equatable {
    case text(String)
    case shortcuts([ShortcutRow])
}

struct ShortcutRow: Equatable {
    let action: String
    let place: String
    let effect: String
}

/// 도움말 글(확정 시안 1~9번). 따옴표 안 글자는 손으로 적지 않고 화면이 쓰는 상수에서 가져온다(R-705, data-model §3).
enum HelpContent {
    static func title(_ topic: HelpTopic) -> String {
        switch topic {
        case .notch: "노치"
        case .tasksAndContexts: "할 일과 일정"
        case .rankAndNext: "순위와 \(q(next))"
        case .reasonLine: "이유 줄"
        case .firstAction: "첫 행동 칸"
        case .decisionModel: "판단 모델과 키"
        case .destination: "보내는 곳"
        case .shortcuts: "단축 동작"
        }
    }

    static func summary(_ topic: HelpTopic) -> String {
        switch topic {
        case .notch: "접힘, 펼침, 시간 끝"
        case .tasksAndContexts: "더하기, 고치기, 보기와 정렬"
        case .rankAndNext: "노치에 무엇이 뜨는지"
        case .reasonLine: reasonExample
        case .firstAction: "막연한 할 일에 한 줄 적기"
        case .decisionModel: "공급자 고르기, 키 넣기, 키가 맞지 않을 때"
        case .destination: "무엇이 어디로 가는지"
        case .shortcuts: "Enter, esc, 우클릭, 메뉴"
        }
    }

    static func body(_ topic: HelpTopic) -> HelpBody {
        switch topic {
        case .notch:
            .text(
                "마우스를 노치에 올리면 펼쳐지고, 펼친 판을 한 번 누르면 글자를 적을 수 있어요. "
                    + "\(q(NotchText.titlePlaceholder)) 칸에 할 일을 적고 Enter를 누른 뒤, 시간을 골라 \(q(NotchText.start))을 눌러 주세요. "
                    + "타이머가 도는 동안 접힌 노치에 제목과 남은 시간이 보여요. "
                    + "시간이 끝나면 노치가 펼친 채로 기다리니, \(q(NotchText.complete))를 누르거나 시간을 골라 이어 가거나 "
                    + "\(q(NotchText.skip))·\(q(NotchText.switchTask))를 눌러 주세요. "
                    + "노치가 없는 화면에서는 메뉴 막대 아래 가운데에 같은 판이 떠요.")
        case .tasksAndContexts:
            .text(
                "할 일은 노치에서 바로 적거나 설정의 \(q(SettingsTab.tasks.title)) 탭에서 +로 더하고, 두 번 클릭하면 고쳐요. "
                    + "\(q(TaskListText.scopeAll)), \(q(TaskListText.scopeToday)), \(q(TaskListText.scopeThisWeek))로 보기를 바꾸고 "
                    + "\(q(TaskListText.orderCreated)), \(q(TaskListText.orderDeadline))으로 정렬해요. "
                    + "일정은 시험이나 제출처럼 할 일 순서에 영향을 주는 날이에요. "
                    + "\(q(SettingsTab.contexts.title)) 탭에서 이름, 날짜, 중요도(\(contextImpacts))를 넣어요.")
        case .rankAndNext:
            .text(
                "\(q(SettingsTab.tasks.title)) 탭에서 먼저 할 세 할 일에 \(q(rank(1))), \(q(rank(2))), \(q(rank(3)))가 붙어요. "
                    + "\(q(next)) 표시가 붙은 할 일이 노치에 떠요. "
                    + "키가 있으면 판단 모델이 정한 순서이고, 키가 없으면 마감이 가까운 순이에요. "
                    + "\(q(NotchText.skip))나 \(q(NotchText.switchTask))를 누르면 그다음 순위의 할 일이 떠요.")
        case .reasonLine:
            .text(
                "노치를 펼치면 제목 아래에 이 할 일이 왜 떴는지 한 줄로 보여요. "
                    + "예를 들어 \(q(reasonExample))은 마감까지 사흘 남았고, 판단 모델이 본 중요도가 보통이고, 두 번 미뤘다는 뜻이에요. "
                    + "\(q(ReasonText.deadline(.today)))는 오늘 마감, \(q(ReasonText.deadline(.overdue(2))))는 마감이 이틀 지났다는 뜻이에요. "
                    + "판단 결과가 아직 없으면 중요도 칸은 빠져요. "
                    + "이 중요도는 판단 모델이 매긴 값이라 일정의 중요도(\(contextImpacts))와는 달라요.")
        case .firstAction:
            .text(
                "어디서 시작할지 막연해 보이는 할 일이 시작 전으로 뜨면 노치가 \(q(GateDisplay.title))라고 물어요. "
                    + "지금 바로 손댈 첫 행동을 한 줄 적고 \(q(GateDisplay.submit))를 누르면 판단 모델이 다시 확인해요. "
                    + "통과하면 제목 아래 \(q(NotchText.firstActionLabel))로 보여요. "
                    + "세 번까지 묻고, 그 뒤에는 묻지 않아요. "
                    + "바로 시작하고 싶으면 \(q(GateDisplay.skip))를 누르거나 \(q(NotchText.start))을 눌러 주세요.")
        case .decisionModel:
            .text(
                "판단 모델은 할 일과 일정을 보고 무엇부터 할지 순서를 정해요. "
                    + "설정의 \(q(SettingsTab.basic.title)) 탭 판단 모델 칸에서 공급자를 고르고 키를 붙여 넣어 주세요. "
                    + "키는 이 Mac의 키체인에만 저장되고 다시 보이지 않아요. "
                    + "키가 없으면 마감이 가까운 순으로 떠요. "
                    + "\(q(GateDisplay.keyNoticeText))가 보이면 \(q(GateDisplay.keyNoticeButton))을 눌러 키를 지우고 다시 저장해 주세요.")
        case .destination:
            .text(
                "키를 넣으면 할 일 제목, 마감, 예상 시간, 이어서 할 일, 일정, 마지막으로 적은 두 줄이 판단 모델 서버로 가요. "
                    + "다른 할 일과 미룬 횟수는 보내지 않아요. "
                    + "어느 서버로 가는지는 \(q(SettingsTab.basic.title)) 탭의 \(q(destinationLabel))에서 볼 수 있어요. "
                    + "보내고 싶지 않으면 키를 지워 주세요.")
        case .shortcuts:
            .shortcuts(shortcutRows)
        }
    }

    static let quotes = Set(
        [
            NotchText.titlePlaceholder, NotchText.start, NotchText.complete, NotchText.skip, NotchText.switchTask,
            NotchText.firstActionLabel, NotchText.newTask, NotchText.otherTask, NotchText.settingsMenu,
            NotchText.quit, NotchText.register, NotchText.back, GateDisplay.submit, GateDisplay.skip,
            GateDisplay.title, GateDisplay.keyNoticeText, GateDisplay.keyNoticeButton, TaskListText.scopeAll,
            TaskListText.scopeToday, TaskListText.scopeThisWeek, TaskListText.orderCreated,
            TaskListText.orderDeadline, SettingsTab.basic.title, SettingsTab.tasks.title, SettingsTab.contexts.title,
            SheetText.save, SheetText.cancel, rank(1), rank(2), rank(3), next, reasonExample,
            ReasonText.deadline(.today), ReasonText.deadline(.overdue(2)), destinationLabel,
        ] + ContextImpact.allCases.map(ContextText.impact))

    private static let shortcutRows: [ShortcutRow] = [
        ShortcutRow(action: "마우스 올리기", place: "노치", effect: "노치를 펼쳐요"),
        ShortcutRow(action: "한 번 누르기", place: "펼친 노치", effect: "글자를 적을 수 있게 돼요"),
        ShortcutRow(
            action: "우클릭", place: "펼친 노치", effect: "\(q(NotchText.settingsMenu))과 \(q(NotchText.quit))가 있는 메뉴를 열어요"),
        ShortcutRow(action: "Enter", place: "노치 제목 칸", effect: "적은 제목으로 시간 고르기로 가요"),
        ShortcutRow(
            action: "Enter", place: "시작 전 노치",
            effect: "고른 시간으로 \(q(NotchText.start))해요. 제목 칸이나 첫 행동 칸이 열려 있으면 그 칸의 Enter예요"),
        ShortcutRow(action: "Enter", place: "첫 행동 칸", effect: "\(q(GateDisplay.submit))예요"),
        ShortcutRow(
            action: "Enter", place: "시간 끝 노치", effect: "\(q(NotchText.complete))예요. 직접 적는 분 칸이 열려 있으면 이어 가기예요"),
        ShortcutRow(
            action: "Enter", place: "미루기·바꾸기 두 줄 칸",
            effect: "첫 칸에서는 둘째 칸으로, 둘째 칸에서는 \(q(NotchText.register))이에요"),
        ShortcutRow(action: "Enter", place: "시간 끝 두 줄 칸", effect: "첫 칸에서는 둘째 칸으로 가요"),
        ShortcutRow(action: "esc", place: "\(q(NotchText.newTask)) 제목 칸", effect: "제목 칸을 닫아요"),
        ShortcutRow(
            action: "esc", place: "\(q(NotchText.otherTask)) 고르기, 미루기·바꾸기 두 줄 칸", effect: "\(q(NotchText.back))예요"),
        ShortcutRow(action: "⌘,", place: "메뉴 막대 Moka 메뉴", effect: "설정 창을 열어요"),
        ShortcutRow(action: "⌘Q", place: "메뉴 막대 Moka 메뉴", effect: "앱을 끝내요"),
        ShortcutRow(
            action: "Enter, esc", place: "할 일·일정 고치기", effect: "\(q(SheetText.save)), \(q(SheetText.cancel))예요"),
    ]

    private static let next = TaskRowText.rankBadge(rank: nil, isNext: true) ?? ""
    private static let reasonExample = ReasonText.line(ReasonLine(deadline: .left(3), impact: "보통", skipCount: 2))
    private static let destinationLabel = String(DecisionFieldText.destinationPrefix.dropLast(2))
    private static var contextImpacts: String {
        ContextImpact.allCases.map { q(ContextText.impact($0)) }.joined(separator: ", ")
    }

    private static func rank(_ rank: Int) -> String {
        TaskRowText.rankBadge(rank: rank, isNext: false) ?? ""
    }

    private static func q(_ text: String) -> String { "\"\(text)\"" }
}

/// 도움말 탭 맨 위 줄과 항목 줄 VoiceOver 값(R-702, R-716).
enum HelpText {
    static let guideMessage = "노치, 순위, 첫 행동 칸 안내를 한 장씩 다시 볼 수 있어요."
    static let guideButton = "안내 다시 보기"
    static let expandedValue = "펼침"
    static let collapsedValue = "접힘"

    static func value(expanded: Bool) -> String { expanded ? expandedValue : collapsedValue }
}
