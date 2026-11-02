import Foundation
import MokaCore
import Testing

@Test(
    "FR-01 R-101: 저장 시각은 UTC YYYY-MM-DDTHH:MM:SSZ",
    arguments: [
        (0.0, "1970-01-01T00:00:00Z"),
        (1_793_000_000.0, "2026-10-26T07:33:20Z"),
        (1_951_747_199.0, "2031-11-06T15:59:59Z"),
        (-1.0, "1969-12-31T23:59:59Z"),
        (951_782_400.0, "2000-02-29T00:00:00Z"),
        (4_107_542_399.0, "2100-02-28T23:59:59Z"),
        (4_107_542_400.0, "2100-03-01T00:00:00Z"),
    ])
func utcTimestampFormats(seconds: Double, expected: String) {
    #expect(UTCTimestamp.format(Date(timeIntervalSince1970: seconds)) == expected)
}

@Test("FR-01 R-101: 초 아래는 버린다(반올림하지 않음)", arguments: [0.001, 0.5, 0.999])
func utcTimestampTruncatesSubSeconds(fraction: Double) {
    let date = Date(timeIntervalSince1970: 1_793_000_000 + fraction)
    #expect(UTCTimestamp.format(date) == "2026-10-26T07:33:20Z")
    #expect(UTCTimestamp.floorToSecond(date) == Date(timeIntervalSince1970: 1_793_000_000))
}

@Test("FR-01 R-101: 초 아래가 있는 음수 시각도 아래로 내린다")
func utcTimestampFloorsNegative() {
    let date = Date(timeIntervalSince1970: -0.25)
    #expect(UTCTimestamp.floorToSecond(date) == Date(timeIntervalSince1970: -1))
    #expect(UTCTimestamp.format(date) == "1969-12-31T23:59:59Z")
}

@Test(
    "FR-01 R-101: parse는 format의 역이다(윤년·월말 포함)",
    arguments: [
        "1970-01-01T00:00:00Z", "2026-10-26T07:33:20Z", "2028-02-29T23:59:59Z", "2000-02-29T12:00:00Z",
        "2026-01-31T00:00:00Z", "2026-04-30T23:59:59Z", "2026-12-31T23:59:59Z", "0001-01-01T00:00:00Z",
        "9999-12-31T23:59:59Z",
    ])
func utcTimestampParseRoundTrips(text: String) throws {
    let date = try #require(UTCTimestamp.parse(text))
    #expect(UTCTimestamp.format(date) == text)
    #expect(UTCTimestamp.floorToSecond(date) == date)
}

@Test(
    "FR-01 R-101: 형식 밖의 시각 문자열은 nil",
    arguments: [
        "", "2026-10-26T07:33:20", "2026-10-26T07:33:20+09:00", "2026-10-26T07:33:20.5Z", "2026-10-26 07:33:20Z",
        "2026-10-26T07:33Z", "2026-02-29T00:00:00Z", "1900-02-29T00:00:00Z", "2026-04-31T00:00:00Z",
        "2026-13-01T00:00:00Z", "2026-10-26T24:00:00Z", "2026-10-26T23:60:00Z", "2026-10-26T23:59:60Z",
        "2026-10-26t07:33:20z", "2026-10-26T07:33:20Z ", " 2026-10-26T07:33:20Z", "0000-01-01T00:00:00Z",
    ])
func utcTimestampRejectsOtherFormats(text: String) {
    #expect(UTCTimestamp.parse(text) == nil)
}

@Test("FR-01 R-101: floorToSecond 값을 format → parse 하면 같은 Date")
func utcTimestampFloorRoundTrip() throws {
    for seconds in stride(from: 1_700_000_000.0, to: 1_700_000_000.0 + 86_400 * 400, by: 86_400 * 3 + 3_671.37) {
        let floored = UTCTimestamp.floorToSecond(Date(timeIntervalSince1970: seconds))
        #expect(try #require(UTCTimestamp.parse(UTCTimestamp.format(floored))) == floored)
    }
}
