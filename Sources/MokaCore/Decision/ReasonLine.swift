import Foundation

/// 마감과 오늘(spec 002 R-114 하루 경계)의 날 수 차이(spec 004 R-302).
public enum DeadlineDistance: Equatable, Sendable {
    case none
    case today
    case left(Int)
    case overdue(Int)
}

/// 노치 할 일이 왜 떴는지 보이는 세 칸(spec 004 R-302~R-304, data-model §2).
public struct ReasonLine: Equatable, Sendable {
    public var deadline: DeadlineDistance
    /// 판단 결과 impact의 화면 말(낮음·보통·높음) 하나. 쓰는 판단 결과가 없거나 impact 옵션이 셋이 아니면 nil이고 칸을 그리지 않는다.
    public var impact: String?
    public var skipCount: Int

    public init(deadline: DeadlineDistance, impact: String?, skipCount: Int) {
        self.deadline = deadline
        self.impact = impact
        self.skipCount = skipCount
    }

    private static let impactWords = ["낮음", "보통", "높음"]

    /// `usable`은 `ScoreRules.usable`로 거른 사전, `today`는 고르기와 같은 날(`SessionScoring.today`).
    public static func make(
        task: MokaTask, usable: [TaskID: TaskScore], questions: QuestionSet, today: LocalDay, calendar: Calendar
    ) -> ReasonLine {
        ReasonLine(
            deadline: distance(to: task.deadline, from: today),
            impact: usable[task.id].flatMap { impactWord(impact: $0.impact, questions: questions) },
            skipCount: task.skipCount)
    }

    /// 시각 차가 아니라 날짜 차라서 일광절약시간 전환일에도 하루는 하루다.
    private static func distance(to deadline: LocalDay?, from today: LocalDay) -> DeadlineDistance {
        guard let deadline else { return .none }
        let days = dayNumber(deadline) - dayNumber(today)
        if days == 0 { return .today }
        return days > 0 ? .left(days) : .overdue(-days)
    }

    private static func dayNumber(_ day: LocalDay) -> Int {
        GregorianCivil.daysFromCivil(year: day.year, month: day.month, day: day.day)
    }

    /// 옵션 번호 `round(impact × (옵션 수 - 1))`, 0.5는 위로. 저장소 값이 0~1 밖이어도 끝 옵션에 머문다.
    private static func impactWord(impact: Double, questions: QuestionSet) -> String? {
        guard case .score(_, let criteria) = questions.questions["impact"], criteria.count == impactWords.count
        else { return nil }
        let index = Int((impact * Double(criteria.count - 1)).rounded(.toNearestOrAwayFromZero))
        return impactWords[min(max(index, 0), impactWords.count - 1)]
    }
}

/// 노치에 보일 이유 한 줄. 표기는 시안 확정 전 초안이다(research R6).
public enum ReasonText {
    public static func line(_ reason: ReasonLine) -> String {
        var parts = [deadline(reason.deadline)]
        if let impact = reason.impact {
            parts.append("중요도 \(impact)")
        }
        parts.append("미룬 \(reason.skipCount)번")
        return parts.joined(separator: " · ")
    }

    private static func deadline(_ distance: DeadlineDistance) -> String {
        switch distance {
        case .none: "마감 없음"
        case .today: "D-day"
        case .left(let days): "D-\(days)"
        case .overdue(let days): "D+\(days)"
        }
    }
}
