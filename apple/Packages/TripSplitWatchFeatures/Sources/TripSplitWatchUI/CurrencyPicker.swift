import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign
import TripSplitWatchModel

/// C5 · All currencies. Quick chips for this trip, the next and recents, then a Crown wheel of
/// every currency. Tapping one chooses it and returns to the dial.
struct CurrencyPicker: View {
  let convert: QuickConvert
  let side: QuickConvert.Side
  @Environment(\.dismiss) private var dismiss
  @State private var selected: String?
  private static let rowHeight: CGFloat = 32

  init(convert: QuickConvert, side: QuickConvert.Side) {
    self.convert = convert
    self.side = side
    _selected = State(initialValue: convert.code(side))
  }

  var body: some View {
    let codes = convert.allCurrencies
    let index = selected.flatMap(codes.firstIndex(of:)) ?? 0
    VStack(spacing: 6) {
      Text(side == .from ? "Convert from" : "Convert to")
        .watchFont(12, .black)
        .foregroundStyle(WatchTheme.ink2)
        .accessibilityAddTraits(.isHeader)
      HStack(spacing: 5) {
        ForEach(convert.quickPicks(for: side), id: \.self) { code in
          let currency = convert.currency(code)
          Button {
            pick(code)
          } label: {
            HStack(spacing: 4) {
              Text(currency.flag).font(.system(size: 13))
              Text(currency.symbol).watchFont(12, .black)
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(WatchTheme.card, in: .capsule)
            .contentShape(.capsule)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(currency.name)
        }
      }
      // Margins of half the wheel let the first and last currencies reach the centre.
      GeometryReader { wheel in
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(Array(codes.enumerated()), id: \.element) { offset, code in
                row(code, distance: abs(offset - index))
              }
            }
            .scrollTargetLayout()
          }
          .scrollPosition(id: $selected, anchor: .center)
          .scrollTargetBehavior(.viewAligned)
          .scrollIndicators(.hidden)
          .contentMargins(
            .vertical, max((wheel.size.height - Self.rowHeight) / 2, 0), for: .scrollContent)
          // Centre on the current currency once the wheel knows its height.
          .onChange(of: wheel.size.height, initial: true) {
            proxy.scrollTo(convert.code(side), anchor: .center)
          }
        }
      }
    }
    .padding(.horizontal, 2)
    .ignoresSafeArea(edges: .bottom)
    .containerBackground(.black, for: .navigation)
  }

  private func row(_ code: String, distance: Int) -> some View {
    let currency = convert.currency(code)
    let other = convert.code(side.other)
    let isSelected = distance == 0
    return Button {
      pick(code)
    } label: {
      HStack(spacing: 8) {
        Text(currency.flag).font(.system(size: isSelected ? 24 : 14))
        if isSelected {
          VStack(alignment: .leading, spacing: 0) {
            Text(currency.label).watchFont(16, .black)
            Text(currency.name).watchFont(10, .bold).foregroundStyle(WatchTheme.ink2)
          }
          Spacer(minLength: 4)
          if code != other, let rate = convert.rateText(from: other, to: code, separator: "=") {
            Text(rate)
              .watchFont(10, .heavy)
              .foregroundStyle(WatchTheme.accentText)
              .padding(.horizontal, 8)
              .frame(height: 34)
              .background(.black.opacity(0.4), in: .capsule)
          }
        } else {
          Text(currency.label).watchFont(13, .black).foregroundStyle(WatchTheme.ink2)
        }
      }
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .padding(.leading, isSelected ? 12 : 0)
      .padding(.trailing, isSelected ? 6 : 0)
      .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight)
      .background {
        if isSelected {
          Capsule()
            .fill(WatchTheme.card)
            .strokeBorder(WatchTheme.accentText, lineWidth: 2)
            .frame(height: 46)
        }
      }
      .contentShape(.rect)
      .opacity(distance == 0 ? 1 : distance == 1 ? 0.6 : distance == 2 ? 0.35 : 0.2)
      .scaleEffect(distance == 0 ? 1 : distance == 1 ? 0.94 : 0.88)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(currency.name)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func pick(_ code: String) {
    convert.choose(code, for: side)
    convert.focus = nil
    dismiss()
  }
}
