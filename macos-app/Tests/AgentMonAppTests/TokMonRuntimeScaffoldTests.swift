import Testing
@testable import AgentMonApp

@Test func nativeTokMonRuntimeTypesAreAvailable() {
  _ = TokMonConfig.self
  _ = TokMonUIState.self
  _ = TokMonUsageRecord.self
  _ = TokMonEngine.self
  _ = TokMonConfigStore.self
  _ = TokMonDatabase.self
  _ = TokMonScanner.self
  _ = TokMonQueryStore.self
  _ = TokMonParityVerifier.self
}
