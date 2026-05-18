import Foundation

final class TokMonParityVerifier {
  init() {}

  func compare(native: TokMonParitySnapshot, legacy: TokMonParitySnapshot) -> TokMonParityReport {
    var differences: [TokMonParityDifference] = []
    appendDifferences(&differences, endpoint: "summary", native: native.summary, legacy: legacy.summary)
    appendDifferences(&differences, endpoint: "trend", native: native.trend, legacy: legacy.trend)
    appendDifferences(&differences, endpoint: "heatmap", native: native.heatmap, legacy: legacy.heatmap)
    appendDifferences(&differences, endpoint: "models", native: native.models, legacy: legacy.models)
    appendDifferences(&differences, endpoint: "records", native: native.records, legacy: legacy.records)
    appendDifferences(&differences, endpoint: "sessions", native: native.sessions, legacy: legacy.sessions)
    return TokMonParityReport(differences: differences)
  }

  private func appendDifferences(
    _ differences: inout [TokMonParityDifference],
    endpoint: String,
    native: [String: String],
    legacy: [String: String],
  ) {
    let keys = Set(native.keys).union(legacy.keys).sorted()
    for key in keys where native[key] != legacy[key] {
      differences.append(TokMonParityDifference(
        endpoint: endpoint,
        path: key,
        native: native[key] ?? "<missing>",
        legacy: legacy[key] ?? "<missing>",
      ))
    }
  }
}

struct TokMonParitySnapshot: Equatable {
  let summary: [String: String]
  let trend: [String: String]
  let heatmap: [String: String]
  let models: [String: String]
  let records: [String: String]
  let sessions: [String: String]
}

struct TokMonParityReport: Equatable {
  let differences: [TokMonParityDifference]

  var passed: Bool {
    differences.isEmpty
  }

  var summary: String {
    if passed {
      return "Legacy parity passed."
    }
    return "Legacy parity failed with \(differences.count) differences."
  }
}

struct TokMonParityDifference: Equatable, Identifiable {
  var id: String { "\(endpoint):\(path)" }
  let endpoint: String
  let path: String
  let native: String
  let legacy: String
}
