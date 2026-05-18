import Testing
@testable import AgentMonApp

@Test func parityVerifierReportsPassForMatchingSnapshots() {
  let snapshot = TokMonParitySnapshot(
    summary: ["total.total_requests": "2", "total.total_input": "30"],
    trend: ["2026-05-14 09:00.requests": "2"],
    heatmap: ["2026-05-14.requests": "2"],
    models: ["0.model": "gpt-a"],
    records: ["total": "2", "0.session_id": "s1"],
    sessions: ["0.session_id": "s1", "0.requests": "2"],
  )
  let report = TokMonParityVerifier().compare(native: snapshot, legacy: snapshot)

  #expect(report.passed)
  #expect(report.differences.isEmpty)
  #expect(report.summary == "Legacy parity passed.")
}

@Test func parityVerifierReportsDeepFieldDifferences() {
  let native = TokMonParitySnapshot(
    summary: ["total.total_requests": "2", "total.total_input": "30"],
    trend: ["2026-05-14 09:00.requests": "2"],
    heatmap: ["2026-05-14.requests": "2"],
    models: ["0.model": "gpt-a"],
    records: ["total": "2", "0.session_id": "s1"],
    sessions: ["0.session_id": "s1", "0.requests": "2"],
  )
  let legacy = TokMonParitySnapshot(
    summary: ["total.total_requests": "2", "total.total_input": "31"],
    trend: ["2026-05-14 09:00.requests": "1"],
    heatmap: ["2026-05-14.requests": "3"],
    models: ["0.model": "gpt-b"],
    records: ["total": "2", "0.session_id": "s2"],
    sessions: ["0.session_id": "s1", "0.requests": "1"],
  )

  let report = TokMonParityVerifier().compare(native: native, legacy: legacy)

  #expect(!report.passed)
  #expect(report.differences.contains(TokMonParityDifference(endpoint: "summary", path: "total.total_input", native: "30", legacy: "31")))
  #expect(report.differences.contains(TokMonParityDifference(endpoint: "records", path: "0.session_id", native: "s1", legacy: "s2")))
  #expect(report.summary == "Legacy parity failed with 6 differences.")
}
