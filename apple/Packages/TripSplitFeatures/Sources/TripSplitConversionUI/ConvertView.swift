import SwiftUI
import TripSplitApplication
import TripSplitConversion
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitNetworking
import TripSplitSharedUI
import TripSplitSync

/// Quick convert: type a price you can see, read it back in the other currency and against a
/// day's budget, then hand it off as a new expense for that day.
public struct ConvertView: View {
  public init(tripID: String, attachment: Attachment) {
    self.tripID = tripID
    self.attachment = attachment
  }
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.horizontalSizeClass) private var sizeClass
  var tripID: String
  var attachment: Attachment
  @State private var conversion: ConversionModel?
  @State private var picking: ConversionSide?
  @State private var size = CGSize.zero
  private var wide: Bool { size.width >= 590 }
  /// Tent: compact width but wider than tall, read from arm's length on a counter.
  private var tent: Bool { sizeClass == .compact && size.width > size.height }
  @State private var verticalRail = false
  @State private var swapTurns = 0.0
  @State private var handingOff = false
  @FocusState private var rateFocused: Bool

  public var body: some View {
    if let trip = app.store.trip(tripID) {
      NavigationStack {
        Group {
          if let conversion {
            content(conversion, trip: trip)
          } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
        .background(Theme.surface)
        // The tent reads from arm's length, so the rail carries the controls and no title.
        .navigationTitle(tent ? "" : "Quick convert")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(verticalRail ? .automatic : .hidden, for: .navigationBar)
        .toolbar {
          if verticalRail {
            ToolbarItem(placement: .cancellationAction) {
              Button("Close", systemImage: "xmark") { close() }
            }
            if let conversion {
              ToolbarItem(placement: .confirmationAction) {
                Button("Log as expense", systemImage: tent ? "checkmark" : "plus") {
                  logExpense(conversion, trip: trip)
                }
                .disabled(!conversion.canLogExpense(homeCurrency: trip.homeCurrency) || handingOff)
                .accessibilityIdentifier("converter.log")
              }
            }
          }
        }
        .sheet(item: $picking) { side in
          if let conversion {
            ConversionCurrencyPicker(
              title: side.title, selection: side == .from ? conversion.from : conversion.to
            ) { choice in
              conversion.select(choice, for: side)
            }
          }
        }
      }
      .task {
        // A nested picker may cause this task to run again; the open session owns its choices.
        guard conversion == nil else { return }
        let defaults = trip.conversionDefaults(on: trip.date(for: attachment))
        let api = app.sync.api
        let state = ConversionModel(
          from: defaults.from, to: defaults.to, date: trip.date(for: attachment)
        ) { from, to, date in
          try await api.quote(from: from, to: to, date: date, token: nil)
        }
        state.amount = ""
        conversion = state
        state.start()
        #if DEBUG
          // `--convert-amount 24.5` and `--convert-swap` reach a typed or swapped sheet.
          let arguments = ProcessInfo.processInfo.arguments
          if let index = arguments.firstIndex(of: "--convert-amount"), arguments.indices.contains(index + 1) {
            state.amount = arguments[index + 1]
          }
          if arguments.contains("--convert-swap") { state.swap() }
        #endif
      }
      .readVerticalRail($verticalRail)
      .taskRail()
      .presentationDragIndicator(.visible)
      .presentationBackground(Theme.surface)
      .presentationCornerRadius(Theme.Radius.sheet)
    }
  }

  // MARK: - Layout

  private func content(_ conversion: ConversionModel, trip: TripSnapshot) -> some View {
    @Bindable var conversion = conversion
    let keypad = NumberPad(
      value: $conversion.amount, currency: conversion.from.code, keyHeight: 48, spacing: 4)
    return VStack(spacing: 0) {
      if tent {
        tentContent(conversion, trip: trip)
      } else {
        if !verticalRail { header.padding(.horizontal, 18) }
        regularContent(conversion, trip: trip, keypad: keypad)
      }
    }
    .padding(.bottom, 4)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .scrollDismissesKeyboard(.interactively)
    .onGeometryChange(for: CGSize.self) {
      $0.size
    } action: {
      size = $0
    }
  }

  @ViewBuilder private func regularContent(
    _ conversion: ConversionModel, trip: TripSnapshot, keypad: NumberPad
  ) -> some View {
    if wide {
      HStack(alignment: .bottom, spacing: 24) {
        ScrollView { readout(conversion, trip: trip) }.scrollBounceBehavior(.basedOnSize)
        VStack(spacing: 8) {
          keypad
          if !verticalRail { logButton(conversion, trip: trip) }
        }
        .frame(width: 240).padding(.trailing, 18)
      }
    } else {
      ScrollView { readout(conversion, trip: trip) }.scrollBounceBehavior(.basedOnSize)
      VStack(spacing: 8) {
        keypad
        if !verticalRail { logButton(conversion, trip: trip) }
      }
      .padding(.horizontal, 18).padding(.top, 8)
    }
  }

  /// Tent: the result at display size on the leading side, big keys on the trailing side.
  private func tentContent(_ conversion: ConversionModel, trip: TripSnapshot) -> some View {
    @Bindable var conversion = conversion
    // As tall as the space allows, up to 80pt, so the pad still fits a landscape phone.
    let key = min(80, max(44, (size.height - 30) / 4))
    let typed = (conversion.parsedAmount ?? 0) > 0
    let shown = Money.typed(conversion.amount, currency: conversion.from.code)
    let result = resultText(conversion)
    return HStack(alignment: .top, spacing: 20) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 10) {
          if !verticalRail {
            Button("Close", systemImage: "xmark") { close() }
              .labelStyle(.iconOnly).buttonStyle(.glass)
          }
          currencies(conversion, compact: true)
        }
        Spacer(minLength: 8)
        Text(shown)
          .typeface(30, .bold, tracking: -0.03, relativeTo: .title, maximum: 1.2)
          .monospacedDigit()
          .foregroundStyle(typed ? Theme.secondary : Theme.tertiary)
          .lineLimit(1).minimumScaleFactor(0.5)
          .bump(on: shown)
          .accessibilityLabel("Amount in \(conversion.from.currencyName), \(shown)")
          .accessibilityIdentifier("converter.amount")
        Text(result)
          .typeface(88, .heavy, tracking: -0.05, relativeTo: .largeTitle, maximum: 1.2)
          .monospacedDigit()
          .foregroundStyle(Theme.accentText)
          .lineLimit(1).minimumScaleFactor(0.4)
          .contentTransition(.numericText())
          .animation(reduceMotion ? nil : Motion.bump, value: result)
          .accessibilityLabel("\(boardLabel(conversion)), \(result)")
          .accessibilityIdentifier("converter.result")
        if conversion.result == nil || conversion.amountIssue != nil {
          Text(boardLabel(conversion))
            .typeface(13, .bold, relativeTo: .footnote, maximum: 1.4)
            .foregroundStyle(Theme.secondary)
        }
        rateControls(conversion)
        Spacer(minLength: 8)
        insight(conversion, trip: trip)
        if !verticalRail { logButton(conversion, trip: trip, height: 48).padding(.top, 10) }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      NumberPad(
        value: $conversion.amount, currency: conversion.from.code, keyHeight: key, spacing: 6,
        filled: true)
      .frame(width: key * 3 + 12)
      .frame(maxHeight: .infinity)
    }
    .padding(.horizontal, 20).padding(.vertical, 12)
  }

  private var header: some View {
    ZStack {
      Text("Quick convert")
        .typeface(16, .heavy, relativeTo: .headline, maximum: 1.3)
        .foregroundStyle(Theme.ink)
        .accessibilityAddTraits(.isHeader)
      HStack {
        Button("Close") { close() }
          .typeface(16, .bold, relativeTo: .body, maximum: 1.3)
          .foregroundStyle(Theme.secondary)
          .frame(minWidth: 44, minHeight: 44, alignment: .leading)
          .contentShape(Rectangle())
          .buttonStyle(.plain)
        Spacer()
      }
    }
    .frame(height: 44)
  }

  private func readout(_ conversion: ConversionModel, trip: TripSnapshot) -> some View {
    VStack(spacing: 0) {
      currencies(conversion).padding(.top, 4)
      amount(conversion).padding(.top, 14)
      board(conversion).padding(.top, 10)
      rateControls(conversion)
      insight(conversion, trip: trip).padding(.top, 12)
      presets(conversion, trip: trip).padding(.top, 12)
    }
    .padding(.horizontal, 18).padding(.bottom, 8)
  }

  // MARK: - Currencies

  private func currencies(_ conversion: ConversionModel, compact: Bool = false) -> some View {
    HStack(spacing: compact ? 6 : 12) {
      pill(conversion.from, side: .from)
      Button {
        rateFocused = false
        conversion.swap()
        Haptics.selection()
        withAnimation(reduceMotion ? nil : .timingCurve(0.34, 1.56, 0.64, 1, duration: 0.6)) {
          swapTurns += 180
        }
      } label: {
        Image(systemName: "arrow.right.arrow.left")
          .font(.system(size: compact ? 13 : 16, weight: .bold))
          .foregroundStyle(compact ? Theme.secondary : Theme.background)
          .rotationEffect(.degrees(swapTurns))
          .frame(width: compact ? 32 : 42, height: compact ? 32 : 42)
          .background(compact ? .clear : Theme.ink, in: Circle())
          .contentShape(Circle())
      }
      .buttonStyle(PressStyle(scale: 0.92))
      .accessibilityLabel("Swap currencies")
      .accessibilityIdentifier("converter.swap")
      pill(conversion.to, side: .to)
    }
  }

  private func pill(_ currency: ConversionCurrency, side: ConversionSide) -> some View {
    Button {
      rateFocused = false
      picking = side
    } label: {
      Text("\(currency.flag) \(currency.code)")
        .typeface(15, .heavy, relativeTo: .body, maximum: 1.4)
        .foregroundStyle(Theme.ink)
        .padding(.vertical, 9).padding(.horizontal, 14)
        .frame(minWidth: 74)
        .background(Theme.inset, in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(PressStyle(scale: 0.94))
    .accessibilityLabel("\(side.title), \(currency.title), \(currency.currencyName)")
    .accessibilityHint("Choose a country, city, currency or flag")
    .accessibilityIdentifier("converter.\(side.rawValue)")
  }

  // MARK: - Amounts

  private func amount(_ conversion: ConversionModel) -> some View {
    let shown = Money.typed(conversion.amount, currency: conversion.from.code)
    let typed = (conversion.parsedAmount ?? 0) > 0
    return Text(shown)
      .typeface(46, .bold, tracking: -0.045, relativeTo: .largeTitle, maximum: 1.2)
      .monospacedDigit()
      .foregroundStyle(typed ? Theme.ink : Theme.tertiary)
      .lineLimit(1).minimumScaleFactor(0.5)
      .bump(on: shown)
      .accessibilityLabel("Amount in \(conversion.from.currencyName), \(shown)")
      .accessibilityIdentifier("converter.amount")
  }

  private func board(_ conversion: ConversionModel) -> some View {
    let result = resultText(conversion)
    return VStack(spacing: 2) {
      Text(boardLabel(conversion))
        .typeface(13, .bold, relativeTo: .footnote, maximum: 1.4)
        .foregroundStyle(Theme.secondary)
      Text(result)
        .typeface(44, .bold, tracking: -0.045, relativeTo: .largeTitle, maximum: 1.2)
        .monospacedDigit()
        .foregroundStyle(Theme.accentText)
        .lineLimit(1).minimumScaleFactor(0.5)
        .contentTransition(.numericText())
        .animation(reduceMotion ? nil : Motion.bump, value: result)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 12).padding(.horizontal, 10).padding(.bottom, 14)
    .background(Theme.inset, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("converter.result")
  }

  /// "That's about" once there's an amount, otherwise the unit rate, e.g. "€1 = £0.86".
  private func boardLabel(_ conversion: ConversionModel) -> String {
    if conversion.isIdentity { return "Same currency" }
    if conversion.amountIssue != nil { return "Check the amount" }
    if (conversion.parsedAmount ?? 0) > 0, conversion.result != nil { return "That’s about" }
    if let rate = unitRate(conversion) { return rate }
    if conversion.isLoading { return "Fetching today’s rate…" }
    return conversion.usesManualRate ? "Enter a rate below" : "No live rate right now"
  }

  private func resultText(_ conversion: ConversionModel) -> String {
    if let result = conversion.result { return Money.format(result, conversion.to.code) }
    let empty = conversion.amount.isEmpty || conversion.parsedAmount == 0
    return empty && conversion.amountIssue == nil ? Money.format(0, conversion.to.code) : "—"
  }

  /// One unit (or a thousand of a zero-decimal currency) at the current rate.
  private func unitRate(_ conversion: ConversionModel) -> String? {
    let rate = conversion.usesManualRate ? conversion.rateInput : conversion.quote?.rate
    guard let rate, !rate.isEmpty else { return nil }
    let from = conversion.from.code
    let to = conversion.to.code
    let unit = Money.factor(from) * (Money.precision(from) == 0 ? 1000 : 1)
    guard let value = try? Money.convert(unit, from: from, to: to, rate: rate) else { return nil }
    return "\(Money.format(unit, from, compact: true)) = \(Money.format(value, to))"
  }

  /// Offline, or with a refused quote: retry, or type the rate off a board or a receipt.
  @ViewBuilder private func rateControls(_ conversion: ConversionModel) -> some View {
    if !conversion.isIdentity, conversion.usesManualRate || conversion.message != nil {
      VStack(spacing: 8) {
        if conversion.usesManualRate {
          HStack(spacing: 8) {
            Text("1 \(conversion.from.code) =")
            TextField(
              "Rate",
              text: Binding(get: { conversion.rateInput }, set: { conversion.enterManualRate($0) })
            )
            .keyboardType(.decimalPad)
            .focused($rateFocused)
            .multilineTextAlignment(.center)
            .frame(width: 96)
            .padding(.vertical, 8)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel("Exchange rate, \(conversion.to.code) per \(conversion.from.code)")
            .accessibilityIdentifier("converter.rate")
            Text(conversion.to.code)
          }
          .typeface(15, .bold, relativeTo: .body, maximum: 1.4)
          .foregroundStyle(Theme.ink)
        } else if let message = conversion.message {
          Text(message)
            .typeface(12.5, .semibold, relativeTo: .caption, maximum: 1.6)
            .foregroundStyle(Theme.secondary)
            .multilineTextAlignment(.center)
        }
        if let issue = conversion.conversionIssue {
          Text(issue)
            .typeface(12.5, .semibold, relativeTo: .caption, maximum: 1.6)
            .foregroundStyle(Theme.bad)
            .multilineTextAlignment(.center)
        }
        HStack(spacing: 18) {
          if !conversion.usesManualRate {
            Button("Enter a rate") {
              conversion.enterManualRate()
              rateFocused = true
            }
          }
          Button(conversion.usesManualRate ? "Use live rate" : "Try again") {
            rateFocused = false
            conversion.refresh()
          }
        }
        .typeface(13, .heavy, relativeTo: .footnote, maximum: 1.4)
        .foregroundStyle(Theme.accentText)
        .buttonStyle(.plain)
        .frame(minHeight: 32)
      }
      .padding(.top, 10)
    }
  }

  // MARK: - Budget

  /// "12% of a day's budget" against the trip budget spread over its days, with a bar that turns
  /// from good to accent past half and bad once it's over.
  @ViewBuilder private func insight(_ conversion: ConversionModel, trip: TripSnapshot) -> some View
  {
    if trip.dailyBudget > 0 {
      let daily = trip.dailyBudget
      let typed = (conversion.parsedAmount ?? 0) > 0
      let home = homeValue(conversion, trip: trip)
      let percent = home.map { Double($0) / Double(daily) * 100 } ?? 0
      let colour = percent <= 50 ? Theme.good : percent <= 100 ? Theme.accent : Theme.bad
      VStack(spacing: 6) {
        HStack {
          Text(
            !typed
              ? "Type a price you can see"
              : home == nil ? "Waiting for a rate" : "\(Int(percent.rounded()))% of a day’s budget"
          )
          Spacer(minLength: 8)
          Text(
            "\(Money.format(Money.wholeUnits(daily, trip.homeCurrency), trip.homeCurrency, compact: true)) a day"
          )
        }
        .typeface(13, .bold, relativeTo: .footnote, maximum: 1.4)
        .foregroundStyle(Theme.secondary)
        Capsule().fill(Theme.inset).frame(height: 8)
          .overlay(alignment: .leading) {
            GeometryReader { proxy in
              Capsule().fill(colour)
                .frame(width: proxy.size.width * min(1, percent / 100))
            }
          }
          .clipShape(Capsule())
          .animation(
            reduceMotion ? nil : .timingCurve(0.34, 1.3, 0.64, 1, duration: 0.5), value: percent
          )
          .accessibilityHidden(true)
      }
      .accessibilityElement(children: .combine)
    }
  }

  /// The typed amount in home currency: as typed, as converted, or at the trip's known rate.
  private func homeValue(_ conversion: ConversionModel, trip: TripSnapshot) -> Int64? {
    guard let typed = conversion.parsedAmount, typed > 0 else { return nil }
    if conversion.from.code == trip.homeCurrency { return typed }
    if conversion.to.code == trip.homeCurrency { return conversion.result }
    return trip.estimate(typed, from: conversion.from.code)
  }

  // MARK: - Presets

  private func presets(_ conversion: ConversionModel, trip: TripSnapshot) -> some View {
    let scale = presetScale(conversion, trip: trip)
    let values = [1, 5, 10, 20, 50, 100].map { Int64($0) * scale }
    let chips = values.map { value in
      Button {
        rateFocused = false
        conversion.amount = String(value)
        Haptics.selection()
      } label: {
        Text(
          Money.format(
            value * Money.factor(conversion.from.code), conversion.from.code, compact: true)
        )
        .typeface(13, .heavy, relativeTo: .footnote, maximum: 1.4)
        .foregroundStyle(Theme.secondary)
        .padding(.vertical, 7).padding(.horizontal, 12)
        .background(Theme.inset, in: Capsule())
        .fixedSize()
      }
      .buttonStyle(PressStyle(scale: 0.9))
    }
    return ViewThatFits(in: .horizontal) {
      HStack(spacing: 6) { ForEach(values.indices, id: \.self) { chips[$0] } }
      VStack(spacing: 6) {
        HStack(spacing: 6) { ForEach(0..<3, id: \.self) { chips[$0] } }
        HStack(spacing: 6) { ForEach(3..<6, id: \.self) { chips[$0] } }
      }
    }
    .frame(maxWidth: .infinity)
  }

  /// Presets in round numbers worth about £1 to £100 back home: €1…€100, ¥100…¥10,000.
  private func presetScale(_ conversion: ConversionModel, trip: TripSnapshot) -> Int64 {
    let from = conversion.from.code
    guard from != trip.homeCurrency else { return 1 }
    let rate =
      (conversion.to.code == trip.homeCurrency ? conversion.quote?.rate : nil)
      ?? trip.knownRate(from: from)
    guard let rate, let value = Double(rate), value > 0 else {
      return Money.precision(from) == 0 ? 100 : 1
    }
    // Capped so the largest preset stays within the keypad's seven digits.
    let power = min(4, max(0, log10(1 / value).rounded()))
    return Int64(pow(10, power))
  }

  // MARK: - Actions

  private func logButton(
    _ conversion: ConversionModel, trip: TripSnapshot, height: CGFloat = 56
  ) -> some View {
    Button("Log it as an expense") { logExpense(conversion, trip: trip) }
      .buttonStyle(LipButtonStyle(height: height))
      .disabled(!conversion.canLogExpense(homeCurrency: trip.homeCurrency) || handingOff)
      .animation(
        .easeOut(duration: 0.25), value: conversion.canLogExpense(homeCurrency: trip.homeCurrency)
      )
      .accessibilityIdentifier("converter.log")
  }

  private func close() {
    conversion?.cancel()
    dismiss()
  }

  /// Closes, then opens Add expense for the same day with the amount and currency typed here.
  private func logExpense(_ conversion: ConversionModel, trip: TripSnapshot) {
    guard !handingOff else { return }
    do {
      let draft = try conversion.expenseDraft(trip: trip, attachment: attachment)
      handingOff = true
      conversion.cancel()
      dismiss()
      Task {
        try? await Task.sleep(for: .milliseconds(350))
        app.expenseDraft = draft
        app.persistDraft()
      }
    } catch {
      Haptics.error()
      app.error = error.localizedDescription
    }
  }
}
