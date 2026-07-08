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
}
