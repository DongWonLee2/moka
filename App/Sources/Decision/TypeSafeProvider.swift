import Foundation
import MokaCore
import os

/// TypeSafe 판단 공급자(contracts/decision-provider.md "HTTP"). 앱 타깃에만 있고 시험·CI는 링크하지 않는다(SC-207).
/// 받은 키는 `Authorization` 헤더에만 넣는다. 상태 코드와 본문은 `TypeSafeCodec.decode`가 해석하고, 시간 초과와
/// 연결 실패만 여기서 `timeout`·`network`로 바꾼다. 세션의 자원 시간 한도가 `Defaults.decisionTimeout`이라 어떤 경우에도
/// 그 안에 답 또는 오류로 돌아온다(단일 실행기가 멈추지 않게, data-model §6).
struct TypeSafeProvider: DecisionProvider {
    let name = "typesafe"

    private static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Defaults.decisionTimeout
        configuration.timeoutIntervalForResource = Defaults.decisionTimeout
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
    private static let logger = Logger(subsystem: "dev.dongwon.moka", category: "decision")

    func decide(_ request: DecisionRequest, key: String) async throws(DecisionError) -> DecisionResponse {
        guard !key.isEmpty else { throw .missingKey }
        var http = URLRequest(url: Self.endpoint, timeoutInterval: Defaults.decisionTimeout)
        http.httpMethod = "POST"
        http.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.httpBody = TypeSafeCodec.body(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: http)
        } catch let error as URLError where error.code == .timedOut {
            Self.logger.error("판단 요청 실패: timeout")
            throw .timeout
        } catch {
            Self.logger.error("판단 요청 실패: network")
            throw .network
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            Self.logger.error("판단 요청 실패: network")
            throw .network
        }
        do {
            return try TypeSafeCodec.decode(status: status, body: data)
        } catch {
            Self.logger.error(
                "판단 요청 실패: \(String(describing: error), privacy: .public) 상태 \(status, privacy: .public)")
            throw error
        }
    }
}
