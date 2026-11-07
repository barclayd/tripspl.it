import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitPersistence
import TripSplitSharedUI

/// The add and edit sheet: amount on a keypad, then what, when, who paid and who shares it.
public struct ExpenseEditor: View {
  public init() {}
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var saved: Expense?
  @State private var announced = false
  @State private var saving = false
  @State private var wideSheet = false
  @State private var usesVerticalRail = false
  @State private var deleteConfirmation = false
  @State private var localError: String?
  @State private var keyboardVisible = false
  @State private var amountFocused = true
  private enum Field: Hashable { case title, bank }
  @FocusState private var focusedField: Field?

  public var body: some View {
    NavigationStack {
      if let draft = model.expenseDraft, let trip = model.store.trip(draft.tripID) {
        Group {
          if let saved {
            ReceiptView(expense: saved, trip: trip) {
              announce(saved, trip: trip)
              dismiss()
            }
          } else {
            form(trip, draft: draft)
          }
        }
        .background(Theme.surface)
        // Beside the keypad the heading shares a row with the day chips, so the bar stays empty.
        .navigationTitle(wideSheet && usesVerticalRail ? "" : heading(draft))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(usesVerticalRail && saved == nil ? .automatic : .hidden, for: .navigationBar)
        .toolbar {
          ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focusedField = nil }
          }
          if usesVerticalRail && saved == nil {
            ToolbarItem(placement: .cancellationAction) {
              Button("Cancel", systemImage: "xmark") { cancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
              Button("Save", systemImage: "checkmark") { save() }.disabled(!valid(draft))
            }
            if draft.expenseID != nil {
              ToolbarItem {
                Button("Delete expense", systemImage: "trash", role: .destructive) {
                  deleteConfirmation = true
                }
              }
            }
          }
        }
        .confirmationDialog(
          "Delete this expense?", isPresented: $deleteConfirmation, titleVisibility: .visible
        ) {
          Button("Delete expense", role: .destructive) { delete(draft, trip: trip) }
        }
        .onDisappear { if let saved { announce(saved, trip: trip) } }
        .interactiveDismissDisabled(saving)
      }
    }
    .disabled(saving)
    .onChange(of: focusedField) { _, field in
      if field != nil { amountFocused = false }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
      keyboardVisible = true
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
      keyboardVisible = false
    }
    .overlay {
      if saving {
        ProgressView("Saving expense…")
          .typeface(15, .semibold, relativeTo: .subheadline)
          .padding(24)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      }
    }
    .readVerticalRail($usesVerticalRail)
    .taskRail()
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.surface)
    .presentationCornerRadius(Theme.Radius.sheet)
  }

  private func heading(_ draft: ExpenseDraft) -> String {
    draft.expenseID != nil ? "Edit" : draft.attachment.kind == .leg ? "New travel" : "New expense"
  }

  private func valid(_ draft: ExpenseDraft) -> Bool {
    !saving && amount(draft) > 0 && !draft.splitWith.isEmpty
  }

  private func amount(_ draft: ExpenseDraft) -> Int64 {
    (try? Money.parse(draft.amount, currency: draft.currency)) ?? 0
  }

  // MARK: - Layout

  /// Wide enough for the keypad to sit beside the form, as on the open Duo's trailing sheet.
  @ViewBuilder private func form(_ trip: TripSnapshot, draft: ExpenseDraft) -> some View {
    let keypad = NumberPad(
      value: bind(\.amount, fallback: ""), currency: draft.currency,
      keyHeight: wideSheet ? 56 : 52, spacing: 4, filled: wideSheet)
    VStack(spacing: 0) {
      if !usesVerticalRail { header(draft).padding(.horizontal, wideSheet ? 22 : 18) }
      if wideSheet {
        HStack(spacing: 14) {
          if usesVerticalRail {
            Text(heading(draft))
              .typeface(20, .heavy, relativeTo: .title3, maximum: 1.3)
              .foregroundStyle(Theme.ink)
              .fixedSize()
              .accessibilityAddTraits(.isHeader)
              .padding(.leading, 22)
          }
          dayChips(trip, draft: draft, inset: usesVerticalRail ? 0 : 22)
            .padding(.trailing, usesVerticalRail ? 22 : 0)
        }
        .padding(.top, usesVerticalRail ? 20 : 2).padding(.bottom, 14)
        HStack(alignment: .bottom, spacing: 0) {
          formScroll(trip, draft: draft)
          if amountFocused && !keyboardVisible && focusedField == nil {
            keypad.frame(width: 200).padding(.bottom, 18).padding(.trailing, 22)
          }
        }
      } else {
        formScroll(trip, draft: draft)
        if amountFocused && !keyboardVisible && focusedField == nil {
          keypad.padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 4)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      Theme.surface.onTapGesture { amountFocused = false }
    }
    .onGeometryChange(for: Bool.self) { $0.size.width >= 480 } action: { wideSheet = $0 }
  }

  private func formScroll(_ trip: TripSnapshot, draft: ExpenseDraft) -> some View {
    ScrollView { fields(trip, draft: draft) }
      .scrollDismissesKeyboard(.interactively)
      .onScrollPhaseChange { _, phase in
        if phase == .interacting { amountFocused = false }
      }
  }

  /// Cancel, the heading, then delete and a Save pill that lights up once there's an amount.
  private func header(_ draft: ExpenseDraft) -> some View {
    let ready = valid(draft)
    return HStack(spacing: 0) {
      Button("Cancel") { cancel() }
        .typeface(16, .bold, relativeTo: .body, maximum: 1.3)
        .foregroundStyle(Theme.secondary)
        .frame(width: 90, alignment: .leading)
      Spacer(minLength: 0)
      Text(heading(draft))
        .typeface(16, .heavy, relativeTo: .headline, maximum: 1.3)
        .foregroundStyle(Theme.ink)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 0)
      HStack(spacing: 4) {
        if draft.expenseID != nil {
          Button {
            deleteConfirmation = true
          } label: {
            Image(systemName: "trash").font(.system(size: 17, weight: .semibold))
              .foregroundStyle(Theme.bad)
              .frame(width: 34, height: 34)
              .contentShape(Circle())
          }
          .accessibilityLabel("Delete expense")
        }
        Button("Save") { save() }
          .typeface(15, .heavy, relativeTo: .body, maximum: 1.3)
          .fixedSize()
          .foregroundStyle(ready ? Theme.accentInk : Theme.tertiary)
          .padding(.vertical, 8).padding(.horizontal, 15)
          .background(ready ? Theme.accent : Theme.inset, in: Capsule())
          .animation(.easeOut(duration: 0.25), value: ready)
          .disabled(!ready)
      }
      .frame(minWidth: 90, alignment: .trailing)
    }
    .buttonStyle(.plain)
    .frame(height: 44)
    .contentShape(Rectangle())
    .simultaneousGesture(TapGesture().onEnded { amountFocused = false })
  }

  /// Leading and trailing space for the form; beside the keypad it's also the gap to the keys.
  private var inset: CGFloat { wideSheet ? 22 : 18 }

  private func fields(_ trip: TripSnapshot, draft: ExpenseDraft) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if !wideSheet { dayChips(trip, draft: draft, inset: inset).padding(.top, 2) }
      amountBlock(trip, draft: draft).padding(.top, 2).padding(.bottom, wideSheet ? 2 : -2)
      details(trip, draft: draft)
    }
    .padding(.bottom, 8)
  }

  private func details(_ trip: TripSnapshot, draft: ExpenseDraft) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if draft.attachment.kind == .day {
        Text(draft.selectedDayIDs.count > 1
          ? "Total shared across \(draft.selectedDayIDs.count) days"
          : "Tap days above to share this expense")
          .typeface(12.5, .semibold, relativeTo: .caption)
          .foregroundStyle(Theme.secondary)
          .padding(.horizontal, inset)
      }
      TextField(
        draft.attachment.kind == .leg ? "e.g. Taxi to the airport" : "What was it?",
        text: bind(\.title, fallback: "")
      )
      .typeface(16, .bold, relativeTo: .body)
      .foregroundStyle(Theme.ink)
      .submitLabel(.done)
      .focused($focusedField, equals: .title)
      .onSubmit { focusedField = nil }
      .padding(.vertical, 13).padding(.horizontal, 16)
      .background(Theme.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .padding(.horizontal, inset)
      categoryChips(draft)
      panel(trip, draft: draft).padding(.horizontal, inset)
      if draft.currency != trip.homeCurrency {
        Text(conversionNote(trip, draft: draft))
        .typeface(12, .semibold, relativeTo: .caption)
        .foregroundStyle(Theme.tertiary)
        .padding(.horizontal, inset + 4)
      }
      if let localError {
        Text(localError).typeface(13, .semibold, relativeTo: .footnote)
          .foregroundStyle(Theme.bad).padding(.horizontal, inset + 4)
      }
    }
    .contentShape(Rectangle())
    .simultaneousGesture(TapGesture().onEnded { amountFocused = false })
  }

  // MARK: - When

  /// Day pills toggle a shared expense's dates; travel legs remain a single selection.
  private func dayChips(_ trip: TripSnapshot, draft: ExpenseDraft, inset: CGFloat) -> some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal) {
        HStack(spacing: 6) {
          ForEach(options(trip), id: \.attachment.id) { option in
            let selected = option.attachment.kind == .day
              ? draft.selectedDayIDs.contains(option.attachment.id)
              : option.attachment == draft.attachment
            Button {
              setDay(option.attachment, trip: trip)
            } label: {
              Text(option.label)
                .typeface(12.5, .heavy, relativeTo: .caption, maximum: 1.4)
                .foregroundStyle(selected ? Theme.background : Theme.secondary)
                .padding(.vertical, 7).padding(.horizontal, 12)
                .background(selected ? Theme.ink : Theme.inset, in: Capsule())
                .animation(.easeOut(duration: 0.25), value: selected)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint(option.attachment.kind == .day
              ? "Toggles this day. The total is shared across selected days." : "Selects this travel leg")
            .id(option.attachment.id)
          }
        }
      }
      .scrollIndicators(.hidden)
      .contentMargins(.horizontal, inset, for: .scrollContent)
      .simultaneousGesture(TapGesture().onEnded { amountFocused = false })
      .onScrollPhaseChange { _, phase in
        if phase == .interacting { amountFocused = false }
      }
      .onAppear { proxy.scrollTo(draft.attachment.id, anchor: .center) }
    }
  }

  private func options(_ trip: TripSnapshot) -> [(attachment: Attachment, label: String)] {
    let legs = trip.orderedLegs
    func leg(_ leg: TravelLeg) -> (Attachment, String) {
      let label =
        switch leg.kind {
        case .outbound: "Getting there"
        case .return: "Getting home"
        default: leg.title
        }
      return (.init(kind: .leg, id: leg.id), label)
    }
    var result = legs.filter { $0.kind == .outbound }.map(leg)
    for stop in trip.stops {
      for day in trip.days where day.stopId == stop.id {
        let date = CivilDate.display(day.date, format: "EEE d")
        result.append(
          (.init(kind: .day, id: day.id), "\(stop.flag) \(date)\(trip.isToday(day) ? " · Today" : "")"))
      }
      result += legs.filter { $0.kind == .transfer && $0.fromStopId == stop.id }.map(leg)
    }
    result += legs.filter { $0.kind == .return }.map(leg)
    return result.map { (attachment: $0.0, label: $0.1) }
  }

  /// Moving day keeps the currency if that day spends it, and swaps to a category that fits.
  private func setDay(_ attachment: Attachment, trip: TripSnapshot) {
    Haptics.selection()
    mutate {
      let previous = $0.attachment
      $0.select(attachment, in: trip)
      let offered = currencies(trip, attachment: $0.attachment)
      if previous.kind != $0.attachment.kind, !offered.contains($0.currency) {
        setCurrency(offered[0], on: &$0)
      }
      let travel = $0.attachment.kind == .leg
      let categories = travel ? ExpenseCategory.travelCategories : ExpenseCategory.dayCategories
      if !categories.contains($0.category) { $0.category = travel ? .flight : .food }
    }
  }

  // MARK: - How much

  /// Centred over the keypad on the phone, and leading beside it on a wide sheet.
  private func amountBlock(_ trip: TripSnapshot, draft: ExpenseDraft) -> some View {
    let minor = amount(draft)
    let shown = Money.typed(draft.amount, currency: draft.currency)
    return VStack(alignment: wideSheet ? .leading : .center, spacing: wideSheet ? 10 : 12) {
      Text(shown)
        .typeface(wideSheet ? 54 : 58, .bold, tracking: -0.05, relativeTo: .largeTitle, maximum: 1.2)
        .monospacedDigit()
        .foregroundStyle(minor > 0 ? Theme.ink : Theme.tertiary)
        .lineLimit(1).minimumScaleFactor(0.5)
        .bump(on: shown)
        .padding(.horizontal, inset)
        .accessibilityLabel("Amount, \(shown)")
        .contentShape(Rectangle())
        .onTapGesture { focusAmount() }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows the number pad to edit the amount")
        .accessibilityAction { focusAmount() }
      ScrollView(.horizontal) {
        HStack(spacing: 6) {
          ForEach(currencies(trip, attachment: draft.attachment, current: draft.currency), id: \.self) {
            currency in
            let selected = currency == draft.currency
            Button {
              mutate { setCurrency(currency, on: &$0) }
            } label: {
              Text("\(flag(currency)) \(currency)")
                .typeface(13, .heavy, relativeTo: .footnote, maximum: 1.4)
                .foregroundStyle(selected ? Theme.background : Theme.secondary)
                .padding(.vertical, 6).padding(.horizontal, 11)
                .background(selected ? Theme.ink : Theme.inset, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(currency)
            .accessibilityAddTraits(selected ? .isSelected : [])
          }
          Menu {
            ForEach(CurrencyMetadata.codes, id: \.self) { currency in
              Button(currency) { mutate { setCurrency(currency, on: &$0) } }
            }
          } label: {
            Image(systemName: "ellipsis")
              .font(.system(size: 13, weight: .heavy))
              .foregroundStyle(Theme.secondary)
              .frame(width: 30, height: 27)
              .background(Theme.inset, in: Capsule())
          }
          .accessibilityLabel("Other currency")
          if minor > 0, let estimate = estimate(trip, draft: draft, minor: minor) {
            Text("≈ \(Money.format(estimate, trip.homeCurrency))")
              .typeface(13.5, .bold, relativeTo: .footnote, maximum: 1.4)
              .monospacedDigit()
              .foregroundStyle(Theme.secondary)
              .padding(.leading, 4)
              .contentTransition(.numericText())
          }
        }
        .frame(minWidth: 0)
      }
      .scrollIndicators(.hidden)
      .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
      .contentMargins(.horizontal, inset, for: .scrollContent)
      .defaultScrollAnchor(wideSheet ? .leading : .center, for: .alignment)
      .simultaneousGesture(TapGesture().onEnded { amountFocused = false })
      .onScrollPhaseChange { _, phase in
        if phase == .interacting { amountFocused = false }
      }
    }
    .frame(maxWidth: .infinity, alignment: wideSheet ? .leading : .center)
  }

  private func estimate(_ trip: TripSnapshot, draft: ExpenseDraft, minor: Int64) -> Int64? {
    guard draft.currency != trip.homeCurrency else { return nil }
    if let actual = try? Money.parse(draft.actualHomeAmount, currency: trip.homeCurrency), actual > 0 {
      return actual
    }
    if let conversion = draft.conversion, !conversion.isBankCharge {
      return try? Money.convert(minor, from: draft.currency, to: trip.homeCurrency, rate: conversion.rate)
    }
    return (try? model.cachedExpenseConversion(minor, from: draft.currency, to: trip.homeCurrency))
      .flatMap { Money.minor($0.homeAmountMinor) }
  }

  private func conversionNote(_ trip: TripSnapshot, draft: ExpenseDraft) -> String {
    let reminder = "You can update the bank charge in \(trip.homeCurrency) anytime."
    if !draft.actualHomeAmount.isEmpty { return "Uses your bank charge. " + reminder }
    if let conversion = draft.conversion, !conversion.isBankCharge {
      return "Rate from \(conversion.rateDate). " + reminder
    }
    return "Automatically converted using the latest available rate. " + reminder
  }

  /// The day's own currency and home, plus whatever the expense already uses.
  private func currencies(_ trip: TripSnapshot, attachment: Attachment, current: String? = nil)
    -> [String]
  {
    let local = trip.stop(for: attachment)?.currency ?? trip.homeCurrency
    var list = attachment.kind == .leg ? [trip.homeCurrency, local] : [local, trip.homeCurrency]
    if let current { list.append(current) }
    var seen = Set<String>()
    return list.filter { seen.insert($0).inserted }
  }

  private func setCurrency(_ currency: String, on draft: inout ExpenseDraft) {
    guard currency != draft.currency else { return }
    if Money.precision(currency) == 0 {
      draft.amount = String(draft.amount.split(separator: ".").first ?? "")
    }
    draft.currency = currency
    draft.conversion = nil
    draft.actualHomeAmount = ""
  }

  private func flag(_ currency: String) -> String {
    if currency == "EUR" { return "🇪🇺" }
    if currency.hasPrefix("X") { return "🌍" }
    return String(currency.prefix(2)).flag
  }

  // MARK: - What

  /// One scrolling row on the phone; beside the keypad they wrap, so every category shows.
  @ViewBuilder private func categoryChips(_ draft: ExpenseDraft) -> some View {
    let categories =
      draft.attachment.kind == .leg ? ExpenseCategory.travelCategories : ExpenseCategory.dayCategories
    let chips = ForEach(categories, id: \.self) { category in
      categoryChip(category, selected: draft.category == category)
    }
    if wideSheet {
      FlowLayout(spacing: 6) { chips }.padding(.horizontal, inset)
    } else {
      ScrollView(.horizontal) {
        HStack(spacing: 7) { chips }.padding(.vertical, 2)
      }
      .scrollIndicators(.hidden)
      .contentMargins(.horizontal, inset, for: .scrollContent)
      .onScrollPhaseChange { _, phase in
        if phase == .interacting { amountFocused = false }
      }
    }
  }

  private func categoryChip(_ category: ExpenseCategory, selected: Bool) -> some View {
    Button {
      Haptics.selection()
      mutate { $0.category = category }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: category.glyph).font(.system(size: wideSheet ? 13 : 14, weight: .semibold))
        Text(category.title)
      }
      .typeface(wideSheet ? 13 : 13.5, .heavy, relativeTo: .footnote, maximum: 1.4)
      .foregroundStyle(selected ? Theme.background : Theme.secondary)
      .padding(.vertical, wideSheet ? 7 : 8).padding(.leading, wideSheet ? 9 : 10)
      .padding(.trailing, wideSheet ? 11 : 12)
      .background(selected ? Theme.ink : Theme.inset, in: Capsule())
      .scaleEffect(selected ? 1.04 : 1)
      .animation(Motion.spring, value: selected)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  // MARK: - Who

  private func panel(_ trip: TripSnapshot, draft: ExpenseDraft) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      if trip.asksReturn(draft.category, on: draft.attachment) {
        row("Ticket") { ticket(draft) }
        if let note = returnNote(trip, draft: draft) {
          Text(note)
            .typeface(12.5, .bold, relativeTo: .caption, maximum: 1.4)
            .foregroundStyle(Theme.secondary).monospacedDigit()
            .padding(.leading, 68)
        }
      }
      row("Status") { status(draft) }
      if trip.hasCompanions {
        row("Paid by") { people(trip, draft: draft, split: false) }
        row("Split") { people(trip, draft: draft, split: true) }
        // The shortcuts drop under the summary when the panel's too narrow for one line.
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 12) {
            splitTotal(draft)
            Spacer(minLength: 4)
            splitShortcuts(trip)
          }
          VStack(alignment: .leading, spacing: 6) {
            splitTotal(draft)
            HStack(spacing: 14) { splitShortcuts(trip) }
          }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accentText)
        .typeface(12.5, .bold, relativeTo: .caption, maximum: 1.4)
        .padding(.leading, 68)
      }
      if draft.currency != trip.homeCurrency {
        row("Bank") {
          TextField(
            "Actual charge in \(trip.homeCurrency), optional",
            text: bind(\.actualHomeAmount, fallback: "")
          )
          .keyboardType(.decimalPad)
          .focused($focusedField, equals: .bank)
          .typeface(14, .bold, relativeTo: .subheadline)
          .foregroundStyle(Theme.ink)
          .padding(.vertical, 7).padding(.horizontal, 12)
          .background(Theme.surface, in: Capsule())
          .accessibilityLabel("Actual charge in \(trip.homeCurrency)")
        }
      }
    }
    .padding(12)
    .background(Theme.inset, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private func splitTotal(_ draft: ExpenseDraft) -> some View {
    Text(splitSummary(draft)).foregroundStyle(Theme.secondary).monospacedDigit()
      .lineLimit(1).minimumScaleFactor(0.8).layoutPriority(1)
      .contentTransition(.numericText())
      .animation(Motion.bump, value: splitSummary(draft))
  }

  @ViewBuilder private func splitShortcuts(_ trip: TripSnapshot) -> some View {
    Button("Just me") { mutate { $0.splitWith = [trip.currentTravellerId] } }
    Button("Everyone") { mutate { $0.splitWith = trip.activeTravellers.map(\.id) } }
  }

  private func row(_ label: String, @ViewBuilder content: () -> some View) -> some View {
    HStack(spacing: 10) {
      Text(label)
        .typeface(13, .heavy, relativeTo: .footnote, maximum: 1.3)
        .foregroundStyle(Theme.secondary)
        .frame(width: 58, alignment: .leading)
        .accessibilityHidden(true)
      content().frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
  }

  private func status(_ draft: ExpenseDraft) -> some View {
    segments([(Expense.Status.paid, "Paid"), (.planned, "Planned")], selected: draft.status) {
      $0.status = $1
    }
  }

  /// Travel booked before you go is a return unless it's one way, like the watch asks.
  private func ticket(_ draft: ExpenseDraft) -> some View {
    segments([(true, "Return"), (false, "One way")], selected: draft.isReturn) {
      $0.coversReturn = $1
    }
  }

  /// "£210.00 there · £210.00 home" under the ticket choice, so the split shows before saving.
  private func returnNote(_ trip: TripSnapshot, draft: ExpenseDraft) -> String? {
    guard draft.isReturn, trip.asksReturn(draft.category, on: draft.attachment) else { return nil }
    let minor = amount(draft)
    guard minor > 0 else { return "Half there · half home" }
    let out = Money.format(minor - minor / 2, draft.currency)
    let back = Money.format(minor / 2, draft.currency)
    return "\(out) there · \(back) home"
  }

  private func segments<Value: Hashable>(
    _ options: [(Value, String)], selected current: Value,
    set: @escaping (inout ExpenseDraft, Value) -> Void
  ) -> some View {
    HStack(spacing: 4) {
      ForEach(options, id: \.0) { option in
        let value = option.0
        let selected = current == value
        Button(option.1) {
          Haptics.selection()
          mutate { set(&$0, value) }
        }
        .buttonStyle(.plain)
        .typeface(13, .heavy, relativeTo: .footnote, maximum: 1.4)
        .foregroundStyle(selected ? Theme.ink : Theme.secondary)
        .padding(.vertical, 6).padding(.horizontal, 14)
        .background {
          if selected {
            Capsule().fill(Theme.surface).shadow(color: .black.opacity(0.12), radius: 2, y: 1)
          }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
    .padding(3)
    .background(Theme.line, in: Capsule())
    .animation(.easeOut(duration: 0.25), value: current)
  }

  private func people(_ trip: TripSnapshot, draft: ExpenseDraft, split: Bool) -> some View {
    ScrollView(.horizontal) {
      HStack(spacing: 6) {
        ForEach(trip.activeTravellers) { person in
          let selected = split ? draft.splitWith.contains(person.id) : draft.paidBy == person.id
          Button {
            Haptics.selection()
            mutate {
              if !split {
                $0.paidBy = person.id
              } else if $0.splitWith.contains(person.id) {
                $0.splitWith.removeAll { $0 == person.id }
              } else {
                let chosen = Set($0.splitWith + [person.id])
                $0.splitWith = trip.activeTravellers.map(\.id).filter(chosen.contains)
              }
            }
          } label: {
            HStack(spacing: 6) {
              Avatar(traveller: person, size: wideSheet ? 24 : 26)
              Text(person.id == trip.currentTravellerId ? "You" : person.name)
                .typeface(wideSheet ? 12.5 : 13, .heavy, relativeTo: .footnote, maximum: 1.3)
                .foregroundStyle(Theme.ink)
            }
            .padding(.leading, 3).padding(.trailing, wideSheet ? 10 : 11)
            .frame(height: wideSheet ? 30 : 32)
            .background(selected ? Theme.surface : .clear, in: Capsule())
            .overlay { if selected { Capsule().strokeBorder(Theme.accent, lineWidth: 2) } }
            .opacity(selected ? 1 : split ? 0.45 : 0.55)
            .scaleEffect(split && !selected ? 0.96 : 1)
            .animation(Motion.spring, value: selected)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(person.name)
          .accessibilityAddTraits(selected ? .isSelected : [])
        }
      }
      .padding(2)
    }
    .scrollIndicators(.hidden)
  }

  /// "€3.20 each · 2 people", a range when the split doesn't divide evenly.
  private func splitSummary(_ draft: ExpenseDraft) -> String {
    let count = draft.splitWith.count
    guard count > 0 else { return "Pick at least one" }
    let minor = amount(draft)
    guard minor > 0 else { return "Split between \(count)" }
    let shares = Money.split(minor, among: draft.splitWith).values
    let low = Money.format(shares.min() ?? 0, draft.currency)
    let high = Money.format(shares.max() ?? 0, draft.currency)
    return "\(low == high ? low : "\(low)–\(high)") each · \(count) \(count == 1 ? "person" : "people")"
  }

  // MARK: - State

  private func focusAmount() {
    focusedField = nil
    amountFocused = true
  }

  private func bind<T>(_ keyPath: WritableKeyPath<ExpenseDraft, T>, fallback: T) -> Binding<T> {
    Binding(
      get: { model.expenseDraft?[keyPath: keyPath] ?? fallback },
      set: { value in mutate { $0[keyPath: keyPath] = value } })
  }

  private func mutate(_ update: (inout ExpenseDraft) -> Void) {
    guard var draft = model.expenseDraft else { return }
    update(&draft)
    model.expenseDraft = draft
    model.persistDraft()
  }

  private func cancel() {
    model.persistDraft()
    dismiss()
  }

  private func delete(_ draft: ExpenseDraft, trip: TripSnapshot) {
    model.perform {
      guard let expense = trip.expenses.first(where: { $0.id == draft.expenseID }) else { return }
      try model.deleteExpense(expense, trip: trip)
      try model.store.removeDocument("expense:" + trip.id)
      model.changed()
      model.notify("Deleted")
      dismiss()
    }
  }

  private func save() {
    guard let draft = model.expenseDraft, valid(draft) else { return }
    focusedField = nil
    saving = true
    localError = nil
    Task {
      do {
        let editing = draft.expenseID != nil
        let result = try await model.saveExpense()
        saving = false
        Haptics.success()
        if editing {
          model.notify("Saved")
          dismiss()
        } else {
          withAnimation(reduceMotion ? nil : Motion.push) { saved = result }
        }
      } catch {
        saving = false
        Haptics.error()
        localError = error.localizedDescription
      }
    }
  }

  /// "£42.10 added to Day 3", once, however the receipt goes away.
  private func announce(_ expense: Expense, trip: TripSnapshot) {
    guard !announced else { return }
    announced = true
    let amount =
      expense.homeMinor(in: trip.homeCurrency).map { Money.format($0, trip.homeCurrency) }
      ?? Money.format(Money.minor(expense.amountMinor) ?? 0, expense.currency)
    let destination = expense.dayIds.map { "\($0.count) days" }
      ?? trip.shortTitle(for: expense.attachment)
    model.notify("\(amount) added to \(destination)")
  }
}
