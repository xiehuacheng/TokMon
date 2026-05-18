import Foundation

final class TokMonConfigStore {
  var config: TokMonConfig
  var uiState: TokMonUIState

  init(config: TokMonConfig = .default, uiState: TokMonUIState = .default) {
    self.config = config
    self.uiState = uiState
  }
}
