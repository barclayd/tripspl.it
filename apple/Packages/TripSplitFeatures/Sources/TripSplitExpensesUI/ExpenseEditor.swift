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
        .navigationTitle(heading(draft))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(usesVerticalRail && saved == nil ? .automatic : .hidden, for: .navigationBar)
        .toolbar {
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

  @ViewBuilder private func form(_ trip: TripSnapshot, draft: ExpenseDraft) -> some View {
    let keypad = NumberPad(
      value: bind(\.amount, fallback: ""), currency: draft.currency, keyHeight: 52, spacing: 4)
    VStack(spacing: 0) {
      if !usesVerticalRail { header(draft).padding(.horizontal, 18) }
      if wideSheet {
        HStack(alignment: .bottom, spacing: 24) {
          ScrollView { fields(trip, draft: draft) }.scrollDismissesKeyboard(.interactively)
          keypad.frame(width: 200).padding(.bottom, 12).padding(.trailing, 18)
        }
      } else {
        ScrollView { fields(trip, draft: draft) }.scrollDismissesKeyboard(.interactively)
        keypad.padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 4)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onGeometryChange(for: Bool.self) { $0.size.width >= 590 } action: { wideSheet = $0 }
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
          .foregroundStyle(ready ? Theme.accentInk : Theme.tertiary)
          .padding(.vertical, 8).padding(.horizontal, 15)
          .background(ready ? Theme.accent : Theme.inset, in: Capsule())
          .animation(.easeOut(duration: 0.25), value: ready)
          .disabled(!ready)
      }
      .frame(width: 90, alignment: .trailing)
    }
    .buttonStyle(.plain)
    .frame(height: 44)
  }

  private func fields(_ trip: TripSnapshot, draft: ExpenseDraft) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      dayChips(trip, draft: draft).padding(.top, 2)
      amountBlock(trip, draft: draft).padding(.top, 2).padding(.bottom, -2)
      TextField(
        draft.attachment.kind == .leg ? "e.g. Taxi to the airport" : "What was it?",
        text: bind(\.title, fallback: "")
      )
      .typeface(16, .bold, relativeTo: .body)
      .foregroundStyle(Theme.ink)
      .submitLabel(.done)
      .padding(.vertical, 13).padding(.horizontal, 16)
      .background(Theme.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .padding(.horizontal, 18)
      categoryChips(draft)
      panel(trip, draft: draft).padding(.horizontal, 18)
      if draft.currency != trip.homeCurrency {
        Text(
          draft.conversion.map { "Saved rate: \($0.rate) · \($0.source) · \($0.rateDate)" }
            ?? "We’ll try the reference rate when saving. Without a rate, this expense stays visible with conversion pending."
        )
        .typeface(12, .semibold, relativeTo: .caption)
        .foregroundStyle(Theme.tertiary)
        .padding(.horizontal, 22)
      }
      if let localError {
        Text(localError).typeface(13, .semibold, relativeTo: .footnote)
          .foregroundStyle(Theme.bad).padding(.horizontal, 22)
      }
    }
    .padding(.bottom, 8)
  }

  // MARK: - When

  /// Every day and leg in itinerary order, so an expense can move to another day.
  private func dayChips(_ trip: TripSnapshot, draft: ExpenseDraft) -> some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal) {
        HStack(spacing: 6) {
          ForEach(options(trip), id: \.attachment.id) { option in
            let selected = option.attachment == draft.attachment
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
            .id(option.attachment.id)
          }
        }
      }
      .scrollIndicators(.hidden)
      .contentMargins(.horizontal, 18, for: .scrollContent)
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
      $0.attachment = attachment
      let offered = currencies(trip, attachment: attachment)
      if !offered.contains($0.currency) { setCurrency(offered[0], on: &$0) }
      let travel = attachment.kind == .leg
      let categories = travel ? ExpenseCategory.travelCategories : ExpenseCategory.dayCategories
      if !categories.contains($0.category) { $0.category = travel ? .flight : .food }
    }
  }

  // MARK: - How much

  private func amountBlock(_ trip: TripSnapshot, draft: ExpenseDraft) -> some View {
    let minor = amount(draft)
    let shown = display(draft.amount, currency: draft.currency)
    return VStack(spacing: 12) {
      Text(shown)
        .typeface(58, .bold, tracking: -0.05, relativeTo: .largeTitle, maximum: 1.2)
        .monospacedDigit()
        .foregroundStyle(minor > 0 ? Theme.ink : Theme.tertiary)
        .lineLimit(1).minimumScaleFactor(0.5)
        .bump(on: shown)
        .padding(.horizontal, 18)
        .accessibilityLabel("Amount, \(shown)")
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
      .contentMargins(.horizontal, 18, for: .scrollContent)
      .defaultScrollAnchor(.center, for: .alignment)
    }
    .frame(maxWidth: .infinity)
  }

  /// "£1,234.5" as typed, grouping the whole part and keeping the decimals the keypad has so far.
  private func display(_ amount: String, currency: String) -> String {
    let parts = amount.split(separator: ".", omittingEmptySubsequences: false)
    let whole = Int64(parts.first.map(String.init) ?? "") ?? 0
    var text = Money.format(whole * Money.factor(currency), currency, compact: true)
    if parts.count > 1, text.last?.isNumber == true { text += "." + parts[1] }
    return text
  }

  private func estimate(_ trip: TripSnapshot, draft: ExpenseDraft, minor: Int64) -> Int64? {
    guard draft.currency != trip.homeCurrency else { return nil }
    if let actual = try? Money.parse(draft.actualHomeAmount, currency: trip.homeCurrency), actual > 0 {
      return actual
    }
    if let rate = draft.conversion?.rate {
      return try? Money.convert(minor, from: draft.currency, to: trip.homeCurrency, rate: rate)
    }
    return trip.estimate(minor, from: draft.currency)
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

  private func categoryChips(_ draft: ExpenseDraft) -> some View {
    let categories =
      draft.attachment.kind == .leg ? ExpenseCategory.travelCategories : ExpenseCategory.dayCategories
    return ScrollView(.horizontal) {
      HStack(spacing: 7) {
        ForEach(categories, id: \.self) { category in
          let selected = draft.category == category
          Button {
            Haptics.selection()
            mutate { $0.category = category }
          } label: {
            HStack(spacing: 6) {
              Image(systemName: category.glyph).font(.system(size: 14, weight: .semibold))
              Text(category.title)
            }
            .typeface(13.5, .heavy, relativeTo: .footnote, maximum: 1.4)
            .foregroundStyle(selected ? Theme.background : Theme.secondary)
            .padding(.vertical, 8).padding(.leading, 10).padding(.trailing, 12)
            .background(selected ? Theme.ink : Theme.inset, in: Capsule())
            .scaleEffect(selected ? 1.04 : 1)
            .animation(Motion.spring, value: selected)
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(selected ? .isSelected : [])
        }
      }
      .padding(.vertical, 2)
    }
    .scrollIndicators(.hidden)
    .contentMargins(.horizontal, 18, for: .scrollContent)
  }

  // MARK: - Who

  private func panel(_ trip: TripSnapshot, draft: ExpenseDraft) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      row("Status") { status(draft) }
      row("Paid by") { people(trip, draft: draft, split: false) }
      row("Split") { people(trip, draft: draft, split: true) }
      HStack(spacing: 12) {
        Text(splitSummary(draft)).foregroundStyle(Theme.secondary).monospacedDigit()
          .lineLimit(1).minimumScaleFactor(0.8).layoutPriority(1)
          .contentTransition(.numericText())
          .animation(Motion.bump, value: splitSummary(draft))
        Spacer(minLength: 4)
        Button("Just me") { mutate { $0.splitWith = [trip.currentTravellerId] } }
        Button("Everyone") { mutate { $0.splitWith = trip.activeTravellers.map(\.id) } }
      }
      .buttonStyle(.plain)
      .foregroundStyle(Theme.accentText)
      .typeface(12.5, .bold, relativeTo: .caption, maximum: 1.4)
      .padding(.leading, 68)
      if draft.currency != trip.homeCurrency {
        row("Charged") {
          TextField(
            "Card charge in \(trip.homeCurrency), optional",
            text: bind(\.actualHomeAmount, fallback: "")
          )
          .keyboardType(.decimalPad)
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
    HStack(spacing: 4) {
      ForEach([Expense.Status.paid, .planned], id: \.self) { value in
        let selected = draft.status == value
        Button(value == .paid ? "Paid" : "Planned") {
          Haptics.selection()
          mutate { $0.status = value }
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
    .animation(.easeOut(duration: 0.25), value: draft.status)
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
              Avatar(traveller: person, size: 26)
              Text(person.id == trip.currentTravellerId ? "You" : person.name)
                .typeface(13, .heavy, relativeTo: .footnote, maximum: 1.3)
                .foregroundStyle(Theme.ink)
            }
            .padding(.leading, 3).padding(.trailing, 11)
            .frame(height: 32)
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
      try model.store.deleteExpense(expense, tripID: trip.id)
      try model.store.removeDocument("expense:" + trip.id)
      model.changed()
      model.notify("Deleted")
      dismiss()
    }
  }

  private func save() {
    guard let draft = model.expenseDraft, valid(draft) else { return }
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
    model.notify("\(amount) added to \(trip.shortTitle(for: expense.attachment))")
  }
}
