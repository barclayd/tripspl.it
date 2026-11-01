import TripSplitDomain
import UIKit

package enum Haptics {
  @MainActor package static func lightImpact() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }
}
