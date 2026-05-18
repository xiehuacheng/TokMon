import Foundation

final class TokMonEngine {
  let configStore: TokMonConfigStore
  let database: TokMonDatabase
  let scanner: TokMonScanner
  let queryStore: TokMonQueryStore
  let parityVerifier: TokMonParityVerifier

  init(
    configStore: TokMonConfigStore,
    database: TokMonDatabase,
    scanner: TokMonScanner? = nil,
    queryStore: TokMonQueryStore = TokMonQueryStore(),
    parityVerifier: TokMonParityVerifier = TokMonParityVerifier(),
  ) {
    self.configStore = configStore
    self.database = database
    self.scanner = scanner ?? TokMonScanner(database: database)
    self.queryStore = queryStore
    self.parityVerifier = parityVerifier
  }
}
