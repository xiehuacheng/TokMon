import Foundation
import Testing
@testable import TokMonApp

private final class StubURLProtocol: URLProtocol {
  nonisolated(unsafe) static var responses: [URL: (statusCode: Int, data: Data)] = [:]

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let url = request.url, let stub = StubURLProtocol.responses[url] else {
      client?.urlProtocol(self, didFailWithError: NSError(domain: "StubURLProtocol", code: -1))
      return
    }
    let response = HTTPURLResponse(
      url: url,
      statusCode: stub.statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: stub.data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite(.serialized) struct TokMonKimiQuotaTests {
  @Test func parseShapeAWeeklyOnly() async throws {
    let json = """
    {
      "data": [
        { "model_name": "all", "limit": 1000, "used": 500 }
      ]
    }
    """.data(using: .utf8)!

    let fixed = Date(timeIntervalSince1970: 1_000_000)
    let store = TokMonKimiQuotaStore()
    let snapshot = try await store.parseForTests(json: json, fetchedAt: fixed)

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

    let fixed = Date(timeIntervalSince1970: 1_000_000)
    let store = TokMonKimiQuotaStore()
    let snapshot = try await store.parseForTests(json: json, fetchedAt: fixed)

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

    let fixed = Date(timeIntervalSince1970: 1_000_000)
    let store = TokMonKimiQuotaStore()
    let snapshot = try await store.parseForTests(json: json, fetchedAt: fixed)

    #expect(snapshot.weekly?.used == 10)
    #expect(snapshot.weekly?.countdown == "2h 0m")
  }

  @Test func parseExplicitEndAt() async throws {
    let json = """
    {
      "usage": {
        "limit": 100,
        "used": 10,
        "resetTime": "2026-02-11T17:32:50.757941Z",
        "end_at": "2026-02-11T20:00:00.000000Z"
      }
    }
    """.data(using: .utf8)!

    let fixed = Date(timeIntervalSince1970: 1_000_000)
    let store = TokMonKimiQuotaStore()
    let snapshot = try await store.parseForTests(json: json, fetchedAt: fixed)

    #expect(Int(snapshot.weekly?.resetAt?.timeIntervalSince1970 ?? 0) == 1_770_831_170)
    #expect(snapshot.weekly?.endAt?.timeIntervalSince1970 == 1_770_840_000)
  }

  @Test func parseEndAtFallsBackToResetAt() async throws {
    let json = """
    {
      "usage": { "limit": 100, "used": 10, "resetTime": "2026-02-11T17:32:50.757941Z" }
    }
    """.data(using: .utf8)!

    let fixed = Date(timeIntervalSince1970: 1_000_000)
    let store = TokMonKimiQuotaStore()
    let snapshot = try await store.parseForTests(json: json, fetchedAt: fixed)

    #expect(snapshot.weekly?.endAt == snapshot.weekly?.resetAt)
  }

  @Test func parseWindowEndForFiveHour() async throws {
    let json = """
    {
      "usage": { "limit": "100", "remaining": "74", "resetTime": "2026-02-11T17:32:50.757941Z" },
      "limits": [
        {
          "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE", "end": "2026-02-07T14:00:00.000000Z" },
          "detail": { "limit": "100", "remaining": "85" }
        }
      ]
    }
    """.data(using: .utf8)!

    let fixed = Date(timeIntervalSince1970: 1_000_000)
    let store = TokMonKimiQuotaStore()
    let snapshot = try await store.parseForTests(json: json, fetchedAt: fixed)

    #expect(snapshot.fiveHour?.endAt?.timeIntervalSince1970 == 1_770_472_800)
  }

  @Test func fallsBackFromUsagesToUsageOn404() async throws {
    let usagesURL = URL(string: "https://api.kimi.com/coding/v1/usages")!
    let usageURL = URL(string: "https://api.kimi.com/coding/v1/usage")!
    let usageJSON = """
    {
      "usage": { "limit": 100, "used": 10 }
    }
    """.data(using: .utf8)!

    StubURLProtocol.responses = [
      usagesURL: (statusCode: 404, data: Data()),
      usageURL: (statusCode: 200, data: usageJSON),
    ]
    defer { StubURLProtocol.responses = [:] }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: config)
    let store = TokMonKimiQuotaStore(urlSession: session)
    let snapshot = await store.fetchQuota(apiKey: "sk-kimi-test")

    #expect(snapshot.error == nil)
    #expect(snapshot.weekly?.limit == 100)
    #expect(snapshot.weekly?.used == 10)
  }

  @Test func mapsHTTPStatusCodesToErrors() async throws {
    let usagesURL = URL(string: "https://api.kimi.com/coding/v1/usages")!
    let cases: [(Int, KimiQuotaError)] = [
      (401, .invalidKey),
      (403, .invalidKey),
      (429, .rateLimited),
      (500, .network),
    ]

    for (status, expected) in cases {
      StubURLProtocol.responses = [usagesURL: (statusCode: status, data: Data())]
      defer { StubURLProtocol.responses = [:] }

      let config = URLSessionConfiguration.ephemeral
      config.protocolClasses = [StubURLProtocol.self]
      let session = URLSession(configuration: config)
      let store = TokMonKimiQuotaStore(urlSession: session)
      let snapshot = await store.fetchQuota(apiKey: "sk-kimi-test")

      #expect(snapshot.error == expected, "Expected \(expected) for status \(status), got \(String(describing: snapshot.error))")
    }
  }

}
