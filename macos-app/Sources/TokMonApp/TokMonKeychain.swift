import Foundation
import Security

enum TokMonKeychain {
  static let kimiService = "com.tokmon.kimi-code.api-key"
  static let kimiAccount = "kimi-code-api-key"

  static func saveKimiAPIKey(_ key: String) throws {
    try save(key, service: kimiService, account: kimiAccount)
  }

  static func loadKimiAPIKey() -> String? {
    load(service: kimiService, account: kimiAccount)
  }

  static func deleteKimiAPIKey() throws {
    try delete(service: kimiService, account: kimiAccount)
  }

  // MARK: - Internal primitives for testability

  static func save(_ value: String, service: String, account: String) throws {
    guard let data = value.data(using: .utf8) else {
      throw KimiKeychainError.invalidData
    }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    let status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecDuplicateItem {
      let updateQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
      ]
      let updateAttrs: [String: Any] = [kSecValueData as String: data]
      let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
      guard updateStatus == errSecSuccess else {
        throw KimiKeychainError.osStatus(updateStatus)
      }
    } else if status != errSecSuccess {
      throw KimiKeychainError.osStatus(status)
    }
  }

  static func load(service: String, account: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func delete(service: String, account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KimiKeychainError.osStatus(status)
    }
  }
}

enum KimiKeychainError: Error {
  case invalidData
  case osStatus(OSStatus)
}
