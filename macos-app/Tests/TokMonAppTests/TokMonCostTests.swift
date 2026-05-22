import Testing
@testable import TokMonApp

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

@Test func summaryEstimatedCostUsesPerModelPricing() {
  let summary = TokMonSummary(
    total: TokMonTotals(
      totalRequests: 2,
      totalInput: 30,
      totalOutput: 9,
      totalCacheCreation: 4,
      totalCacheRead: 2,
      totalReasoning: 0,
    ),
    bySource: [],
    byModel: [
      TokMonModelTotals(
        model: "gpt-a",
        source: "codex",
        requests: 1,
        inputTokens: 10,
        outputTokens: 5,
        cacheCreation: 4,
        cacheRead: 2,
      ),
      TokMonModelTotals(
        model: "gpt-b",
        source: "codex",
        requests: 1,
        inputTokens: 20,
        outputTokens: 4,
        cacheCreation: 0,
        cacheRead: 0,
      ),
      TokMonModelTotals(
        model: "unpriced",
        source: "codex",
        requests: 1,
        inputTokens: 999,
        outputTokens: 999,
        cacheCreation: 999,
        cacheRead: 999,
      ),
    ],
  )

  let pricing = [
    "gpt-a": TokMonCostRates(input: 10, output: 20, cacheCreate: 2, cacheRead: 1),
    "gpt-b": TokMonCostRates(input: 1, output: 2, cacheCreate: 3, cacheRead: 4),
  ]

  #expect(summary.estimatedCost(modelPricing: pricing) == 0.000238)
}

@Test func cacheHitRateUsesCacheReadOverInputPlusCacheRead() {
  let totals = TokMonTotals(
    totalRequests: 2,
    totalInput: 30,
    totalOutput: 10,
    totalCacheCreation: 0,
    totalCacheRead: 70,
    totalReasoning: 0,
  )
  let source = TokMonSourceTotals(
    source: "codex",
    requests: 2,
    inputTokens: 30,
    outputTokens: 10,
    cacheCreation: 0,
    cacheRead: 70,
  )
  let bucket = TokMonTrendBucket(
    bucket: "2026-05-14",
    inputTokens: 30,
    outputTokens: 10,
    cacheCreation: 0,
    cacheRead: 70,
    requests: 2,
  )

  #expect(totals.cacheHitRate == 0.7)
  #expect(source.value(for: .cacheHitRate, costRates: .zero) == 0.7)
  #expect(bucket.value(for: .cacheHitRate, costRates: .zero) == 0.7)
  #expect(TokMonTotals(totalRequests: 0, totalInput: 0, totalOutput: 0, totalCacheCreation: 0, totalCacheRead: 0, totalReasoning: 0).cacheHitRate == 0)
}
