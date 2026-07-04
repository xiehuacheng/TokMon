import Testing
import CoreGraphics
@testable import TokMonApp

@Suite("Status popover screenshot crop rect")
struct StatusPopoverScreenshotTests {
  private let mainDisplay = CGRect(x: 0, y: 0, width: 1920, height: 1080)
  private let scale: CGFloat = 2

  @Test
  func cropRectOnMainDisplay() {
    // The real panel size in AppKit global coords (bottom-left origin).
    let panelWidth = statusPanelContentWidth + statusPanelShadowPadding * 2
    let panelHeight = statusPanelHeight + statusPanelShadowPadding
    let windowFrame = CGRect(x: 100, y: 100, width: panelWidth, height: panelHeight)

    let cropRect = statusPanelScreenshotCropRect(
      windowFrame: windowFrame,
      displayFrame: mainDisplay,
      scale: scale,
      mainDisplayHeight: mainDisplay.height
    )

    let expectedWindowTopInCG = mainDisplay.height - windowFrame.maxY
    let expectedCropLeft = (windowFrame.minX + sessionBubbleWidth + sessionBubbleGutter) * scale
    let expectedCropTop = expectedWindowTopInCG * scale
    let expectedCropWidth = CGFloat(statusPanelMainWidth + statusPanelShadowPadding * 2) * scale
    let expectedCropHeight = CGFloat(statusPanelHeight + statusPanelShadowPadding) * scale

    #expect(cropRect.minX == expectedCropLeft)
    #expect(cropRect.minY == expectedCropTop)
    #expect(cropRect.width == expectedCropWidth)
    #expect(cropRect.height == expectedCropHeight)
  }

  @Test
  func cropRectOnRightDisplay() {
    let panelWidth = statusPanelContentWidth + statusPanelShadowPadding * 2
    let panelHeight = statusPanelHeight + statusPanelShadowPadding
    let rightDisplay = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
    let windowFrame = CGRect(x: 2020, y: 100, width: panelWidth, height: panelHeight)

    let cropRect = statusPanelScreenshotCropRect(
      windowFrame: windowFrame,
      displayFrame: rightDisplay,
      scale: scale,
      mainDisplayHeight: mainDisplay.height
    )

    let expectedWindowTopInCG = mainDisplay.height - windowFrame.maxY
    let expectedCropLeft = (windowFrame.minX - rightDisplay.minX + sessionBubbleWidth + sessionBubbleGutter) * scale
    let expectedCropTop = (expectedWindowTopInCG - rightDisplay.minY) * scale

    #expect(cropRect.minX == expectedCropLeft)
    #expect(cropRect.minY == expectedCropTop)
  }

  @Test
  func cropRectOnDisplayBelowMain() {
    let panelWidth = statusPanelContentWidth + statusPanelShadowPadding * 2
    let panelHeight = statusPanelHeight + statusPanelShadowPadding
    let belowDisplay = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
    // AppKit frame for a panel 100 px above the bottom of the below display.
    let windowFrame = CGRect(x: 100, y: -100 - panelHeight, width: panelWidth, height: panelHeight)

    let cropRect = statusPanelScreenshotCropRect(
      windowFrame: windowFrame,
      displayFrame: belowDisplay,
      scale: scale,
      mainDisplayHeight: mainDisplay.height
    )

    let expectedWindowTopInCG = mainDisplay.height - windowFrame.maxY
    let expectedCropLeft = (windowFrame.minX - belowDisplay.minX + sessionBubbleWidth + sessionBubbleGutter) * scale
    let expectedCropTop = (expectedWindowTopInCG - belowDisplay.minY) * scale

    // Before the fix, the below-display case produced a negative or out-of-bounds y.
    #expect(cropRect.minY >= 0)
    #expect(cropRect.minX == expectedCropLeft)
    #expect(cropRect.minY == expectedCropTop)
  }
}
