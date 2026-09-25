import Foundation
import Security

enum Credentials {
    private static let service = "nl.martijn.aipulse"
    static func read(_ account: String) throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw error(status) }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ value: String, account: String) throws {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary
        let status = SecItemUpdate(query, [kSecValueData: Data(value.utf8)] as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                kSecAttrAccount: account, kSecValueData: Data(value.utf8),
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary, nil)
            guard added == errSecSuccess else { throw error(added) }
        } else if status != errSecSuccess { throw error(status) }
    }
    static func remove(_ account: String) throws {
        let status = SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw error(status) }
    }
    private static func error(_ status: OSStatus) -> UsageError {
        .unavailable("Keychain access failed (\(status)). Unlock your Mac and try again.")
    }
}

final class SameHostRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == task.originalRequest?.url?.host ? request : nil)
    }
    static let session = URLSession(configuration: .ephemeral, delegate: SameHostRedirects(), delegateQueue: nil)
}
