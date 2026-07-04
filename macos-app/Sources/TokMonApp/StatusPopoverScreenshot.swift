import CoreGraphics

/// Converts a status-panel window frame and target display frame into a crop
/// rectangle for `CGImage.cropping(to:)`.
///
/// `windowFrame` is in AppKit global coordinates (origin at the bottom-left of
/// the main display, y increasing upward). `displayFrame` and the returned rect
/// are in Core Graphics / ScreenCaptureKit coordinates (origin at the top-left
/// of the main display, y increasing downward).
func statusPanelScreenshotCropRect(
  windowFrame: CGRect,
  displayFrame: CGRect,
  scale: CGFloat,
  mainDisplayHeight: CGFloat
) -> CGRect {
  // AppKit global coords -> Core Graphics global coords.
  let windowTopInCG = mainDisplayHeight - windowFrame.maxY
  let windowFrameInCG = CGRect(
    x: windowFrame.minX,
    y: windowTopInCG,
    width: windowFrame.width,
    height: windowFrame.height
  )

  // Position of the full panel within the captured display image, in pixels.
  let windowLeftPixel = (windowFrameInCG.minX - displayFrame.minX) * scale
  let windowTopPixel = (windowFrameInCG.minY - displayFrame.minY) * scale
  let windowPixelRect = CGRect(
    x: windowLeftPixel,
    y: windowTopPixel,
    width: windowFrameInCG.width * scale,
    height: windowFrameInCG.height * scale
  )

  // Crop to the main panel content, excluding the session-bubble gutter.
  let cropLeft = windowPixelRect.minX + CGFloat(sessionBubbleWidth + sessionBubbleGutter) * scale
  let cropWidth = CGFloat(statusPanelMainWidth + statusPanelShadowPadding * 2) * scale
  let cropHeight = CGFloat(statusPanelHeight + statusPanelShadowPadding) * scale

  return CGRect(
    x: cropLeft,
    y: windowPixelRect.minY,
    width: cropWidth,
    height: cropHeight
  )
}
