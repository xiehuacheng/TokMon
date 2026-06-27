import Foundation
import Testing
@testable import TokMonApp

@Test func configStoreLoadsDefaultsWhenNoFileExists() throws {
  let dataDir = try makeTokMonTempDir()
  let store = TokMonConfigStore(dataDir: dataDir)

  let config = try store.loadConfig()
  let state = try store.loadUIState()

  #expect(config.sources["claude-code"]?.path == "~/.claude/projects")
  #expect(config.sources["codex"]?.path == "~/.codex")
  #expect(config.sources["opencode"]?.path == "~/.local/share/opencode")
  #expect(config.sources["qwen-code"]?.path == "~/.qwen/projects")
  #expect(state.rangeLabel == "thisWeek")
  #expect(state.rangeDays == nil)
  #expect(state.rangeMode == "round")
  #expect(state.activeSeries == "total")
  #expect(state.menuBarDisplayMode == .iconOnly)
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
  #expect(config.sources["opencode"]?.path == "~/.local/share/opencode")
  #expect(config.sources["qwen-code"]?.path == "~/.qwen/projects")
  #expect(state.source == "codex")
  #expect(state.from == "")
  #expect(state.to == "")
  #expect(state.rangeLabel == "thisWeek")
  #expect(state.rangeHours == nil)
  #expect(state.rangeDays == nil)
  #expect(state.costRates.input == 0)
  #expect(state.costRates.output == 9.5)
  #expect(state.menuBarDisplayMode == .iconOnly)
  #expect(state.modelPricing["gpt-a"] == TokMonCostRates(input: 1.5, output: 2.5, cacheCreate: 3.5, cacheRead: 4.5))
  #expect(state.modelPricing["bad"] == TokMonCostRates(input: 0, output: 0, cacheCreate: 0, cacheRead: 0))
}

@Test func configStoreLoadsAndSavesMenuBarDisplayMode() throws {
  let dataDir = try makeTokMonTempDir()
  try """
  {
    "source": "codex",
    "rangeLabel": "today",
    "menuBarDisplayMode": "estimatedCost"
  }
  """.write(to: dataDir.appendingPathComponent("tokmon-ui-state.json"), atomically: true, encoding: .utf8)
  let store = TokMonConfigStore(dataDir: dataDir)

  var state = try store.loadUIState()
  #expect(state.menuBarDisplayMode == .estimatedCost)

  state.menuBarDisplayMode = .requests
  try store.saveUIState(state)

  let text = try String(contentsOf: dataDir.appendingPathComponent("tokmon-ui-state.json"), encoding: .utf8)
  #expect(text.contains("\"menuBarDisplayMode\" : \"requests\""))
  #expect(try store.loadUIState().menuBarDisplayMode == .requests)
}

@Test func configStoreDefaultsUnknownMenuBarDisplayModeToIconOnly() throws {
  let dataDir = try makeTokMonTempDir()
  try """
  {
    "source": "codex",
    "menuBarDisplayMode": "inputTokens"
  }
  """.write(to: dataDir.appendingPathComponent("tokmon-ui-state.json"), atomically: true, encoding: .utf8)
  let store = TokMonConfigStore(dataDir: dataDir)

  #expect(try store.loadUIState().menuBarDisplayMode == .iconOnly)
}

@Test func configStoreSavesPrettyJSONWithTrailingNewlineAndExpandsHomePath() throws {
  let dataDir = try makeTokMonTempDir()
  let store = TokMonConfigStore(dataDir: dataDir)
  let config = TokMonConfig(
    port: 3399,
    sources: [
      "claude-code": TokMonSourceConfig(path: "~/.claude/projects"),
      "codex": TokMonSourceConfig(path: "~/.codex/sessions"),
      "opencode": TokMonSourceConfig(path: "~/.local/share/opencode"),
      "qwen-code": TokMonSourceConfig(path: "~/.qwen/projects"),
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
