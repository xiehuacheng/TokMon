import AppKit
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
    switch TokMonUpdateCompatibility.shared.updateSupport {
    case .supported:
      updaterController.checkForUpdates(nil)
    case .unsupportedLocation:
      showMoveToApplicationsAlert()
    case .adHocSigned:
      showAdHocWarningAlert()
    }
  }

  private func showMoveToApplicationsAlert() {
    let alert = NSAlert()
    alert.messageText = "自动更新受限"
    alert.informativeText = "当前 TokMon 没有放在“应用程序（/Applications）”文件夹中。继续自动安装更新可能导致 App 被终止后无法重新启动。请将 App 拖到 /Applications 后重试，或前往 Releases 页面手动下载最新版本。"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "前往 Releases")
    alert.addButton(withTitle: "取消")
    if alert.runModal() == .alertFirstButtonReturn,
       let url = URL(string: "https://github.com/xiehuacheng/TokMon/releases") {
      NSWorkspace.shared.open(url)
    }
  }

  private func showAdHocWarningAlert() {
    let alert = NSAlert()
    alert.messageText = "自动更新可能不稳定"
    alert.informativeText = "当前 TokMon 未使用 Apple Developer ID 签名。自动安装更新时 macOS 可能阻止替换或无法重新启动 App。建议前往 Releases 页面手动下载；如仍要继续，请确保 App 已位于 /Applications。"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "继续检查更新")
    alert.addButton(withTitle: "前往 Releases")
    alert.addButton(withTitle: "取消")
    switch alert.runModal() {
    case .alertFirstButtonReturn:
      updaterController.checkForUpdates(nil)
    case .alertSecondButtonReturn:
      if let url = URL(string: "https://github.com/xiehuacheng/TokMon/releases") {
        NSWorkspace.shared.open(url)
      }
    default:
      break
    }
  }
}

@MainActor
final class TokMonUpdateCompatibility {
  static let shared = TokMonUpdateCompatibility()

  enum UpdateSupport {
    case supported
    case unsupportedLocation
    case adHocSigned
  }

  var updateSupport: UpdateSupport {
    guard isInApplicationsFolder else {
      return .unsupportedLocation
    }
    return hasDeveloperIDSignature ? .supported : .adHocSigned
  }

  private var isInApplicationsFolder: Bool {
    Bundle.main.bundlePath.hasPrefix("/Applications/")
  }

  private var hasDeveloperIDSignature: Bool {
    guard FileManager.default.isExecutableFile(atPath: "/usr/bin/codesign") else {
      return false
    }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    task.arguments = ["-dvv", Bundle.main.bundlePath]
    let pipe = Pipe()
    task.standardError = pipe
    do {
      try task.run()
      task.waitUntilExit()
    } catch {
      return false
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else {
      return false
    }
    return output.contains("Authority=Developer ID Application:")
  }
}
