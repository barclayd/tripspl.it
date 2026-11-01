import SwiftUI

/// A thin progress bar, used for trip progress and daily budgets.
public struct Meter: View {
  let value: Double
  let fill: Color
  let track: Color
  let height: CGFloat

  public init(value: Double, fill: Color = .white, track: Color, height: CGFloat = 5) {
    self.value = value
    self.fill = fill
    self.track = track
    self.height = height
  }

  public var body: some View {
    Capsule()
      .fill(track)
      .frame(height: height)
      .overlay(alignment: .leading) {
        GeometryReader { proxy in
          Capsule().fill(fill).frame(width: proxy.size.width * min(1, max(0, value)))
        }
      }
      .accessibilityElement()
      .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
  }
}
