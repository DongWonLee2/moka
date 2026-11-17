import Foundation
import MokaCore
import os

/// HTTP 판단 공급자(spec 006 contracts/decision-provider-v2.md). 공급자 표의 줄 하나와 보낼 주소로 만든다.
/// 앱 타깃과 macOS 앱 시험 번들만 컴파일한다(ADR-0013). 세션은 만드는 쪽이 넘긴다: 앱은 `liveSession`,
/// 시험은 가짜 URLProtocol만 쓰는 세션이다. 받은 키는 인증 헤더에만 넣는다. 상태 코드와 본문은
/// `DecisionWire.decode`가 해석하고, 시간 초과와 연결 실패만 여기서 `timeout`·`network`로 바꾼다. 세션의 자원 시간 한도가
/// `Defaults.decisionTimeout`이라 어떤 경우에도 그 안에 답 또는 오류로 돌아온다(단일 실행기가 멈추지 않게).
/// 리디렉트는 따라가지 않는다(research R7). 따라가지 않은 3xx는 그대로 `server(status)`가 된다.
struct HTTPDecisionProvider: DecisionProvider {
    let config: ProviderConfig
    let url: URL
    let session: URLSession

    var name: String { config.id.rawValue }

    /// 앱이 실제 판단 API로 보낼 때 쓰는 세션.
    static let liveSession = makeSession(.ephemeral)

    /// 시간 한도와 리디렉트 거부 대리자를 붙인 세션.
    static func makeSession(_ configuration: URLSessionConfiguration) -> URLSession {
        configuration.timeoutIntervalForRequest = Defaults.decisionTimeout
        configuration.timeoutIntervalForResource = Defaults.decisionTimeout
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: RedirectRefusal(), delegateQueue: nil)
    }
    private static let logger = Logger(subsystem: "dev.dongwon.moka", category: "decision")

    func decide(_ request: DecisionRequest, key: String) async throws(DecisionError) -> DecisionResponse {
        guard !key.isEmpty else { throw .missingKey }
        var http = URLRequest(url: url, timeoutInterval: Defaults.decisionTimeout)
        http.httpMethod = "POST"
        switch config.auth {
        case .bearer: http.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .apiKeyHeader: http.setValue(key, forHTTPHeaderField: "api-key")
        }
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.httpBody = DecisionWire.body(request, shape: config.shape)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: http)
        } catch let error as URLError where error.code == .timedOut {
            throw Self.failed(.timeout)
        } catch {
            throw Self.failed(.network)
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw Self.failed(.network) }
        do {
            return try DecisionWire.decode(status: status, body: data, shape: config.shape)
        } catch {
            throw Self.failed(error, status: status)
        }
    }

    /// 공급자 안쪽의 유일한 로그 자리. 실패 종류와 상태 코드만 남기고 주소·호스트·배포 이름·키·본문은 남기지 않는다.
    private static func failed(_ error: DecisionError, status: Int? = nil) -> DecisionError {
        if let status {
            logger.error("판단 요청 실패: \(String(describing: error), privacy: .public) 상태 \(status, privacy: .public)")
        } else {
            logger.error("판단 요청 실패: \(String(describing: error), privacy: .public)")
        }
        return error
    }
}

/// 리디렉트를 거부하는 세션 대리자. 판단은 MokaCore `RedirectRule`이 하고 여기서는 그 값을 그대로 돌려준다.
/// 저장 상태가 없다.
private final class RedirectRefusal: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let target = RedirectRule.follow(status: response.statusCode, to: request.url) else { return nil }
        var next = request
        next.url = target
        return next
    }
}
