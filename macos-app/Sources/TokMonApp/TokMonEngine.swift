import Foundation

final class TokMonEngine: @unchecked Sendable {
  let configStore: TokMonConfigStore
  let database: TokMonDatabase
  let scanner: TokMonScanner
  let queryStore: TokMonQueryStore
  let kimiQuotaStore: TokMonKimiQuotaStore

  init(
    configStore: TokMonConfigStore,
    database: TokMonDatabase,
    scanner: TokMonScanner? = nil,
    queryStore: TokMonQueryStore? = nil,
    kimiQuotaStore: TokMonKimiQuotaStore? = nil
  ) {
    self.configStore = configStore
    self.database = database
    self.scanner = scanner ?? TokMonScanner(database: database)
    self.queryStore = queryStore ?? TokMonQueryStore(database: database)
    self.kimiQuotaStore = kimiQuotaStore ?? TokMonKimiQuotaStore()
  }
}
