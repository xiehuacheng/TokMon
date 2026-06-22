import SwiftUI

enum TokMonGlass {
  /// Deep tech blue — primary brand color for totals, selected states, and Codex.
  static let accent = Color(nsColor: NSColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1))

  /// Teal green — used for cost, cache hit rate, and OpenCode.
  static let success = Color(nsColor: NSColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1))

  /// Cool amber — used for cache-related series and Claude Code.
  static let warning = Color(nsColor: NSColor(red: 1.0, green: 0.70, blue: 0.25, alpha: 1))

  /// Bright crimson — errors, zero/negative deltas, and Qwen Code.
  static let danger = Color(nsColor: NSColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1))

  /// Subtle glass edge stroke used on non-Liquid-Glass platforms to keep
  /// material surfaces from melting into busy wallpapers.
  static let glassEdge = Color.white.opacity(0.22)

  /// Soft ambient shadow used for floating panels and controls.
  static let ambientShadow = Color.black.opacity(0.08)
}

private struct TokMonSelectionPillModifier: ViewModifier {
  let isSelected: Bool
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    if #available(macOS 26.0, *) {
      if isSelected {
        content
          .glassEffect(.regular.tint(TokMonGlass.accent), in: shape)
      } else {
        content
          .glassEffect(.regular, in: shape)
      }
    } else {
      content
        .background {
          shape.fill(isSelected ? TokMonGlass.accent.opacity(0.18) : Color.black.opacity(0.04))
        }
        .overlay {
          shape.strokeBorder(isSelected ? TokMonGlass.accent.opacity(0.28) : Color.black.opacity(0.08), lineWidth: 0.8)
        }
    }
  }
}

extension View {
  func tokMonSelectionPill(isSelected: Bool, cornerRadius: CGFloat = 7) -> some View {
    modifier(TokMonSelectionPillModifier(isSelected: isSelected, cornerRadius: cornerRadius))
  }

  @ViewBuilder
  func tokMonGlassButton(prominent: Bool = false) -> some View {
    if #available(macOS 26.0, *) {
      if prominent {
        buttonStyle(.glassProminent)
      } else {
        buttonStyle(.glass)
      }
    } else {
      if prominent {
        buttonStyle(.borderedProminent)
      } else {
        buttonStyle(.bordered)
      }
    }
  }
}
