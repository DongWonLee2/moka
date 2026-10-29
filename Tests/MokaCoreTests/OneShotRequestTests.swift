import MokaCore
import Testing

@Test("FR-06 R-002 SC-003: 요청이 없으면 포커스를 주지 않는다")
func oneShotWithoutRequest() {
    var request = OneShotRequest()
    #expect(request.take() == false)
}

@Test("FR-06 R-002 SC-003: 직접 입력 포커스 요청은 한 번만 소비되고, 칸이 다시 나타날 때(재hover 펼침)는 주지 않는다")
func oneShotIsConsumedOnce() {
    var request = OneShotRequest()
    request.request()
    #expect(request.take())
    #expect(request.take() == false)
}

@Test("FR-06 R-002: 요청을 여러 번 해도 소비는 한 번이다")
func oneShotCoalescesRequests() {
    var request = OneShotRequest()
    request.request()
    request.request()
    #expect(request.take())
    #expect(request.take() == false)
}

@Test("FR-06 R-002: 취소한 요청은 소비되지 않는다")
func oneShotCancel() {
    var request = OneShotRequest()
    request.request()
    request.cancel()
    #expect(request.take() == false)
}
