import SwiftUI

enum TokMonMotion {
  static let smoothSpring = Animation.spring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.08)
  static let gentleSpring = Animation.spring(response: 0.50, dampingFraction: 0.90, blendDuration: 0.12)
  static let softSnappySpring = Animation.spring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.06)
}

extension AnyTransition {
  static var tokMonPanelDrilldown: AnyTransition {
    .asymmetric(
      insertion: .move(edge: .trailing).combined(with: .opacity),
      removal: .move(edge: .trailing).combined(with: .opacity),
    )
  }

  static var tokMonTokenDetailGrid: AnyTransition {
    .asymmetric(
      insertion: .move(edge: .trailing).combined(with: .opacity),
      removal: .move(edge: .trailing).combined(with: .opacity),
    )
  }

  static var tokMonMetricGrid: AnyTransition {
    .asymmetric(
      insertion: .scale(scale: 0.985).combined(with: .opacity),
      removal: .scale(scale: 0.985).combined(with: .opacity),
    )
  }

  static var tokMonSupportingMetrics: AnyTransition {
    .asymmetric(
      insertion: .move(edge: .top).combined(with: .opacity),
      removal: .move(edge: .top).combined(with: .opacity),
    )
  }
}
