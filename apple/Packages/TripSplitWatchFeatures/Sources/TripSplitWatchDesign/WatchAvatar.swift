import SwiftUI
import TripSplitDomain

/// A traveller's initial on their colour. You are always a white "Y" on the accent.
public struct WatchAvatar: View {
  let traveller: Traveller
  let isYou: Bool
  let size: CGFloat

  public init(_ traveller: Traveller, isYou: Bool, size: CGFloat) {
    self.traveller = traveller
    self.isYou = isYou
    self.size = size
  }

  public var body: some View {
    Text(isYou ? "Y" : traveller.name.prefix(1).uppercased())
      .font(.system(size: size * 0.44, weight: .black, design: .rounded))
      .foregroundStyle(isYou ? .white : Color(hex: 0x16120F))
      .frame(width: size, height: size)
      .background(traveller.colour(isYou: isYou), in: .circle)
      .accessibilityHidden(true)
  }
}

extension Traveller {
  /// The radial wash behind a person's page: their hue, dark, fading to black.
  public func wash(isYou: Bool) -> RadialGradient {
    RadialGradient(
      colors: [isYou ? WatchTheme.tint : Color(oklch: 0.32, 0.07, hue), .black],
      center: .top, startRadius: 0, endRadius: 190)
  }
}

extension WatchTheme {
  /// The pink wash behind Today, from the top of the screen.
  public static let wash = RadialGradient(
    colors: [tint, .black], center: .top, startRadius: 0, endRadius: 190)
}
