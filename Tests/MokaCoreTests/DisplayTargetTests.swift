import MokaCore
import Testing

private let builtIn = ScreenInfo(id: 1, hasNotch: true, isMain: false)
private let external = ScreenInfo(id: 2, hasNotch: false, isMain: true)

@Test("FR-06 R-011: 노치 화면과 외부 모니터가 있으면 노치 화면에 노치로 표시")
func notchScreenWins() {
    #expect(chooseDisplayTarget([external, builtIn]) == .notch(1))
}

@Test("FR-06 R-011: 외부 모니터만 있으면 주 화면에 떠 있는 창")
func externalOnlyFloatsOnMain() {
    let other = ScreenInfo(id: 3, hasNotch: false, isMain: false)
    #expect(chooseDisplayTarget([other, external]) == .floating(2))
}

@Test("FR-06 R-011: 주 화면 표시가 없으면 목록 첫 화면에 떠 있는 창")
func noMainFloatsOnFirst() {
    let a = ScreenInfo(id: 4, hasNotch: false, isMain: false)
    let b = ScreenInfo(id: 5, hasNotch: false, isMain: false)
    #expect(chooseDisplayTarget([a, b]) == .floating(4))
}

@Test("FR-06 R-011: 노치 화면이 둘이면 목록의 첫 노치 화면")
func firstNotchScreen() {
    let other = ScreenInfo(id: 6, hasNotch: true, isMain: true)
    #expect(chooseDisplayTarget([external, builtIn, other]) == .notch(1))
}

@Test("FR-06 R-011: 화면이 없으면 표시하지 않는다")
func noScreens() {
    #expect(chooseDisplayTarget([]) == nil)
}
