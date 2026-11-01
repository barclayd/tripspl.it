import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign
import TripSplitWatchModel

/// C2 · Type it. A keypad for exact amounts, with the result live above. The Crown still dials.
struct ConvertKeypad: View {
  @Bindable var convert: QuickConvert

  var body: some View {
    AmountKeypad(
      code: convert.pair.from, currency: convert.currency(convert.pair.from),
      result: convert.result.map { WatchCurrency.format($0, convert.pair.to) } ?? "—",
      amount: $convert.amount, detent: convert.amountDetent, detents: AmountLadder.count,
      dial: convert.dial(to:))
  }
}

/// A keypad for exact amounts, with the entry and what it comes to above. The Crown still dials,
/// in the same detents as the screen it came from.
struct AmountKeypad: View {
  let code: String
  let currency: WatchCurrency
  /// What the amount comes to, in pink beside it, or nil to show the entry alone.
  let result: String?
  @Binding var amount: Decimal
  let detent: Int
  let detents: Int
  let dial: (Int) -> Void
  @State private var entry = ""
  /// The next digit replaces the amount rather than appending to it.
  @State private var fresh = true
  @State private var crown = 0.0
  @FocusState private var crownFocused: Bool

  private static let keys = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "⌫"]]

  var body: some View {
    VStack(spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(currency.symbol == currency.code ? "\(currency.code) \(entry)" : currency.symbol + entry)
          .watchFont(26, .black)
          .contentTransition(.numericText())
        if let result {
          Text(result)
            .watchFont(17, .black)
            .foregroundStyle(WatchTheme.accentText)
            .contentTransition(.numericText())
        }
      }
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .layoutPriority(1)
      .accessibilityElement(children: .combine)
      Grid(horizontalSpacing: 5, verticalSpacing: 4) {
        ForEach(Self.keys, id: \.self) { row in
          GridRow {
            ForEach(row, id: \.self) { key in
              Button {
                press(key)
              } label: {
                label(key)
              }
              .buttonStyle(KeyStyle())
              .disabled(key == "." && Money.precision(code) == 0)
            }
          }
        }
      }
    }
    .padding(.horizontal, 4)
    .containerBackground(.black, for: .navigation)
    .focusable()
    .focused($crownFocused)
    .focusEffectDisabled()
    .digitalCrownRotation(
      detent: $crown, from: 0, through: Double(detents - 1), by: 1,
      sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true
    )
    .onChange(of: crown) { _, value in
      let turned = Int(value.rounded())
      guard turned != detent else { return }
      dial(turned)
      entry = Self.plain(amount)
      fresh = true
    }
    .onChange(of: detent) { _, detent in
      if crown != Double(detent) { crown = Double(detent) }
    }
    .onAppear {
      entry = Self.plain(amount)
      crown = Double(detent)
      crownFocused = true
    }
  }

  @ViewBuilder private func label(_ key: String) -> some View {
    if key == "⌫" {
      Image(systemName: "delete.left").font(.system(size: 17, weight: .bold))
        .accessibilityLabel("Delete")
    } else {
      Text(key).watchFont(18, .heavy)
    }
  }

  private func press(_ key: String) {
    let precision = Money.precision(code)
    switch key {
    case "⌫":
      entry = String(entry.dropLast())
      if entry.isEmpty { entry = "0" }
    case ".":
      if fresh {
        entry = "0."
      } else if !entry.contains(".") {
        entry += "."
      }
    default:
      if fresh || entry == "0" {
        entry = key
      } else if let dot = entry.firstIndex(of: ".") {
        guard entry[dot...].count <= precision else { return }
        entry += key
      } else {
        guard entry.count < 7 else { return }
        entry += key
      }
    }
    fresh = false
    withAnimation(.snappy) {
      amount = Decimal(string: entry, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }
  }

  private static func plain(_ amount: Decimal) -> String {
    NSDecimalNumber(decimal: amount).stringValue
  }
}

/// A keypad key on the card fill, up to 38pt tall.
struct KeyStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 38)
      .background(WatchTheme.card, in: .rect(cornerRadius: 12))
      .contentShape(.rect(cornerRadius: 12))
      .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.3)
  }
}
