import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign
import TripSplitWatchModel

/// Quick convert, presented as a sheet: the Crown dials an amount between today's stop currency
/// and home (C1), or changes a currency once its pill is tapped (C4).
public struct QuickConvertView: View {
  @State private var convert: QuickConvert
  @State private var path: [ConvertRoute] = []

  public init(model: WatchModel) {
    _convert = State(initialValue: QuickConvert(model: model))
  }

  public var body: some View {
    NavigationStack(path: $path) {
      ConvertDial(convert: convert, path: $path)
        .navigationDestination(for: ConvertRoute.self) { route in
          switch route {
          case .keypad: ConvertKeypad(convert: convert)
          case .picker(let side): CurrencyPicker(convert: convert, side: side)
          }
        }
    }
    // Toolbar buttons sit on the card fill rather than the accent, as in the design.
    .tint(WatchTheme.card2)
    .task(id: convert.pair) { await convert.loadRateIfNeeded() }
  }
}

enum ConvertRoute: Hashable {
  case keypad
  case picker(QuickConvert.Side)
}

/// C1 · Dial it. Pills, the amount, the result and the rate, with swap and keypad below.
struct ConvertDial: View {
  let convert: QuickConvert
  @Binding var path: [ConvertRoute]
  @State private var crown = 0.0
  @State private var pulse: QuickConvert.Side?
  @FocusState private var crownFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        pill(.from)
        Image(systemName: "arrow.right")
          .font(.system(size: 11, weight: .heavy))
          .foregroundStyle(WatchTheme.ink3)
          .accessibilityHidden(true)
        pill(.to)
      }
      .frame(height: 28)
      amount.padding(.top, 2)
      Spacer(minLength: 0)
    }
    .padding(.top, -8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    // The rate line may pass between the corner buttons, so the amount never shrinks for them.
    .ignoresSafeArea(edges: .bottom)
    .focusable()
    .focused($crownFocused)
    .focusEffectDisabled()
    .digitalCrownRotation(
      detent: $crown, from: 0, through: Double(crownStops - 1), by: 1, sensitivity: .medium,
      isContinuous: false, isHapticFeedbackEnabled: true
    )
    .onChange(of: crown) { _, value in turned(to: Int(value.rounded())) }
    .onChange(of: convert.focus) { syncCrown() }
    .onChange(of: convert.amountDetent) { syncCrown() }
    .onChange(of: convert.changed) { _, change in
      if let change, change.side != convert.focus { flash(change.side) }
    }
    .onAppear {
      syncCrown()
      crownFocused = true
    }
    .toolbar { bottomBar }
    .containerBackground(.black, for: .navigation)
  }

  private var amount: some View {
    let result = convert.result
    let from = WatchCurrency.format(convert.amountMinor, convert.pair.from, compact: true)
    let to = result.map { WatchCurrency.format($0, convert.pair.to) }
    return Button(action: tapAmount) {
      VStack(spacing: 0) {
        Text(from)
          .watchFont(50, .black)
          .tracking(em: -0.02, size: 50)
          .contentTransition(.numericText(value: Double(convert.amountMinor)))
        Text(to ?? "—")
          .watchFont(30, .black)
          .foregroundStyle(WatchTheme.accentText)
          .contentTransition(.numericText(value: Double(result ?? 0)))
        Text(convert.rateLine ?? "No rate yet")
          .watchFont(11, .bold)
          .foregroundStyle(WatchTheme.ink3)
          .padding(.top, 3)
      }
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .frame(maxWidth: .infinity)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(to.map { "\(from) is about \($0)" } ?? from)
    .accessibilityHint(
      convert.focus == nil ? "Turn the Digital Crown to change, or double tap to type" : "")
  }

  private func pill(_ side: QuickConvert.Side) -> some View {
    let currency = convert.currency(convert.code(side))
    return Button {
      tapPill(side)
    } label: {
      CurrencyPill(
        currency: currency, isTarget: side == .to, focused: convert.focus == side,
        pulsing: pulse == side)
    }
    .buttonStyle(.plain)
    .simultaneousGesture(LongPressGesture().onEnded { _ in path.append(.picker(side)) })
    .accessibilityLabel("\(side == .from ? "From" : "To") \(currency.name)")
    .accessibilityHint("Double tap, then turn the Digital Crown to change currency")
  }

  @ToolbarContentBuilder private var bottomBar: some ToolbarContent {
    // While the Crown changes a currency, nothing else is on screen (C4).
    ToolbarItemGroup(placement: .bottomBar) {
      if convert.focus == nil { actions }
    }
  }

  /// Swap fills pink once the pair runs home → local (C3); a custom pair offers "Reset to trip" (C6).
  @ViewBuilder private var actions: some View {
    let swap = Button {
      withAnimation(.snappy) { convert.swap() }
    } label: {
      Image(systemName: "arrow.up.arrow.down")
    }
    .accessibilityLabel("Swap currencies")
    swap.tint(convert.isFlipped ? WatchTheme.accent : WatchTheme.card2)
    Spacer()
    if convert.isCustom {
      Button("Reset to trip") {
        withAnimation(.snappy) { convert.resetToTrip() }
      }
      .watchFont(13, .heavy)
      .foregroundStyle(WatchTheme.ink2)
    } else {
      Button {
        path.append(.keypad)
      } label: {
        Image(systemName: "circle.grid.3x3.fill")
      }
      .accessibilityLabel("Type an amount")
    }
  }

  /// Amount detents, or the focused currency's stops ending at "All currencies…".
  private var crownStops: Int {
    convert.focus == nil ? AmountLadder.count : max(convert.cycleItems.count, 1)
  }

  private func turned(to detent: Int) {
    guard let side = convert.focus else {
      if detent != convert.amountDetent { withAnimation(.snappy) { convert.dial(to: detent) } }
      return
    }
    if withAnimation(.snappy, { convert.turn(to: detent) }) {
      crown = Double(convert.cycleDetent)
      path.append(.picker(side))
    }
  }

  private func syncCrown() {
    let detent = Double(convert.focus == nil ? convert.amountDetent : convert.cycleDetent)
    if crown != detent { crown = detent }
  }

  private func tapPill(_ side: QuickConvert.Side) {
    if convert.focus == side {
      path.append(.picker(side))
    } else {
      withAnimation(.snappy) { convert.focus = side }
    }
  }

  private func tapAmount() {
    if convert.focus != nil {
      withAnimation(.snappy) { convert.focus = nil }
    } else {
      path.append(.keypad)
    }
  }

  /// The changed pill pulses pink once (C6).
  private func flash(_ side: QuickConvert.Side) {
    withAnimation(.easeIn(duration: 0.15)) { pulse = side }
    Task {
      try? await Task.sleep(for: .milliseconds(450))
      withAnimation(.easeOut(duration: 0.6)) { if pulse == side { pulse = nil } }
    }
  }
}

/// A currency pill: flag and symbol, pink for the target currency. Focused for the Crown, it
/// grows onto the accent tint with a pink ring (C4).
struct CurrencyPill: View {
  let currency: WatchCurrency
  let isTarget: Bool
  let focused: Bool
  let pulsing: Bool

  var body: some View {
    HStack(spacing: 4) {
      Text(currency.flag).font(.system(size: focused ? 16 : 13))
      Text(currency.symbol)
        .watchFont(focused ? 14 : 12, .black)
        .foregroundStyle(isTarget ? WatchTheme.accentText : .white)
      if !focused {
        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .black))
          .foregroundStyle(WatchTheme.ink2)
      }
    }
    .lineLimit(1)
    .fixedSize()
    .padding(.horizontal, focused ? 10 : 8)
    .frame(height: focused ? 28 : 24)
    .background(focused || pulsing ? WatchTheme.tint : WatchTheme.card, in: .capsule)
    .overlay {
      Capsule().strokeBorder(
        WatchTheme.accentText, lineWidth: focused ? 2 : pulsing ? 1.5 : 0)
    }
    .contentShape(.capsule)
  }
}
