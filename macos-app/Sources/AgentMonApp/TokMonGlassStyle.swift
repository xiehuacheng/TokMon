import SwiftUI

enum TokMonGlass {
  static let accent = Color(nsColor: NSColor(red: 0.64, green: 0.82, blue: 1.0, alpha: 1))
  static let success = Color(nsColor: NSColor(red: 0.58, green: 0.78, blue: 0.66, alpha: 1))
  static let warning = Color(nsColor: NSColor(red: 0.86, green: 0.74, blue: 0.48, alpha: 1))
  static let danger = Color(nsColor: NSColor(red: 0.88, green: 0.50, blue: 0.52, alpha: 1))
  static let neutralTint = Color.white.opacity(0.86)
  static let mutedTint = Color.white.opacity(0.52)
  static let border = Color.white.opacity(0.12)
  static let strongBorder = Color.white.opacity(0.20)
  static let quietFill = Color.white.opacity(0.045)
  static let selectedFill = Color.white.opacity(0.10)
  static let hudCardFill = Color.black.opacity(0.13)
  static let hudCardStroke = Color.white.opacity(0.085)
  static let hudRailFill = Color.black.opacity(0.13)
  static let chartFill = Color.black.opacity(0.12)
  static let chartGrid = Color.white.opacity(0.075)
}

struct TokMonLiquidGlassScene<Content: View>: View {
  @ViewBuilder let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .preferredColorScheme(.dark)
  }
}

private struct TokMonTranslucentSurfaceModifier: ViewModifier {
  let cornerRadius: CGFloat
  let prominence: Double
  let tint: Color?

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    let baseOpacity = 0.18 + prominence * 0.06
    let highlightOpacity = 0.05 + prominence * 0.045
    let borderOpacity = 0.10 + prominence * 0.055

    content
      .background {
        shape
          .fill(Color.black.opacity(baseOpacity))
          .overlay {
            LinearGradient(
              colors: [
                Color.white.opacity(highlightOpacity),
                (tint ?? Color.white).opacity(0.014 + prominence * 0.016),
                Color.black.opacity(0.025),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing,
            )
            .clipShape(shape)
          }
      }
      .clipShape(shape)
      .overlay {
        shape.strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 0.8)
      }
      .shadow(
        color: Color.black.opacity(0.12 + prominence * 0.05),
        radius: CGFloat(7 + prominence * 6),
        y: CGFloat(4 + prominence * 4),
      )
  }
}

private struct TokMonSelectionPillModifier: ViewModifier {
  let isSelected: Bool
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    content
      .background {
        shape.fill(isSelected ? TokMonGlass.accent.opacity(0.24) : Color.white.opacity(0.035))
      }
      .overlay {
        shape.strokeBorder(isSelected ? TokMonGlass.accent.opacity(0.44) : Color.white.opacity(0.055), lineWidth: 0.8)
      }
  }
}

extension View {
  func tokMonGlassPanel(
    cornerRadius: CGFloat = 14,
    prominence: Double = 0.72,
    tint: Color? = nil,
    interactive: Bool = false,
  ) -> some View {
    modifier(TokMonTranslucentSurfaceModifier(
      cornerRadius: cornerRadius,
      prominence: prominence,
      tint: tint,
    ))
  }

  func tokMonGlassRow(
    cornerRadius: CGFloat = 11,
    prominence: Double = 0.36,
    tint: Color? = nil,
    interactive: Bool = false,
  ) -> some View {
    modifier(TokMonTranslucentSurfaceModifier(
      cornerRadius: cornerRadius,
      prominence: prominence,
      tint: tint,
    ))
  }

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
