import UIKit

/// Light taps for keys and chips, success for saves and ticks, error for rejected input.
package enum Haptics {
  @MainActor package static func lightImpact() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }
  @MainActor package static func selection() {
    UISelectionFeedbackGenerator().selectionChanged()
  }
  @MainActor package static func success() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
  }
  @MainActor package static func error() {
    UINotificationFeedbackGenerator().notificationOccurred(.error)
  }
}
