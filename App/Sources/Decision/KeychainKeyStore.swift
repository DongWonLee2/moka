import Foundation
import MokaCore
import Security

/// 로그인 키체인의 generic password 항목 하나(spec 003 research R10). service `dev.dongwon.moka`, account는 공급자 ID다.
/// Jev는 spec 003부터 쓰던 account `typesafe` 그대로다(spec 006 R-613). 접근성 속성은 두지 않는다(로그인 키체인에서
/// 지켜지는지 미확인, research R10). 앱 타깃에만 있고 시험에서 쓰지 않는다.
final class KeychainKeyStore: KeyStore {
    struct Failure: Error {
        let status: OSStatus
    }

    private let account: String

    init(account: String) {
        self.account = account
    }

    private var item: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: "dev.dongwon.moka", kSecAttrAccount: account]
    }

    /// 값을 꺼내지 않고 속성만 조회한다.
    func hasKey() throws -> Bool {
        var query = item
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess: return true
        case errSecItemNotFound: return false
        default: throw Failure(status: status)
        }
    }

    func read() throws -> String? {
        var query = item
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw Failure(status: status)
        }
    }

    /// 항목이 있으면 값만 바꾼다.
    func save(_ key: String) throws {
        let data = Data(key.utf8)
        var attributes = item
        attributes[kSecValueData] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = SecItemUpdate(item as CFDictionary, [kSecValueData: data] as CFDictionary)
            guard update == errSecSuccess else { throw Failure(status: update) }
            return
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    func delete() throws {
        let status = SecItemDelete(item as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
