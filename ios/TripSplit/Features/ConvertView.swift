import SwiftUI

struct ConvertView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var tripID: String
  var attachment: Attachment
  @State private var conversion: ConversionModel?
  @State private var picking: ConversionSide?
  @State private var wide = false
  @State private var verticalRail = false
  @State private var swapTurns = 0.0
  @State private var handingOff = false
  private enum InputField: Hashable { case amount, rate }
  @FocusState private var inputFocus: InputField?
  @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 48.0

  var body: some View {
    if let trip = app.store.trip(tripID) {
      NavigationStack {
        Group {
          if let conversion {
            content(conversion, trip: trip)
          } else {
            ProgressView("Opening converter…").frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }.background(Theme.background).navigationTitle("Quick convert")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Close", systemImage: "xmark") {
                conversion?.cancel()
                dismiss()
              }
            }
            if verticalRail, let conversion {
              ToolbarItem(placement: .confirmationAction) {
                Button("Log as expense", systemImage: "plus") { logExpense(conversion, trip: trip) }
                  .disabled(
                    !conversion.canLogExpense(homeCurrency: trip.homeCurrency) || handingOff
                  )
                  .accessibilityIdentifier("converter.log")
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
          .onGeometryChange(for: Bool.self) {
            $0.size.width >= 600 && $0.size.width > $0.size.height
          } action: {
            wide = $0
          }
          .readVerticalRail($verticalRail)
      }.task {
        // A nested picker may cause this task to run again; the open session owns its choices.
        guard conversion == nil else { return }
        let defaults = trip.conversionDefaults
        let api = app.sync.api
        let state = ConversionModel(
          from: defaults.from, to: defaults.to, date: trip.date(for: attachment)
        ) { from, to, date in
          try await api.quote(from: from, to: to, date: date, token: nil)
        }
        conversion = state
        state.start()
      }.taskRail()
    }
  }

  private func content(_ conversion: ConversionModel, trip: TripSnapshot) -> some View {
    @Bindable var conversion = conversion
    return ScrollView {
      VStack(spacing: 22) {
        currencyControls(conversion, trip: trip)
        let layout =
          wide && !dynamicTypeSize.isAccessibilitySize
          ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
          : AnyLayout(VStackLayout(spacing: 22))
        layout {
          VStack(spacing: 18) {
            TextField("Amount", text: $conversion.amount).keyboardType(.decimalPad)
              .multilineTextAlignment(.center).focused($inputFocus, equals: .amount)
              .font(.system(size: wide ? min(amountSize, 38) : amountSize, weight: .bold))
              .monospacedDigit().accessibilityLabel("Amount in \(conversion.from.code)")
              .accessibilityIdentifier("converter.amount")
            if let issue = conversion.amountIssue {
              Text(issue).font(.footnote).foregroundStyle(Theme.bad)
            }
            resultBoard(conversion)
            rateDetails(conversion)
            budgetInsight(conversion, trip: trip)
          }.frame(maxWidth: .infinity)
          VStack(spacing: 18) {
            LazyVGrid(
              columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8
            ) {
              ForEach([1, 5, 10, 20, 50, 100], id: \.self) { value in
                let preset = value * (Money.precision(conversion.from.code) == 0 ? 100 : 1)
                Button("\(preset)") { conversion.amount = String(preset) }
                  .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity, minHeight: 44)
                  .background(Theme.inset, in: Capsule()).buttonStyle(.plain)
                  .accessibilityLabel("Set amount to \(preset) \(conversion.from.code)")
              }
            }
            NumberPad(value: $conversion.amount, currency: conversion.from.code)
            if !verticalRail {
              Button {
                logExpense(conversion, trip: trip)
              } label: {
                Label("Log it as an expense", systemImage: "plus")
                  .font(.headline).padding(.horizontal, 16).padding(.vertical, 14)
                  .frame(maxWidth: .infinity, minHeight: 50)
                  .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16))
                  .foregroundStyle(.white).contentShape(RoundedRectangle(cornerRadius: 16))
              }.buttonStyle(.plain).fixedSize(horizontal: false, vertical: true)
                .disabled(!conversion.canLogExpense(homeCurrency: trip.homeCurrency) || handingOff)
                .opacity(conversion.canLogExpense(homeCurrency: trip.homeCurrency) ? 1 : 0.45)
                .accessibilityIdentifier("converter.log")
            }
            if conversion.to.code != trip.homeCurrency {
              Text("Choose \(trip.homeCurrency) as the destination currency to log a trip expense.")
                .font(.footnote).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            } else if !conversion.isIdentity, conversion.result == nil,
              conversion.conversionIssue == nil
            {
              Text("You can still log the original amount with conversion pending.")
                .font(.footnote).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            }
          }.frame(maxWidth: .infinity)
        }
      }.pagePadding()
    }.scrollDismissesKeyboard(.interactively)
  }

  private func currencyControls(_ conversion: ConversionModel, trip: TripSnapshot) -> some View {
    VStack(spacing: 8) {
      let layout =
        dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
      layout {
        currencyButton(conversion.from, side: .from)
        Button {
          inputFocus = nil
          conversion.swap()
          withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) {
            swapTurns += 180
          }
        } label: {
          Image(systemName: "arrow.left.arrow.right").font(.title3.weight(.semibold))
            .rotationEffect(.degrees(reduceMotion ? 0 : swapTurns))
            .frame(width: 44, height: 44).contentShape(Circle())
        }.buttonStyle(.plain).foregroundStyle(Theme.accent)
          .accessibilityLabel("Swap currencies").accessibilityIdentifier("converter.swap")
        currencyButton(conversion.to, side: .to)
      }
      Button {
        inputFocus = nil
        let defaults = trip.conversionDefaults
        conversion.reset(from: defaults.from, to: defaults.to)
      } label: {
        Label("Reset to trip currencies", systemImage: "arrow.counterclockwise")
          .font(.footnote.weight(.semibold)).frame(minHeight: 44)
          .contentShape(Rectangle())
      }.accessibilityIdentifier("converter.reset")
    }
  }
  private func currencyButton(_ currency: ConversionCurrency, side: ConversionSide) -> some View {
    Button {
      inputFocus = nil
      picking = side
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        Text(side == .from ? "FROM" : "TO").font(.caption2.weight(.heavy)).tracking(1)
          .foregroundStyle(Theme.secondary)
        HStack(spacing: 7) {
          Text(currency.flag).font(.title2).accessibilityHidden(true)
          Text(currency.code).font(.title3.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.8)
          Spacer(minLength: 0)
          Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(
            Theme.accent)
        }
        Text(currency.title).font(.caption).foregroundStyle(Theme.secondary).lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
      }.padding(14).frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }.buttonStyle(.plain).foregroundStyle(Theme.ink)
      .accessibilityLabel(
        "\(side.title), \(currency.title), \(currency.code), \(currency.currencyName)"
      )
      .accessibilityHint("Choose a country, city, currency or flag")
      .accessibilityIdentifier("converter.\(side.rawValue)")
  }
  private func resultBoard(_ conversion: ConversionModel) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(conversion.isIdentity ? "SAME CURRENCY" : "THAT’S ABOUT")
        .font(.system(.caption2, design: .monospaced, weight: .heavy)).tracking(2)
        .foregroundStyle(Theme.amber)
      if let result = conversion.result {
        let formatted = Money.format(result, conversion.to.code)
        if wide || dynamicTypeSize.isAccessibilitySize || formatted.count > 12 {
          Text(formatted).font(.system(size: wide ? 52 : 38, weight: .bold)).monospacedDigit()
            .minimumScaleFactor(0.5).lineLimit(1).foregroundStyle(.white)
        } else {
          FlapText(value: formatted, count: max(10, formatted.count), size: 23)
        }
      } else {
        Text(
          conversion.amountIssue != nil
            ? "Check amount" : conversion.isLoading ? "Fetching rate…" : "Rate needed"
        )
        .font(.title2.weight(.heavy)).foregroundStyle(.white)
      }
    }.frame(maxWidth: .infinity, minHeight: 85, alignment: .leading).padding(22)
      .background(Theme.board, in: RoundedRectangle(cornerRadius: 22))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        conversion.result.map { Money.format($0, conversion.to.code) }
          ?? (conversion.amountIssue ?? (conversion.isLoading ? "Fetching rate" : "Rate needed"))
      )
      .accessibilityIdentifier("converter.result")
  }
  @ViewBuilder private func rateDetails(_ conversion: ConversionModel) -> some View {
    if conversion.isIdentity {
      Text("1 \(conversion.from.code) = 1 \(conversion.to.code) · No exchange rate needed.")
        .font(.caption).foregroundStyle(Theme.secondary)
    } else {
      VStack(alignment: .leading, spacing: 10) {
        if conversion.usesManualRate {
          HStack {
            Text("1 \(conversion.from.code) =")
            TextField(
              "Rate",
              text: Binding(get: { conversion.rateInput }, set: { conversion.enterManualRate($0) })
            )
            .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).focused(
              $inputFocus, equals: .rate
            )
            .accessibilityLabel("Manual exchange rate").accessibilityIdentifier("converter.rate")
            Text(conversion.to.code)
          }.font(.subheadline)
          Text("Your entered rate · \(conversion.quoteDate)").font(.caption).foregroundStyle(
            Theme.secondary)
        } else if let quote = conversion.quote {
          Text(
            "1 \(conversion.from.code) = \(quote.rate) \(conversion.to.code) · \(quote.source) · \(quote.rateDate)\nReference estimate; your card’s charge may differ."
          )
          .font(.caption).foregroundStyle(Theme.secondary)
        } else {
          Text(conversion.message ?? "Fetching a reference rate for \(conversion.quoteDate)…")
            .font(.footnote).foregroundStyle(Theme.secondary)
        }
        if let issue = conversion.conversionIssue {
          Text(issue).font(.footnote).foregroundStyle(Theme.bad)
        }
        HStack(spacing: 20) {
          if !conversion.usesManualRate {
            Button("Enter a rate") {
              conversion.enterManualRate()
              inputFocus = .rate
            }.frame(minHeight: 44)
          }
          if !conversion.isLoading {
            Button("Use live rate", systemImage: "arrow.clockwise") {
              inputFocus = nil
              conversion.refresh()
            }.frame(minHeight: 44)
          }
        }.font(.footnote.weight(.semibold))
      }
    }
  }
  @ViewBuilder private func budgetInsight(_ conversion: ConversionModel, trip: TripSnapshot)
    -> some View
  {
    if let result = conversion.result, conversion.to.code == trip.homeCurrency,
      let budget = Money.minor(trip.budgetMinor), budget > 0
    {
      let daily = max(1, budget / Int64(max(1, trip.days.count)))
      VStack(spacing: 6) {
        HStack {
          Text("\(result * 100 / daily)% of a day’s budget")
          Spacer()
          Text("\(Money.format(daily, conversion.to.code)) a day")
        }.font(.caption)
        ProgressView(value: min(Double(result) / Double(daily), 1))
          .tint(result > daily ? Theme.bad : Theme.accent)
      }
    }
  }
  private func logExpense(_ conversion: ConversionModel, trip: TripSnapshot) {
    guard !handingOff else { return }
    do {
      let draft = try conversion.expenseDraft(trip: trip, attachment: attachment)
      handingOff = true
      conversion.cancel()
      dismiss()
      Task {
        try? await Task.sleep(for: .milliseconds(300))
        app.expenseDraft = draft
        app.persistDraft()
      }
    } catch { app.error = error.localizedDescription }
  }
}
