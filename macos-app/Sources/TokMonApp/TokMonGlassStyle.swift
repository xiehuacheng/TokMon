import SwiftUI

enum TokMonGlass {
  /// Dark slate — primary brand color for totals, selected states, and Claude Code.
  /// Automatically lightens in Dark Mode to keep text and selections readable.
  static let accent = dynamicColor(
    light: NSColor(red: 0.200, green: 0.255, blue: 0.333, alpha: 1),
    dark: NSColor(red: 0.620, green: 0.700, blue: 0.850, alpha: 1)
  )

  /// Steel blue-gray — used for cost, cache hit rate series.
  static let success = dynamicColor(
    light: NSColor(red: 0.278, green: 0.333, blue: 0.412, alpha: 1),
    dark: NSColor(red: 0.620, green: 0.700, blue: 0.800, alpha: 1)
  )

  /// Desaturated teal-green — distinct source color for Codex.
  static let codexTeal = Color(nsColor: NSColor(red: 0.280, green: 0.520, blue: 0.460, alpha: 1))

  /// Silver gray — used for cache-related series.
  static let warning = dynamicColor(
    light: NSColor(red: 0.580, green: 0.639, blue: 0.722, alpha: 1),
    dark: NSColor(red: 0.720, green: 0.760, blue: 0.820, alpha: 1)
  )

  /// Warm amber-orange — distinct source color for OpenCode.
  static let opencodeAmber = Color(nsColor: NSColor(red: 0.780, green: 0.480, blue: 0.180, alpha: 1))

  /// Violet purple — distinct source color for Kimi Code.
  static let kimiPurple = Color(nsColor: NSColor(red: 0.550, green: 0.300, blue: 0.750, alpha: 1))

  /// Deep rose — errors, zero/negative deltas, and Qwen Code.
  static let danger = Color(nsColor: NSColor(red: 0.624, green: 0.071, blue: 0.224, alpha: 1))

  /// Subtle glass edge stroke used on non-Liquid-Glass platforms to keep
  /// material surfaces from melting into busy wallpapers.
  static let glassEdge = Color.white.opacity(0.10)

  /// Soft ambient shadow used for floating panels and controls.
  static let ambientShadow = Color.black.opacity(0.08)

  /// Outer page card background: light translucent white / dark translucent black.
  static let cardBackgroundOuter = dynamicColor(
    light: NSColor(white: 1.0, alpha: 0.12),
    dark: NSColor(white: 0.0, alpha: 0.34)
  )

  /// Inner overview card background.
  static let cardBackgroundInner = dynamicColor(
    light: NSColor(white: 1.0, alpha: 0.28),
    dark: NSColor(white: 0.0, alpha: 0.22)
  )

  /// Inner overview card background hover state.
  static let cardBackgroundInnerHover = dynamicColor(
    light: NSColor(white: 1.0, alpha: 0.36),
    dark: NSColor(white: 0.0, alpha: 0.30)
  )

  /// Inner overview card background press state.
  static let cardBackgroundInnerPress = dynamicColor(
    light: NSColor(white: 1.0, alpha: 0.44),
    dark: NSColor(white: 0.0, alpha: 0.38)
  )

  /// Request/Session row idle background.
  static let cardRowIdle = dynamicColor(
    light: NSColor(white: 1.0, alpha: 0.44),
    dark: NSColor(white: 0.0, alpha: 0.24)
  )

  /// Request/Session row hover background.
  static let cardRowHover = dynamicColor(
    light: NSColor(white: 1.0, alpha: 0.52),
    dark: NSColor(white: 0.0, alpha: 0.32)
  )

  /// Request/Session row press background.
  static let cardRowPress = dynamicColor(
    light: NSColor(white: 1.0, alpha: 0.60),
    dark: NSColor(white: 0.0, alpha: 0.40)
  )

  /// Selected tile/row accent background idle.
  static let accentTileIdle = dynamicColor(
    light: NSColor(red: 0.200, green: 0.255, blue: 0.333, alpha: 0.18),
    dark: NSColor(red: 0.620, green: 0.700, blue: 0.850, alpha: 0.08)
  )

  /// Selected tile/row accent background hover.
  static let accentTileHover = dynamicColor(
    light: NSColor(red: 0.200, green: 0.255, blue: 0.333, alpha: 0.24),
    dark: NSColor(red: 0.620, green: 0.700, blue: 0.850, alpha: 0.12)
  )

  /// Selected tile/row accent background press.
  static let accentTilePress = dynamicColor(
    light: NSColor(red: 0.200, green: 0.255, blue: 0.333, alpha: 0.30),
    dark: NSColor(red: 0.620, green: 0.700, blue: 0.850, alpha: 0.18)
  )

  /// Card border: stronger in light mode, subtle in dark mode.
  static let cardBorder = dynamicColor(
    light: NSColor(white: 1.0, alpha: 0.40),
    dark: NSColor(white: 1.0, alpha: 0.08)
  )

  private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
      if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
        return dark
      }
      return light
    }))
  }
}

private struct TokMonSelectionPillModifier: ViewModifier {
  let isSelected: Bool
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    if #available(macOS 26.0, *) {
      if isSelected {
        content
          .glassEffect(.regular.tint(TokMonGlass.accent.opacity(0.55)), in: shape)
      } else {
        content
          .glassEffect(.regular, in: shape)
      }
    } else {
      content
        .background {
          shape.fill(isSelected ? TokMonGlass.accent.opacity(0.28) : Color.black.opacity(0.04))
        }
        .overlay {
          shape.strokeBorder(isSelected ? TokMonGlass.accent.opacity(0.45) : Color.black.opacity(0.08), lineWidth: 0.8)
        }
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
  }
}

private struct TokMonFallbackGlassButtonBody: View {
  let configuration: ButtonStyleConfiguration
  let prominent: Bool
  @State private var isHovered = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    let tintOpacity = prominent
      ? (configuration.isPressed ? 0.30 : isHovered ? 0.24 : 0.18)
      : (configuration.isPressed ? 0.10 : isHovered ? 0.07 : 0.04)

    configuration.label
      .font(.system(size: 12, weight: .semibold, design: .rounded))
      .foregroundStyle(prominent ? TokMonGlass.accent : .primary)
      .padding(.horizontal, 14)
      .padding(.vertical, 6)
      .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
      .background {
        shape.fill(.thinMaterial)
      }
      .overlay {
        shape.fill((prominent ? TokMonGlass.accent : TokMonGlass.cardBackgroundInner).opacity(tintOpacity))
      }
      .overlay {
        shape.strokeBorder(
          prominent ? TokMonGlass.accent.opacity(configuration.isPressed ? 0.58 : 0.42) : TokMonGlass.cardBorder,
          lineWidth: 1
        )
      }
      .shadow(color: TokMonGlass.ambientShadow, radius: prominent ? 9 : 6, y: prominent ? 4 : 2)
      .onHover { hovering in
        isHovered = hovering
      }
  }
}

private struct TokMonFallbackGlassButtonStyle: ButtonStyle {
  let prominent: Bool

  func makeBody(configuration: Configuration) -> some View {
    TokMonFallbackGlassButtonBody(configuration: configuration, prominent: prominent)
  }
}

private struct TokMonScrollEdgeFadeModifier: ViewModifier {
  let top: CGFloat
  let bottom: CGFloat

  func body(content: Content) -> some View {
    content
      .mask(alignment: .top) {
        VStack(spacing: 0) {
          LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
            .frame(height: top)
          Color.black
          LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
            .frame(height: bottom)
        }
      }
  }
}

extension View {
  func tokMonSelectionPill(isSelected: Bool, cornerRadius: CGFloat = 7) -> some View {
    modifier(TokMonSelectionPillModifier(isSelected: isSelected, cornerRadius: cornerRadius))
  }

  func tokMonScrollEdgeFade(top: CGFloat = 14, bottom: CGFloat = 14) -> some View {
    modifier(TokMonScrollEdgeFadeModifier(top: top, bottom: bottom))
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
      buttonStyle(TokMonFallbackGlassButtonStyle(prominent: prominent))
    }
  }
}

extension TokMonSourceColor {
  var swiftUIColor: Color {
    Color(red: red, green: green, blue: blue, opacity: alpha)
  }

  init(color: Color) {
    let nsColor = NSColor(color)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    nsColor.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
    self.init(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
  }
}

func colorForSource(_ source: String, colors: [String: TokMonSourceColor]) -> Color {
  colors[source]?.swiftUIColor ?? .secondary
}
