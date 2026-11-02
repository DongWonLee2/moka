import Foundation
import MokaCore
import Testing

private let seoul = TimeZone(identifier: "Asia/Seoul")!
private let newYork = TimeZone(identifier: "America/New_York")!

private func utc(_ text: String) -> Date {
    UTCTimestamp.parse(text)!
}

private func day(_ text: String) -> LocalDay {
    LocalDay(text: text)!
}

private func dayStart(_ text: String) -> DayStart {
    DayStart(text: text)!
}

// MARK: - GregorianCalendar(data-model §2.2)

@Test("FR-09 R-114: GregorianCalendar.make는 받은 시간대의 그레고리력을 만든다", arguments: [seoul, newYork])
func makeBuildsGregorianWithZone(zone: TimeZone) {
    let calendar = GregorianCalendar.make(timeZone: zone)
    #expect(calendar.identifier == .gregorian)
    #expect(calendar.timeZone == zone)
}

// MARK: - 경계값(data-model §5.4)

@Test(
    "FR-09 R-114: 하루 시작 06:00이면 05:59:59는 어제, 06:00:00은 오늘",
    arguments: [
        // Asia/Seoul(+09:00, 일광절약시간 없음)
        (seoul, "2026-11-01T20:59:59Z", "2026-11-01"),
        (seoul, "2026-11-01T21:00:00Z", "2026-11-02"),
        (seoul, "2026-12-31T20:59:59Z", "2026-12-31"),
        (seoul, "2026-12-31T21:00:00Z", "2027-01-01"),
        // America/New_York 보통 날(-05:00)
        (newYork, "2026-01-15T10:59:59Z", "2026-01-14"),
        (newYork, "2026-01-15T11:00:00Z", "2026-01-15"),
        // 3월 전환일(2026-03-08 02:00 EST → 03:00 EDT). 06:00 EDT = 10:00Z
        (newYork, "2026-03-08T09:59:59Z", "2026-03-07"),
        (newYork, "2026-03-08T10:00:00Z", "2026-03-08"),
        // 11월 전환일(2026-11-01 02:00 EDT → 01:00 EST). 06:00 EST = 11:00Z
        (newYork, "2026-11-01T10:59:59Z", "2026-10-31"),
        (newYork, "2026-11-01T11:00:00Z", "2026-11-01"),
    ])
func dayBoundaryAtSixAM(zone: TimeZone, instant: String, expected: String) {
    let calendar = GregorianCalendar.make(timeZone: zone)
    #expect(DayBoundary.day(containing: utc(instant), dayStart: dayStart("06:00"), calendar: calendar).text == expected)
}

@Test(
    "FR-09 R-114: 하루의 시작 시각(start(of:))은 그 날짜의 하루 시작 시·분",
    arguments: [
        (seoul, "2026-11-02", "06:00", "2026-11-01T21:00:00Z"),
        (seoul, "2026-11-02", "00:00", "2026-11-01T15:00:00Z"),
        (seoul, "2026-11-02", "23:59", "2026-11-02T14:59:00Z"),
        (newYork, "2026-03-08", "06:00", "2026-03-08T10:00:00Z"),
        (newYork, "2026-03-08", "00:00", "2026-03-08T05:00:00Z"),
        (newYork, "2026-11-01", "06:00", "2026-11-01T11:00:00Z"),
        (newYork, "2026-11-01", "00:00", "2026-11-01T04:00:00Z"),
        // 전환 구간: 2026-03-08 02:30은 없다 → .nextTime으로 03:00 EDT
        (newYork, "2026-03-08", "02:30", "2026-03-08T07:00:00Z"),
        // 전환 구간: 2026-11-01 01:30은 두 번 있다 → .first로 앞의 01:30 EDT
        (newYork, "2026-11-01", "01:30", "2026-11-01T05:30:00Z"),
    ])
func dayBoundaryStartOfDay(zone: TimeZone, localDay: String, start: String, expected: String) {
    let calendar = GregorianCalendar.make(timeZone: zone)
    let date = DayBoundary.start(of: day(localDay), dayStart: dayStart(start), calendar: calendar)
    #expect(UTCTimestamp.format(date) == expected)
}

@Test(
    "FR-09 R-114: 하루 시작이 전환 구간(02:30·01:30)이어도 경계는 start(of:)",
    arguments: [
        // 3월: 02:30 없음 → 경계 03:00 EDT(07:00Z). 06:59:59Z = 01:59:59 EST
        ("02:30", "2026-03-08T06:59:59Z", "2026-03-07"),
        ("02:30", "2026-03-08T07:00:00Z", "2026-03-08"),
        ("02:30", "2026-03-09T06:29:59Z", "2026-03-08"),  // 다음 날 02:30 EDT = 06:30Z
        ("02:30", "2026-03-09T06:30:00Z", "2026-03-09"),
        // 11월: 01:30 두 번 → 앞의 01:30 EDT(05:30Z). 뒤의 01:30 EST(06:30Z)는 이미 오늘
        ("01:30", "2026-11-01T05:29:59Z", "2026-10-31"),
        ("01:30", "2026-11-01T05:30:00Z", "2026-11-01"),
        ("01:30", "2026-11-01T06:30:00Z", "2026-11-01"),
        ("01:30", "2026-11-02T06:29:59Z", "2026-11-01"),
        ("01:30", "2026-11-02T06:30:00Z", "2026-11-02"),
    ])
func dayBoundaryInTransitionGap(start: String, instant: String, expected: String) {
    let calendar = GregorianCalendar.make(timeZone: newYork)
    #expect(DayBoundary.day(containing: utc(instant), dayStart: dayStart(start), calendar: calendar).text == expected)
}

// MARK: - 왕복과 단조성

private let dayStarts = ["00:00", "01:30", "02:30", "06:00", "23:59"]

/// 전환일 앞뒤를 덮는 10분 간격 시각 묶음(3월·11월 두 묶음).
private func instantRuns() -> [[Date]] {
    let ranges = [("2026-03-05T00:00:00Z", "2026-03-12T00:00:00Z"), ("2026-10-29T00:00:00Z", "2026-11-05T00:00:00Z")]
    return ranges.map { from, to in
        stride(from: utc(from).timeIntervalSince1970, to: utc(to).timeIntervalSince1970, by: 600).map {
            Date(timeIntervalSince1970: $0)
        }
    }
}

@Test("FR-09 R-114: 같은 하루 시작·달력에서 시각이 늘면 하루는 줄지 않고 하루씩만 넘어간다", arguments: [seoul, newYork])
func dayBoundaryIsMonotonic(zone: TimeZone) {
    let calendar = GregorianCalendar.make(timeZone: zone)
    for text in dayStarts {
        let start = dayStart(text)
        for run in instantRuns() {
            var previous: LocalDay?
            var changes = 0
            for instant in run {
                let current = DayBoundary.day(containing: instant, dayStart: start, calendar: calendar)
                if let previous, previous != current {
                    changes += 1
                    #expect(
                        previous.adding(days: 1, calendar: calendar) == current,
                        "\(text) \(UTCTimestamp.format(instant)): \(previous.text) → \(current.text)")
                }
                previous = current
            }
            #expect(changes == 7, "\(text): 7일 묶음에서 하루가 \(changes)번 바뀜")
        }
    }
}

@Test("FR-09 R-114: start(of:)와 day(containing:)는 왕복한다", arguments: [seoul, newYork])
func dayBoundaryRoundTrip(zone: TimeZone) {
    let calendar = GregorianCalendar.make(timeZone: zone)
    for text in dayStarts {
        let start = dayStart(text)
        for instant in instantRuns().joined() {
            let current = DayBoundary.day(containing: instant, dayStart: start, calendar: calendar)
            let begin = DayBoundary.start(of: current, dayStart: start, calendar: calendar)
            let end = DayBoundary.start(
                of: current.adding(days: 1, calendar: calendar), dayStart: start, calendar: calendar)
            #expect(begin <= instant && instant < end, "\(text) \(UTCTimestamp.format(instant)) → \(current.text)")
            #expect(DayBoundary.day(containing: begin, dayStart: start, calendar: calendar) == current)
            #expect(
                DayBoundary.day(containing: begin.addingTimeInterval(-1), dayStart: start, calendar: calendar)
                    == current.adding(days: -1, calendar: calendar))
        }
    }
}

// MARK: - ADR-0010 결정 검증

/// 프로세스 시간대(`TZ` 환경 변수 + `NSTimeZone.resetSystemTimeZone()`)를 바꿔 시스템 시간대 변경을 흉내 낸다.
/// 끝나면 원래 값으로 되돌린다. MokaCore와 다른 시험은 시스템 시간대를 읽지 않는다.
@Suite(.serialized)
struct ADR0010DecisionTests {
    private static func withSystemTimeZone(_ identifier: String, _ body: () -> Void) {
        let saved = ProcessInfo.processInfo.environment["TZ"]
        setenv("TZ", identifier, 1)
        NSTimeZone.resetSystemTimeZone()
        defer {
            if let saved { setenv("TZ", saved, 1) } else { unsetenv("TZ") }
            NSTimeZone.resetSystemTimeZone()
        }
        body()
    }

    @Test("ADR-0010: 시스템 시간대가 바뀌면 (a) 한 번 만든 autoupdatingCurrent 달력과 (b) 판정마다 새로 만든 달력 모두 새 시간대를 따른다")
    func judgmentFollowsSystemTimeZoneChange() {
        // 2026-11-02T03:00:00Z = 서울 11-02 12:00, 뉴욕 11-01 22:00(EST)
        let instant = utc("2026-11-02T03:00:00Z")
        let start = dayStart("06:00")

        Self.withSystemTimeZone("Asia/Seoul") {
            let onceA = GregorianCalendar.make(timeZone: .autoupdatingCurrent)
            let snapshot = GregorianCalendar.make(timeZone: .current)
            #expect(DayBoundary.day(containing: instant, dayStart: start, calendar: onceA).text == "2026-11-02")
            #expect(DayBoundary.day(containing: instant, dayStart: start, calendar: snapshot).text == "2026-11-02")

            Self.withSystemTimeZone("America/New_York") {
                // (a) 바꾸기 전에 한 번 만들어 둔 같은 달력
                #expect(DayBoundary.day(containing: instant, dayStart: start, calendar: onceA).text == "2026-11-01")
                // (b) 판정 순간 TimeZone.current로 새로 만든 달력
                let fresh = GregorianCalendar.make(timeZone: .current)
                #expect(DayBoundary.day(containing: instant, dayStart: start, calendar: fresh).text == "2026-11-01")
                // 대조: 바꾸기 전 TimeZone.current 값으로 만들어 둔 달력은 옛 시간대에 머문다((b)를 판정마다 해야 하는 이유)
                #expect(DayBoundary.day(containing: instant, dayStart: start, calendar: snapshot).text == "2026-11-02")
            }
        }
    }

    @Test("ADR-0010: make는 늘 그레고리력이라 다른 달력 설정과 무관하게 LocalDay 텍스트가 같다", arguments: [seoul, newYork])
    func makeKeepsGregorianLocalDayText(zone: TimeZone) {
        // 2026-11-02T15:00:00Z = 서울 11-03 00:00, 뉴욕 11-02 10:00
        let instant = utc("2026-11-02T15:00:00Z")
        let start = dayStart("00:00")
        let made = GregorianCalendar.make(timeZone: zone)
        let expected = zone == seoul ? "2026-11-03" : "2026-11-02"
        #expect(made.identifier == .gregorian)
        #expect(DayBoundary.day(containing: instant, dayStart: start, calendar: made).text == expected)

        // 대조: 불교력·일본력을 그대로 주입하면 연도 숫자가 달라진다(make가 막는 일)
        for identifier in [Calendar.Identifier.buddhist, .japanese] {
            var other = Calendar(identifier: identifier)
            other.timeZone = zone
            #expect(DayBoundary.day(containing: instant, dayStart: start, calendar: other).text != expected)
        }
    }
}
