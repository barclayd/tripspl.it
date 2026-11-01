import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitPersistence
import TripSplitSync

package struct NumberPad: View {
  package init(value: Binding<String>, currency: String) {
    self._value = value
    self.currency = currency
  }
  @Binding var value: String
  package var currency: String
  private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]
  package var body: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
      ForEach(keys, id: \.self) { key in
        Button {
          input(key)
        } label: {
          Text(key).font(.system(size: 24, weight: .semibold, design: .default)).frame(
            maxWidth: .infinity
          ).frame(height: 48).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).disabled(key == "." && Money.precision(currency) == 0)
          .accessibilityLabel(key == "⌫" ? "Delete digit" : key == "." ? "Decimal point" : key)
      }
    }
  }
  private func input(_ key: String) {
    if key == "⌫" {
      if !value.isEmpty { value.removeLast() }
      return
    }
    if key == "." {
      if !value.contains(".") { value += value.isEmpty ? "0." : "." }
      return
    }
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    if parts.count == 2 && parts[1].count >= Money.precision(currency) { return }
    if parts.count < 2 && value.count >= 9 { return }
    value = value == "0" ? key : value + key
  }
}
