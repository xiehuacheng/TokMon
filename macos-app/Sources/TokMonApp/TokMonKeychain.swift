import Foundation
import Security

enum TokMonKeychain {
  static let kimiService = "com.tokmon.kimi-code.api-key"
  /// Legacy single-key account; kept for migration.
  static let kimiAccount = "kimi-code-api-key"
  /// Unified account that stores all Kimi API keys in a single Keychain item.
  static let kimiKeysAccount = "kimi-code-api-keys"

  // MARK: - Unified multi-key storage

  static func saveKimiAPIKeys(_ keys: [String: String]) throws {
    let data = try JSONEncoder().encode(keys)
    guard let json = String(data: data, encoding: .utf8) else {
      throw KimiKeychainError.invalidData
    }
    try save(json, service: kimiService, account: kimiKeysAccount)
  }

  static func loadKimiAPIKeys() -> [String: String] {
    guard let json = load(service: kimiService, account: kimiKeysAccount),
          let data = json.data(using: .utf8) else {
      return [:]
    }
    return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
  }

  static func deleteKimiAPIKeys() throws {
    try delete(service: kimiService, account: kimiKeysAccount)
  }

  // MARK: - Legacy per-key storage (kept for migration)

  static func saveKimiAPIKey(_ key: String, id: String) throws {
    try save(key, service: kimiService, account: id)
  }

  static func loadKimiAPIKey(id: String) -> String? {
    load(service: kimiService, account: id)
  }

  static func deleteKimiAPIKey(id: String) throws {
    try delete(service: kimiService, account: id)
  }

  static func hasKimiAPIKey(id: String) -> Bool {
    has(service: kimiService, account: id)
  }

  static func allKimiAPIKeyAccountIDs() -> [String] {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: kimiService,
      kSecReturnAttributes as String: true,
      kSecMatchLimit as String: kSecMatchLimitAll,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess else {
      return []
    }
    guard let items = result as? [[String: Any]] else {
      return []
    }
    return items.compactMap { $0[kSecAttrAccount as String] as? String }
  }

  // MARK: - Internal primitives for testability

  static func save(_ value: String, service: String, account: String) throws {
    guard let data = value.data(using: .utf8) else {
      throw KimiKeychainError.invalidData
    }

    // Try updating an existing item first. This avoids the access-control
    // evaluation that SecItemAdd performs even when the item already exists.
    let updateQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let updateAttrs: [String: Any] = [kSecValueData as String: data]
    let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
    if updateStatus == errSecSuccess {
      return
    } else if updateStatus != errSecItemNotFound {
      throw KimiKeychainError.osStatus(updateStatus)
    }

    // The item does not exist yet; add it.
    let addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw KimiKeychainError.osStatus(addStatus)
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

  static func has(service: String, account: String) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: false,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    return status == errSecSuccess
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

enum KimiKeychainError: Error, LocalizedError {
  case invalidData
  case osStatus(OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidData:
      return "Unable to encode the API key for Keychain storage."
    case .osStatus(let status):
      return "Keychain operation failed (status \(status))."
    }
  }
}
