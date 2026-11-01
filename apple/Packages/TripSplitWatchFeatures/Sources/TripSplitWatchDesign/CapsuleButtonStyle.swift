import SwiftUI

/// A neutral raised capsule, as used for secondary actions such as "Open on iPhone".
public struct CapsuleButtonStyle: ButtonStyle {
  var fill: Color

  public init(fill: Color = WatchTheme.card2) {
    self.fill = fill
  }

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.white)
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 40)
      .background(fill, in: .capsule)
      .contentShape(.capsule)
      .opacity(configuration.isPressed ? 0.7 : 1)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.snappy(duration: 0.15), value: configuration.isPressed)
  }
}

extension ButtonStyle where Self == CapsuleButtonStyle {
  public static var capsule: CapsuleButtonStyle { .init() }
}
