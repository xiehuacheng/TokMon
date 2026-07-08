import Foundation
import Testing
@testable import TokMonApp

@Suite struct TokMonKimiQuotaTests {
  @Test func parseShapeAWeeklyOnly() async throws {
    let json = """
    {
      "data": [
        { "model_name": "all", "limit": 1000, "used": 500 }
      ]
    }
    """.data(using: .utf8)!

    let store = TokMonKimiQuotaStore()
    let snapshot = try await store.parseForTests(json: json)

    #expect(snapshot.weekly?.limit == 1000)
    #expect(snapshot.weekly?.used == 500)
    #expect(snapshot.weekly?.percentUsed == 50)
    #expect(snapshot.fiveHour == nil)
  }

  @Test func parseShapeBWeeklyAndFiveHour() async throws {
    let json = """
    {
      "usage": { "limit": "100", "remaining": "74", "resetTime": "2026-02-11T17:32:50.757941Z" },
      "limits": [
        {
          "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
          "detail": { "limit": "100", "remaining": "85", "resetTime": "2026-02-07T12:32:50.757941Z" }
        }
      ]
    }
    """.data(using: .utf8)!

    let store = TokMonKimiQuotaStore()
    let snapshot = try await store.parseForTests(json: json)

    #expect(snapshot.weekly?.limit == 100)
    #expect(snapshot.weekly?.used == 26)
    #expect(snapshot.fiveHour?.limit == 100)
    #expect(snapshot.fiveHour?.used == 15)
    #expect(snapshot.fiveHour?.label == "5-Hour Limit")
  }

  @Test func parseResetInCountdown() async throws {
    let json = """
    {
      "usage": { "limit": 100, "used": 10, "reset_in": 7200 }
    }
    """.data(using: .utf8)!

    let store = TokMonKimiQuotaStore()
    let snapshot = try await store.parseForTests(json: json)

    #expect(snapshot.weekly?.used == 10)
    #expect(snapshot.weekly?.countdown == "2h 0m")
  }
}
