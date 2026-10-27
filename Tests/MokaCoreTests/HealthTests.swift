import MokaCore
import Testing

@Test("health: MokaCore가 링크되고 응답한다")
func coreHealth() {
    #expect(Health.check() == "ok")
}
