import Sparkle

@MainActor
final class TokMonUpdater: ObservableObject {
  static let shared = TokMonUpdater()

  private let updaterController: SPUStandardUpdaterController

  init() {
    updaterController = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }

  func checkForUpdates() {
    updaterController.checkForUpdates(nil)
  }
}
