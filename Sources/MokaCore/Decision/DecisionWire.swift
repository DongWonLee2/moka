import Foundation

/// 공급자의 요청 모양(spec 006 contracts/decision-provider-v2.md).
public enum RequestShape: Equatable, Sendable {
    case systemOne
}

/// 요청 모양에 따라 코덱 하나를 부른다. 앱 공급자는 이것만 부른다.
public enum DecisionWire {
    public static func body(_ request: DecisionRequest, shape: RequestShape) -> Data {
        switch shape {
        case .systemOne: SystemOneCodec.body(request)
        }
    }

    public static func decode(status: Int, body: Data, shape: RequestShape) throws(DecisionError) -> DecisionResponse {
        switch shape {
        case .systemOne: try SystemOneCodec.decode(status: status, body: body)
        }
    }
}
