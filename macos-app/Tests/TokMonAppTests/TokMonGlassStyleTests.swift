import AppKit
import SwiftUI
import Testing
@testable import TokMonApp

@MainActor
@Test func darkModeInnerComponentsStayTransparent() {
  #expect(darkAlpha(TokMonGlass.cardBackgroundInner) <= 0.24)
  #expect(darkAlpha(TokMonGlass.cardBackgroundInnerHover) <= 0.32)
  #expect(darkAlpha(TokMonGlass.cardBackgroundInnerPress) <= 0.40)
  #expect(darkAlpha(TokMonGlass.cardRowIdle) <= 0.26)
  #expect(darkAlpha(TokMonGlass.cardRowHover) <= 0.34)
  #expect(darkAlpha(TokMonGlass.cardRowPress) <= 0.42)
  #expect(darkAlpha(TokMonGlass.accentTileIdle) <= 0.10)
  #expect(darkAlpha(TokMonGlass.accentTileHover) <= 0.14)
  #expect(darkAlpha(TokMonGlass.accentTilePress) <= 0.20)
  #expect(darkAlpha(TokMonGlass.cardBorder) <= 0.10)
}

private func darkAlpha(_ color: Color) -> CGFloat {
  let appearance = NSAppearance(named: .darkAqua)!
  var alpha: CGFloat = 0
  appearance.performAsCurrentDrawingAppearance {
    alpha = NSColor(color).usingColorSpace(.deviceRGB)?.alphaComponent ?? NSColor(color).alphaComponent
  }
  return alpha
}
