import Foundation

/// 공급자의 요청 모양(spec 006 contracts/decision-provider-v2.md).
public enum RequestShape: Equatable, Sendable {
    case systemOne
    case openAI
}

/// 요청 모양에 따라 코덱 하나를 부른다. 앱 공급자는 이것만 부른다.
public enum DecisionWire {
    public static func body(_ request: DecisionRequest, shape: RequestShape) -> Data {
        switch shape {
        case .systemOne: SystemOneCodec.body(request)
        case .openAI: OpenAIDecisionsCodec.body(request)
        }
    }

    public static func decode(status: Int, body: Data, shape: RequestShape) throws(DecisionError) -> DecisionResponse {
        switch shape {
        case .systemOne: try SystemOneCodec.decode(status: status, body: body)
        case .openAI: try OpenAIDecisionsCodec.decode(status: status, body: body)
        }
    }

    /// 200이 아닌 상태 코드의 오류 종류. 두 모양이 같은 표를 쓴다(spec 006 data-model §3).
    static func failure(status: Int) -> DecisionError {
        switch status {
        case 401, 403: .unauthorized
        case 429: .rateLimited
        case 529: .overloaded
        default: .server(status: status)
        }
    }
}
