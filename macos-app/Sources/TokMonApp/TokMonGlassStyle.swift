import SwiftUI

enum TokMonGlass {
  /// Deep sea teal — primary brand color for totals, selected states, and Claude Code.
  static let accent = Color(nsColor: NSColor(red: 0.031, green: 0.569, blue: 0.698, alpha: 1))

  /// Mint green — used for cost, cache hit rate, and Codex.
  static let success = Color(nsColor: NSColor(red: 0.063, green: 0.725, blue: 0.510, alpha: 1))

  /// Sky blue — used for cache-related series and OpenCode.
  static let warning = Color(nsColor: NSColor(red: 0.220, green: 0.740, blue: 0.970, alpha: 1))

  /// Rose coral — errors, zero/negative deltas, and Qwen Code.
  static let danger = Color(nsColor: NSColor(red: 0.957, green: 0.247, blue: 0.369, alpha: 1))

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
          .glassEffect(.regular.tint(TokMonGlass.accent.opacity(0.45)), in: shape)
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
