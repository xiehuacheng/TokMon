import Foundation
import Testing
@testable import AgentMonApp

@Test func configStoreLoadsDefaultsWhenNoFileExists() throws {
  let dataDir = try makeTokMonTempDir()
  let store = TokMonConfigStore(dataDir: dataDir)

  let config = try store.loadConfig()
  let state = try store.loadUIState()

  #expect(config.sources["claude-code"]?.path == "~/.claude/projects")
  #expect(config.sources["codex"]?.path == "~/.codex/sessions")
  #expect(state.rangeLabel == "thisWeek")
  #expect(state.rangeDays == nil)
  #expect(state.rangeMode == "round")
  #expect(state.activeSeries == "total")
}

@Test func configStoreMigratesLegacyDashboardStateOnce() throws {
  let dataDir = try makeTokMonTempDir()
  let legacyURL = dataDir.appendingPathComponent("tokmon-dashboard-state.json")
  try """
  {
    "source": "codex",
    "from": "2026-05-13 00:00:00",
    "to": "2026-05-14 00:00:00",
    "interval": "hour",
    "liveMode": true,
    "rangeMode": "round",
    "rangeLabel": "24H",
    "rangeHours": 24,
    "rangeDays": null,
    "refreshRate": 5000,
    "activeSeries": "output",
    "costRates": {
      "input": 1.1,
      "output": 2.2,
      "cache_create": 0.3,
      "cache_read": 0.4
    },
    "modelPricing": {
      "gpt-a": {
        "input": 3.1,
        "output": 4.2,
        "cache_create": 0.5,
        "cache_read": 0.6
      }
    }
  }
  """.write(to: legacyURL, atomically: true, encoding: .utf8)

  let store = TokMonConfigStore(dataDir: dataDir)
  let state = try store.loadUIState()

  #expect(state.source == "codex")
  #expect(state.from == "2026-05-13 00:00:00")
  #expect(state.to == "2026-05-14 00:00:00")
  #expect(state.interval == "hour")
  #expect(state.rangeMode == "round")
  #expect(state.rangeLabel == "today")
  #expect(state.rangeHours == nil)
  #expect(state.rangeDays == nil)
  #expect(state.refreshRate == 5000)
  #expect(state.activeSeries == "output")
  #expect(state.costRates.output == 2.2)
  #expect(state.costRates.cacheCreate == 0.3)
  #expect(state.costRates.cacheRead == 0.4)
  #expect(state.modelPricing["gpt-a"] == TokMonCostRates(input: 3.1, output: 4.2, cacheCreate: 0.5, cacheRead: 0.6))
  #expect(FileManager.default.fileExists(atPath: dataDir.appendingPathComponent("tokmon-ui-state.json").path))
}

@Test func configStoreDefaultsMissingNativeConfigAndUIStateFields() throws {
  let dataDir = try makeTokMonTempDir()
  try """
  {
    "port": 3390,
    "sources": {
      "codex": { "path": "~/custom-codex" }
    }
  }
  """.write(to: dataDir.appendingPathComponent("tokmon.config.json"), atomically: true, encoding: .utf8)
  try """
  {
    "source": "codex",
    "rangeHours": null,
    "costRates": {
      "output": 9.5
    },
    "modelPricing": {
      "gpt-a": {
        "input": 1.5,
        "output": 2.5,
        "cache_create": 3.5,
        "cache_read": 4.5
      },
      "bad": {
        "input": true,
        "output": "expensive"
      }
    }
  }
  """.write(to: dataDir.appendingPathComponent("tokmon-ui-state.json"), atomically: true, encoding: .utf8)
  let store = TokMonConfigStore(dataDir: dataDir)

  let config = try store.loadConfig()
  let state = try store.loadUIState()

  #expect(config.port == 3390)
  #expect(config.sources["claude-code"]?.path == "~/.claude/projects")
  #expect(config.sources["codex"]?.path == "~/custom-codex")
  #expect(state.source == "codex")
  #expect(state.from == "")
  #expect(state.to == "")
  #expect(state.rangeLabel == "thisWeek")
  #expect(state.rangeHours == nil)
  #expect(state.rangeDays == nil)
  #expect(state.costRates.input == 0)
  #expect(state.costRates.output == 9.5)
  #expect(state.modelPricing["gpt-a"] == TokMonCostRates(input: 1.5, output: 2.5, cacheCreate: 3.5, cacheRead: 4.5))
  #expect(state.modelPricing["bad"] == TokMonCostRates(input: 0, output: 0, cacheCreate: 0, cacheRead: 0))
}

@Test func configStoreFallsBackWhenLegacyDashboardStateIsMalformed() throws {
  let dataDir = try makeTokMonTempDir()
  try """
  {
    "source": "codex",
    "liveMode": true,
    "refreshRate": "fast",
    "costRates": {
      "input": "expensive",
      "cache_create": true,
      "output": 1.25
    }
  }
  """.write(to: dataDir.appendingPathComponent("tokmon-dashboard-state.json"), atomically: true, encoding: .utf8)
  let store = TokMonConfigStore(dataDir: dataDir)

  let state = try store.loadUIState()

  #expect(state.source == "codex")
  #expect(state.refreshRate == 3000)
  #expect(state.costRates.input == 0)
  #expect(state.costRates.output == 1.25)
  #expect(state.costRates.cacheCreate == 0)
  #expect(FileManager.default.fileExists(atPath: dataDir.appendingPathComponent("tokmon-ui-state.json").path))
}

@Test func configStoreSavesPrettyJSONWithTrailingNewlineAndExpandsHomePath() throws {
  let dataDir = try makeTokMonTempDir()
  let store = TokMonConfigStore(dataDir: dataDir)
  let config = TokMonConfig(
    port: 3399,
    sources: [
      "claude-code": TokMonSourceConfig(path: "~/.claude/projects"),
      "codex": TokMonSourceConfig(path: "~/.codex/sessions"),
      "custom": TokMonSourceConfig(path: "~/custom/sessions"),
    ],
  )
  var state = TokMonUIState.default
  state.activeSeries = "cost"

  try store.saveConfig(config)
  try store.saveUIState(state)

  let configText = try String(contentsOf: dataDir.appendingPathComponent("tokmon.config.json"), encoding: .utf8)
  let stateText = try String(contentsOf: dataDir.appendingPathComponent("tokmon-ui-state.json"), encoding: .utf8)

  #expect(configText.contains("  \"port\""))
  #expect(configText.hasSuffix("\n"))
  #expect(stateText.hasSuffix("\n"))
  #expect(try store.loadConfig() == config)
  #expect(try store.loadUIState() == state)
  #expect(store.expandUserPath("~/custom/sessions") == FileManager.default.homeDirectoryForCurrentUser.path + "/custom/sessions")
  #expect(store.expandUserPath("/tmp/~/sessions") == "/tmp/~/sessions")
}
