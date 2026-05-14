import Testing
@testable import AgentMonApp

@Test func summaryEstimatedCostUsesLatestModelTotals() {
  let summary = TokMonSummary(
    total: TokMonTotals(
      totalRequests: 1,
      totalInput: 12,
      totalOutput: 6,
      totalCacheCreation: 4,
      totalCacheRead: 2,
      totalReasoning: 0,
    ),
    bySource: [],
    byModel: [
      TokMonModelTotals(
        model: "gpt-test",
        source: "codex",
        requests: 1,
        inputTokens: 12,
        outputTokens: 6,
        cacheCreation: 4,
        cacheRead: 2,
      ),
    ],
  )

  let rates = TokMonCostRates(input: 10, output: 20, cacheCreate: 2, cacheRead: 1)

  #expect(summary.estimatedCost(costRates: rates) == 0.00025)
}
