import MokaCore
import XCTest

/// 도움말 탭 글(spec 007 R-702~R-705, R-708, R-709, R-716, data-model §2·§3). 기대 글자는 확정 시안 1~9번과 spec 표 그대로다.
final class HelpContentTests: XCTestCase {
    func test_R703_topicOrderAndSummaries() {
        XCTAssertEqual(
            HelpTopic.allCases,
            [.notch, .tasksAndContexts, .rankAndNext, .reasonLine, .firstAction, .decisionModel, .destination, .shortcuts])
        XCTAssertEqual(
            HelpTopic.allCases.map(HelpContent.title),
            ["노치", "할 일과 일정", "순위와 \"다음\"", "이유 줄", "첫 행동 칸", "판단 모델과 키", "보내는 곳", "단축 동작"])
        XCTAssertEqual(
            HelpTopic.allCases.map(HelpContent.summary),
            [
                "접힘, 펼침, 시간 끝", "더하기, 고치기, 보기와 정렬", "노치에 무엇이 뜨는지", "D-3 · 중요도 보통 · 미룬 2번",
                "막연한 할 일에 한 줄 적기", "공급자 고르기, 키 넣기, 키가 맞지 않을 때", "무엇이 어디로 가는지", "Enter, esc, 우클릭, 메뉴",
            ])
    }

    /// 손으로 친 인용이 들어오면 실패한다. 제목, 본문, 단축 동작 표의 모든 칸을 본다.
    func test_R705_quotesComeFromScreenConstants() {
        for text in Self.allTexts {
            for quote in Self.quotes(in: text) {
                XCTAssertTrue(HelpContent.quotes.contains(quote), "화면 상수에 없는 인용 \"\(quote)\": \(text)")
            }
        }
    }

    /// `quotes`가 data-model §3 출처 표의 상수·함수 결과와 같은 집합이다. 화면 상수를 바꾸면 기대 글자 시험이 함께 실패한다.
    func test_R705_quotesSetMatchesScreenSymbols() {
        let destination = DecisionFieldText.destinationPrefix
        XCTAssertTrue(destination.hasSuffix(": "))
        let symbols: Set<String> = [
            NotchText.titlePlaceholder, NotchText.start, NotchText.complete, NotchText.skip, NotchText.switchTask,
            NotchText.firstActionLabel, GateDisplay.submit, GateDisplay.skip, GateDisplay.title,
            GateDisplay.keyNoticeText, GateDisplay.keyNoticeButton, TaskListText.scopeAll, TaskListText.scopeToday,
            TaskListText.scopeThisWeek, TaskListText.orderCreated, TaskListText.orderDeadline, NotchText.newTask,
            NotchText.otherTask, SettingsTab.tasks.title, SettingsTab.contexts.title, SettingsTab.basic.title,
            ContextText.impact(.normal), ContextText.impact(.high), ContextText.impact(.critical),
            TaskRowText.rankBadge(rank: 1, isNext: false)!, TaskRowText.rankBadge(rank: 2, isNext: false)!,
            TaskRowText.rankBadge(rank: 3, isNext: false)!, TaskRowText.rankBadge(rank: nil, isNext: true)!,
            ReasonText.line(ReasonLine(deadline: .left(3), impact: "보통", skipCount: 2)),
            ReasonText.deadline(.today), ReasonText.deadline(.overdue(2)), String(destination.dropLast(2)),
            NotchText.settingsMenu, NotchText.quit, NotchText.register, NotchText.back, SheetText.save, SheetText.cancel,
        ]
        XCTAssertEqual(HelpContent.quotes, symbols)
        XCTAssertEqual(
            HelpContent.quotes,
            [
                "무엇을 할까요?", "시작", "완료", "미루기", "바꾸기", "이어서 할 일", "적기", "지금은 넘기기", "어디서 시작할지 막연해 보여요",
                "키가 맞지 않아 판단 모델에 묻지 못하고 있어요.", "키 확인", "전체", "오늘", "이번 주", "만든 순", "마감 순", "+ 새 할 일",
                "다른 할 일", "할 일", "일정", "기본", "조금", "꽤", "아주", "1순위", "2순위", "3순위", "다음",
                "D-3 · 중요도 보통 · 미룬 2번", "D-day", "D+2", "판단을 받으러 보내는 곳", "설정…", "종료", "등록", "돌아가기", "저장",
                "취소",
            ])
    }

    func test_R704_R717_bodiesMatchConfirmedMockup() {
        let expected: [HelpTopic: String] = [
            .notch:
                "마우스를 노치에 올리면 펼쳐지고, 펼친 판을 한 번 누르면 글자를 적을 수 있어요. \"무엇을 할까요?\" 칸에 할 일을 적고 Enter를 누른 뒤, 시간을 골라 \"시작\"을 눌러 주세요. 타이머가 도는 동안 접힌 노치에 제목과 남은 시간이 보여요. 시간이 끝나면 노치가 펼친 채로 기다리니, \"완료\"를 누르거나 시간을 골라 이어 가거나 \"미루기\"·\"바꾸기\"를 눌러 주세요. 노치가 없는 화면에서는 메뉴 막대 아래 가운데에 같은 판이 떠요.",
            .tasksAndContexts:
                "할 일은 노치에서 바로 적거나 설정의 \"할 일\" 탭에서 +로 더하고, 두 번 클릭하면 고쳐요. \"전체\", \"오늘\", \"이번 주\"로 보기를 바꾸고 \"만든 순\", \"마감 순\"으로 정렬해요. 일정은 시험이나 제출처럼 할 일 순서에 영향을 주는 날이에요. \"일정\" 탭에서 이름, 날짜, 중요도(\"조금\", \"꽤\", \"아주\")를 넣어요.",
            .rankAndNext:
                "\"할 일\" 탭에서 먼저 할 세 할 일에 \"1순위\", \"2순위\", \"3순위\"가 붙어요. \"다음\" 표시가 붙은 할 일이 노치에 떠요. 키가 있으면 판단 모델이 정한 순서이고, 키가 없으면 마감이 가까운 순이에요. \"미루기\"나 \"바꾸기\"를 누르면 그다음 순위의 할 일이 떠요.",
            .reasonLine:
                "노치를 펼치면 제목 아래에 이 할 일이 왜 떴는지 한 줄로 보여요. 예를 들어 \"D-3 · 중요도 보통 · 미룬 2번\"은 마감까지 사흘 남았고, 판단 모델이 본 중요도가 보통이고, 두 번 미뤘다는 뜻이에요. \"D-day\"는 오늘 마감, \"D+2\"는 마감이 이틀 지났다는 뜻이에요. 판단 결과가 아직 없으면 중요도 칸은 빠져요. 이 중요도는 판단 모델이 매긴 값이라 일정의 중요도(\"조금\", \"꽤\", \"아주\")와는 달라요.",
            .firstAction:
                "어디서 시작할지 막연해 보이는 할 일이 시작 전으로 뜨면 노치가 \"어디서 시작할지 막연해 보여요\"라고 물어요. 지금 바로 손댈 첫 행동을 한 줄 적고 \"적기\"를 누르면 판단 모델이 다시 확인해요. 통과하면 제목 아래 \"이어서 할 일\"로 보여요. 세 번까지 묻고, 그 뒤에는 묻지 않아요. 바로 시작하고 싶으면 \"지금은 넘기기\"를 누르거나 \"시작\"을 눌러 주세요.",
            .decisionModel:
                "판단 모델은 할 일과 일정을 보고 무엇부터 할지 순서를 정해요. 설정의 \"기본\" 탭 판단 모델 칸에서 공급자를 고르고 키를 붙여 넣어 주세요. 키는 이 Mac의 키체인에만 저장되고 다시 보이지 않아요. 키가 없으면 마감이 가까운 순으로 떠요. \"키가 맞지 않아 판단 모델에 묻지 못하고 있어요.\"가 보이면 \"키 확인\"을 눌러 키를 지우고 다시 저장해 주세요.",
            .destination:
                "키를 넣으면 할 일 제목, 마감, 예상 시간, 이어서 할 일, 일정, 마지막으로 적은 두 줄이 판단 모델 서버로 가요. 다른 할 일과 미룬 횟수는 보내지 않아요. 어느 서버로 가는지는 \"기본\" 탭의 \"판단을 받으러 보내는 곳\"에서 볼 수 있어요. 보내고 싶지 않으면 키를 지워 주세요.",
        ]
        for topic in HelpTopic.allCases where topic != .shortcuts {
            guard case .text(let text) = HelpContent.body(topic) else {
                XCTFail("\(topic): 글이 아니다")
                continue
            }
            XCTAssertEqual(text, expected[topic], "\(topic)")
        }
    }

    func test_R708_shortcutRows() {
        guard case .shortcuts(let rows) = HelpContent.body(.shortcuts) else {
            return XCTFail("단축 동작 항목이 표가 아니다")
        }
        let expected: [[String]] = [
            ["마우스 올리기", "노치", "노치를 펼쳐요"],
            ["한 번 누르기", "펼친 노치", "글자를 적을 수 있게 돼요"],
            ["우클릭", "펼친 노치", "\"설정…\"과 \"종료\"가 있는 메뉴를 열어요"],
            ["Enter", "노치 제목 칸", "적은 제목으로 시간 고르기로 가요"],
            ["Enter", "시작 전 노치", "고른 시간으로 \"시작\"해요. 제목 칸이나 첫 행동 칸이 열려 있으면 그 칸의 Enter예요"],
            ["Enter", "첫 행동 칸", "\"적기\"예요"],
            ["Enter", "시간 끝 노치", "\"완료\"예요. 직접 적는 분 칸이 열려 있으면 이어 가기예요"],
            ["Enter", "미루기·바꾸기 두 줄 칸", "첫 칸에서는 둘째 칸으로, 둘째 칸에서는 \"등록\"이에요"],
            ["Enter", "시간 끝 두 줄 칸", "첫 칸에서는 둘째 칸으로 가요"],
            ["esc", "\"+ 새 할 일\" 제목 칸", "제목 칸을 닫아요"],
            ["esc", "\"다른 할 일\" 고르기, 미루기·바꾸기 두 줄 칸", "\"돌아가기\"예요"],
            ["⌘,", "메뉴 막대 Moka 메뉴", "설정 창을 열어요"],
            ["⌘Q", "메뉴 막대 Moka 메뉴", "앱을 끝내요"],
            ["Enter, esc", "할 일·일정 고치기", "\"저장\", \"취소\"예요"],
        ]
        XCTAssertEqual(rows.map { [$0.action, $0.place, $0.effect] }, expected)
    }

    /// 해요체 문장 끝(`요.`)이 2~5개다. 따옴표 안 화면 글자의 `요.`는 문장 끝이 아니라 세지 않는다.
    func test_R704_sentenceCount() {
        for topic in HelpTopic.allCases {
            guard case .text(let text) = HelpContent.body(topic) else { continue }
            let count = Self.removingQuotes(text).components(separatedBy: "요.").count - 1
            XCTAssertTrue((2...5).contains(count), "\(topic): \(count)문장")
        }
    }

    func test_R702_guideRowTexts() {
        XCTAssertEqual(HelpText.guideMessage, "노치, 순위, 첫 행동 칸 안내를 한 장씩 다시 볼 수 있어요.")
        XCTAssertEqual(HelpText.guideButton, "안내 다시 보기")
    }

    func test_R709_noHostInHelp() {
        let banned = ["api.", "TypeSafe", "Jev"] + ProviderCatalog.all.map(\.displayName)
        for text in Self.allTexts {
            for word in banned {
                XCTAssertFalse(text.contains(word), "\(word): \(text)")
            }
        }
    }

    func test_R716_helpExpandedAccessibilityValue() {
        XCTAssertEqual(HelpText.value(expanded: true), "펼침")
        XCTAssertEqual(HelpText.value(expanded: false), "접힘")
    }

    private static var allTexts: [String] {
        HelpTopic.allCases.flatMap { topic -> [String] in
            let body: [String]
            switch HelpContent.body(topic) {
            case .text(let text): body = [text]
            case .shortcuts(let rows): body = rows.flatMap { [$0.action, $0.place, $0.effect] }
            }
            return [HelpContent.title(topic), HelpContent.summary(topic)] + body
        }
    }

    /// 큰따옴표 쌍 안의 글자. 쌍이 맞지 않으면 빈 문자열을 하나 더해 시험이 실패하게 한다.
    private static func quotes(in text: String) -> [String] {
        let parts = text.split(separator: "\"", omittingEmptySubsequences: false)
        guard parts.count % 2 == 1 else { return [""] }
        return stride(from: 1, to: parts.count, by: 2).map { String(parts[$0]) }
    }

    private static func removingQuotes(_ text: String) -> String {
        text.split(separator: "\"", omittingEmptySubsequences: false).enumerated()
            .filter { $0.offset % 2 == 0 }.map(\.element).joined()
    }
}
