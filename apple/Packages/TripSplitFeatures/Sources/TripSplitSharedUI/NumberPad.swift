import SwiftUI
import TripSplitDesignSystem
import TripSplitDomain

/// A plain three-column keypad that types an amount in a currency's precision.
package struct NumberPad: View {
  package init(
    value: Binding<String>, currency: String, keyHeight: CGFloat = 48, spacing: CGFloat = 8
  ) {
    self._value = value
    self.currency = currency
    self.keyHeight = keyHeight
    self.spacing = spacing
  }
  @Binding var value: String
  package var currency: String
  package var keyHeight: CGFloat
  package var spacing: CGFloat
  @State private var rejected = 0

  private static let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]

  package var body: some View {
    let decimals = Money.precision(currency) > 0
    Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
      ForEach(0..<4, id: \.self) { row in
        GridRow {
          ForEach(Self.keys[(row * 3)..<(row * 3 + 3)], id: \.self) { key in
            if key == "." && !decimals {
              Color.clear.frame(height: keyHeight).accessibilityHidden(true)
            } else {
              Button {
                input(key)
              } label: {
                Group {
                  if key == "⌫" {
                    Image(systemName: "delete.left").font(.system(size: 21, weight: .bold))
                  } else {
                    Text(key).font(.system(size: keyHeight > 50 ? 25 : 24, weight: .bold))
                  }
                }
                .frame(maxWidth: .infinity).frame(height: keyHeight)
              }
              .buttonStyle(KeyStyle())
              .accessibilityLabel(
                key == "⌫" ? "Delete digit" : key == "." ? "Decimal point" : key)
            }
          }
        }
      }
    }
    .shake(on: rejected)
  }

  private func input(_ key: String) {
    guard let next = Self.next(value, key: key, precision: Money.precision(currency)) else {
      rejected += 1
      Haptics.error()
      return
    }
    Haptics.lightImpact()
    value = next
  }

  /// The amount after pressing `key`, or nil when the key is refused.
  package static func next(_ value: String, key: String, precision: Int) -> String? {
    if key == "⌫" { return String(value.dropLast()) }
    if key == "." {
      if precision == 0 || value.contains(".") { return nil }
      return (value.isEmpty ? "0" : value) + "."
    }
    let current = value == "0" ? "" : value
    let parts = current.split(separator: ".", omittingEmptySubsequences: false)
    if parts.count == 2 && parts[1].count >= precision { return nil }
    if parts.count < 2 && current.count >= 7 { return nil }
    return current + key
  }
}

private struct KeyStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(Theme.ink)
      .background(
        configuration.isPressed ? Theme.inset : .clear,
        in: RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
      )
      .scaleEffect(configuration.isPressed ? 0.92 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
      .contentShape(Rectangle())
  }
}
