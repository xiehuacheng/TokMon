import Foundation
import Testing
@testable import TokMonApp

@Suite final class TokMonKeychainTests {
  private let testService = "com.tokmon.test.key"
  private let testAccount = "test-account"

  init() throws {
    try? TokMonKeychain.delete(service: testService, account: testAccount)
  }

  deinit {
    try? TokMonKeychain.delete(service: testService, account: testAccount)
  }

  @Test func keychainSaveLoadDelete() throws {
    let value = "sk-kimi-test-key"
    #expect(TokMonKeychain.load(service: testService, account: testAccount) == nil)

    try TokMonKeychain.save(value, service: testService, account: testAccount)
    #expect(TokMonKeychain.load(service: testService, account: testAccount) == value)

    let updated = "sk-kimi-updated"
    try TokMonKeychain.save(updated, service: testService, account: testAccount)
    #expect(TokMonKeychain.load(service: testService, account: testAccount) == updated)

    try TokMonKeychain.delete(service: testService, account: testAccount)
    #expect(TokMonKeychain.load(service: testService, account: testAccount) == nil)
  }

  @Test func keychainManagesMultipleKimiAPIKeys() throws {
    let id1 = "test-kimi-id-\(UUID().uuidString)"
    let id2 = "test-kimi-id-\(UUID().uuidString)"
    defer {
      try? TokMonKeychain.deleteKimiAPIKey(id: id1)
      try? TokMonKeychain.deleteKimiAPIKey(id: id2)
    }

    #expect(TokMonKeychain.loadKimiAPIKey(id: id1) == nil)
    #expect(TokMonKeychain.loadKimiAPIKey(id: id2) == nil)

    try TokMonKeychain.saveKimiAPIKey("sk-kimi-one", id: id1)
    try TokMonKeychain.saveKimiAPIKey("sk-kimi-two", id: id2)

    #expect(TokMonKeychain.loadKimiAPIKey(id: id1) == "sk-kimi-one")
    #expect(TokMonKeychain.loadKimiAPIKey(id: id2) == "sk-kimi-two")
    #expect(TokMonKeychain.hasKimiAPIKey(id: id1))
    #expect(TokMonKeychain.hasKimiAPIKey(id: id2))

    let allIDs = TokMonKeychain.allKimiAPIKeyAccountIDs()
    #expect(allIDs.contains(id1))
    #expect(allIDs.contains(id2))

    try TokMonKeychain.deleteKimiAPIKey(id: id1)
    #expect(TokMonKeychain.loadKimiAPIKey(id: id1) == nil)
    #expect(!TokMonKeychain.hasKimiAPIKey(id: id1))

    try TokMonKeychain.deleteKimiAPIKey(id: id2)
    #expect(TokMonKeychain.loadKimiAPIKey(id: id2) == nil)
  }
}
