import Foundation
import MokaCore
import OSLog
import XCTest
import os

/// HTTP 판단 공급자의 연결부(#125, ADR-0013). 실제 전송은 세 겹으로 막는다: 세션은 가짜 URLProtocol을 강제하는
/// `FakeDecisionURLProtocol.makeSession()`으로만 만들고, 가짜는 `.invalid`가 아닌 호스트를 받지 않는다.
final class HTTPDecisionProviderTests: XCTestCase {
    private static let key = "fake-key-0123456789"
    private static let url = URL(string: "https://example-resource.invalid/v1/systemone")!
    private static let redirectTarget = URL(string: "https://example-other.invalid/v1/systemone")!

    override func setUp() {
        FakeDecisionURLProtocol.reset(status: 500, headers: [:])
    }

    private func provider(_ id: ProviderID) throws -> HTTPDecisionProvider {
        HTTPDecisionProvider(
            config: try XCTUnwrap(ProviderCatalog.config(id)), url: Self.url,
            session: FakeDecisionURLProtocol.makeSession())
    }

    private func decide(_ id: ProviderID) async throws -> DecisionError? {
        let questions = try QuestionSet.bundled()
        let request = DecisionRequest(taskID: 1, model: "fake-model", state: [], questions: questions)
        let provider = try provider(id)
        do {
            _ = try await provider.decide(request, key: Self.key)
            return nil
        } catch {
            return error
        }
    }

    func test_ADR0013_testSessionOnlyLoadsThroughFake() throws {
        let session = FakeDecisionURLProtocol.makeSession()
        let classes = try XCTUnwrap(session.configuration.protocolClasses)
        XCTAssertEqual(classes.count, 1)
        XCTAssertTrue(classes.first == FakeDecisionURLProtocol.self)
        XCTAssertTrue(Self.url.host?.hasSuffix(".invalid") == true)
        XCTAssertTrue(Self.redirectTarget.host?.hasSuffix(".invalid") == true)
    }

    func test_ADR0011_R606_bearerProviderSendsKeyOnlyInAuthorization() async throws {
        let error = try await decide(.typesafe)
        XCTAssertEqual(error, .server(status: 500))
        let sent = try XCTUnwrap(FakeDecisionURLProtocol.requests.first)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer \(Self.key)")
        XCTAssertNil(sent.value(forHTTPHeaderField: "api-key"))
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url, Self.url)
    }

    func test_ADR0011_R606_apiKeyHeaderProviderSendsKeyOnlyInApiKey() async throws {
        let error = try await decide(.microsoft)
        XCTAssertEqual(error, .server(status: 500))
        let sent = try XCTUnwrap(FakeDecisionURLProtocol.requests.first)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "api-key"), Self.key)
        XCTAssertNil(sent.value(forHTTPHeaderField: "Authorization"))
    }

    func test_ADR0011_R618_redirectIsNotFollowed() async throws {
        for status in [301, 302, 307, 308] {
            FakeDecisionURLProtocol.reset(status: status, headers: ["Location": Self.redirectTarget.absoluteString])
            let error = try await decide(.typesafe)
            XCTAssertEqual(error, .server(status: status), "\(status)")
            XCTAssertEqual(FakeDecisionURLProtocol.requests.map(\.url), [Self.url], "\(status): 두 번째 요청이 없다")
        }
    }

    func test_ADR0011_failureLogHasNoAddressOrKey() async throws {
        let start = Date().addingTimeInterval(-1)
        _ = try await decide(.typesafe)

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let messages = try store.getEntries(
            at: store.position(date: start),
            matching: NSPredicate(format: "subsystem == %@ AND category == %@", "dev.dongwon.moka", "decision")
        ).map(\.composedMessage)
        XCTAssertFalse(messages.isEmpty, "실패 로그를 찾지 못하면 검사가 빈 통과가 된다")
        for message in messages {
            for secret in [Self.key, Self.url.absoluteString, "example-resource.invalid", "/v1/systemone"] {
                XCTAssertFalse(message.contains(secret), "로그에 \(secret)이 있다: \(message)")
            }
        }
    }
}

/// 받은 요청을 기록하고 정해 둔 상태 코드로 답한다. 3xx면 `Location`으로 리디렉트를 알린 뒤 그 응답으로 끝낸다.
final class FakeDecisionURLProtocol: URLProtocol {
    private struct Stub: Sendable {
        var status: Int
        var headers: [String: String]
        var requests: [URLRequest]
    }

    private static let stub = OSAllocatedUnfairLock(initialState: Stub(status: 500, headers: [:], requests: []))

    static var requests: [URLRequest] { stub.withLock(\.requests) }

    /// 시험 세션은 이것으로만 만든다. 이 가짜 말고 다른 프로토콜(실제 HTTP)로는 나가지 않는다.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeDecisionURLProtocol.self]
        return HTTPDecisionProvider.makeSession(configuration)
    }

    static func reset(status: Int, headers: [String: String]) {
        stub.withLock { $0 = Stub(status: status, headers: headers, requests: []) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        let current = Self.stub.withLock { stub in
            stub.requests.append(request)
            return stub
        }
        guard let url = request.url, url.host?.hasSuffix(".invalid") == true else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        guard
            let response = HTTPURLResponse(
                url: url, statusCode: current.status, httpVersion: "HTTP/1.1", headerFields: current.headers)
        else { return }
        if (300..<400).contains(current.status), let location = current.headers["Location"].flatMap(URL.init) {
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: location), redirectResponse: response)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
