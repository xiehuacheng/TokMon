import SwiftUI

enum TokMonGlass {
  static let accent = Color(nsColor: NSColor(red: 0.20, green: 0.47, blue: 0.86, alpha: 1))
  static let success = Color(nsColor: NSColor(red: 0.24, green: 0.59, blue: 0.39, alpha: 1))
  static let warning = Color(nsColor: NSColor(red: 0.78, green: 0.59, blue: 0.16, alpha: 1))
  static let danger = Color(nsColor: NSColor(red: 0.78, green: 0.27, blue: 0.29, alpha: 1))

  static let glassEdge = Color.white.opacity(0.22)
  static let ambientShadow = Color.black.opacity(0.08)
}

struct TokMonMaterialSurface: ViewModifier {
  let material: Material
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    content
      .background {
        shape
          .fill(material)
      }
      .clipShape(shape)
      .overlay {
        shape.strokeBorder(TokMonGlass.glassEdge, lineWidth: 1)
      }
      .shadow(
        color: TokMonGlass.ambientShadow,
        radius: 8,
        y: 4
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
        shape.fill(isSelected ? TokMonGlass.accent.opacity(0.18) : Color.black.opacity(0.04))
      }
      .overlay {
        shape.strokeBorder(isSelected ? TokMonGlass.accent.opacity(0.28) : Color.black.opacity(0.08), lineWidth: 0.8)
      }
  }
}

extension View {
  func tokMonShell(cornerRadius: CGFloat = 30) -> some View {
    modifier(TokMonMaterialSurface(material: .ultraThin, cornerRadius: cornerRadius))
  }

  func tokMonCard(cornerRadius: CGFloat = 16) -> some View {
    modifier(TokMonMaterialSurface(material: .thin, cornerRadius: cornerRadius))
  }

  func tokMonControl(cornerRadius: CGFloat = 11) -> some View {
    modifier(TokMonMaterialSurface(material: .regular, cornerRadius: cornerRadius))
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
