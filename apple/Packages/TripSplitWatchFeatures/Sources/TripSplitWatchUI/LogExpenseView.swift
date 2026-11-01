import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign
import TripSplitWatchModel

/// Log expense, presented as a sheet: which trip from Trips (F1), which day for a trip still to come
/// (F6), how much (F2), what it was (F3) and, with others on the trip, who shares it (F4), then
/// the receipt (F5).
struct LogExpenseView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var log: LogExpense
  @State private var path: [LogRoute] = []
  @State private var receipt: LogExpense.Receipt?
  @State private var savedOffline = false
  /// Where the flow opened, fixed so choosing a trip doesn't swap the screen underneath.
  private let start: LogExpense.Step

  init(model: WatchModel, trip: TripSnapshot? = nil, editing: Expense? = nil) {
    self.init(log: LogExpense(model: model, trip: trip, editing: editing))
  }

  init(log: LogExpense, path: [LogRoute] = []) {
    _log = State(initialValue: log)
    _path = State(initialValue: path)
    start = log.start
  }

  var body: some View {
    if let receipt {
      LoggedView(
        receipt: receipt, savedOffline: savedOffline,
        rateNote: LogExpense.rateNote(receipt.rateDate, now: log.model.now)
      ) { dismiss() }
    } else {
      NavigationStack(path: $path) {
        screen(for: start)
          .navigationDestination(for: LogRoute.self) { route in
            switch route {
            case .step(let step): screen(for: step)
            case .keypad:
              let home = log.homeMinor.map { "≈ " + WatchCurrency.format($0, log.home) }
              AmountKeypad(
                code: log.currency, currency: log.info(log.currency),
                result: log.currency == log.home ? nil : home ?? "—", amount: $log.amount,
                detent: log.amountDetent, detents: LogExpense.detentCount, dial: log.dial(to:))
            }
          }
      }
      // Toolbar buttons sit on the card fill rather than the accent, as in the design.
      .tint(WatchTheme.card2)
    }
  }

  @ViewBuilder private func screen(for step: LogExpense.Step) -> some View {
    switch step {
    case .trip:
      TripChoiceView(log: log) { trip in
        log.choose(trip)
        advance(from: .trip)
      }
    case .day:
      DayChoiceView(log: log) { attachment in
        log.choose(attachment)
        advance(from: .day)
      }
    case .amount:
      AmountStepView(log: log, path: $path)
    case .category:
      CategoryStepView(log: log) { category in
        log.category = category
        advance(from: .category)
      }
    case .split:
      SplitStepView(log: log, save: save)
    }
  }

  /// On to the next step, or saves when that was the last, e.g. the category on a solo trip.
  private func advance(from step: LogExpense.Step) {
    if let next = log.step(after: step) {
      path.append(.step(next))
    } else {
      save()
    }
  }

  private func save() {
    let offline = !log.model.isPhoneReachable
    guard let saved = log.save() else { return }
    savedOffline = offline
    withAnimation(.snappy) { receipt = saved }
  }
}

enum LogRoute: Hashable {
  case step(LogExpense.Step)
  case keypad
}

// MARK: F1 · F6

/// F1 · Log for… The trip happening now first, in the accent, then those still to come.
struct TripChoiceView: View {
  let log: LogExpense
  let choose: (TripSnapshot) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 6) {
        StepTitle("Log for…")
        ForEach(log.trips) { trip in
          Button {
            choose(trip)
          } label: {
            ChoiceRow(
              title: trip.name, detail: log.detail(for: trip), flag: log.flag(for: trip),
              highlighted: trip.id == log.suggestedTripID)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .containerBackground(.black, for: .navigation)
  }
}

/// F6 · Which day? Costs before you go first, then each day, for a trip still to come.
struct DayChoiceView: View {
  let log: LogExpense
  let choose: (Attachment) -> Void

  var body: some View {
    let options = log.dayOptions
    ScrollView {
      VStack(alignment: .leading, spacing: 6) {
        StepTitle("Which day?")
        ForEach(options) { option in
          Button {
            choose(option.attachment)
          } label: {
            ChoiceRow(
              title: option.title, detail: option.detail, flag: nil,
              highlighted: option.id == options.first?.id)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .toolbar {
      if let trip = log.trip {
        ToolbarItem(placement: .topBarTrailing) {
          Text(log.flag(for: trip)).font(.system(size: 16)).accessibilityHidden(true)
        }
      }
    }
    .containerBackground(.black, for: .navigation)
  }
}

struct StepTitle: View {
  let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title)
      .watchFont(17, .black)
      .padding(.horizontal, 6)
      .accessibilityAddTraits(.isHeader)
  }
}

/// A trip or day to log against: accent when it's the suggestion, otherwise on the card fill.
struct ChoiceRow: View {
  let title: String
  let detail: String
  let flag: String?
  let highlighted: Bool

  var body: some View {
    HStack(spacing: 10) {
      if let flag, !flag.isEmpty {
        Text(flag).font(.system(size: 16)).accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 1) {
        Text(title).watchFont(15, .black)
        Text(detail)
          .watchFont(11, .heavy)
          .foregroundStyle(highlighted ? .white.opacity(0.85) : WatchTheme.ink2)
      }
      .lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .frame(height: 54)
    .background(highlighted ? WatchTheme.accent : WatchTheme.card, in: .rect(cornerRadius: 18))
    .contentShape(.rect(cornerRadius: 18))
    .accessibilityElement(children: .combine)
  }
}

// MARK: F2

/// F2 · How much? Today's stop currency or home, dialled on the Crown in the same detents as
/// quick convert, or typed on the keypad.
struct AmountStepView: View {
  let log: LogExpense
  @Binding var path: [LogRoute]
  @State private var crown = 0.0
  @FocusState private var crownFocused: Bool

  var body: some View {
    let currencies = log.currencies
    let home = log.homeMinor.map { "≈ " + WatchCurrency.format($0, log.home) }
    VStack(spacing: 0) {
      if currencies.count > 1 {
        Segmented(
          options: currencies.map { code in
            let currency = log.info(code)
            return .init(id: code, label: "\(currency.flag) \(code)")
          },
          selection: log.currency, fill: WatchTheme.card2, size: 13, height: 26
        ) { code in
          withAnimation(.snappy) { log.select(currency: code) }
        }
        .fixedSize()
      }
      Button {
        path.append(.keypad)
      } label: {
        VStack(spacing: 0) {
          Text(WatchCurrency.format(log.amountMinor, log.currency, compact: true))
            .watchFont(52, .black)
            .tracking(em: -0.02, size: 52)
            .contentTransition(.numericText(value: Double(log.amountMinor)))
          if log.currency != log.home {
            Text(home ?? "No rate yet")
              .watchFont(14, .black)
              .foregroundStyle(home == nil ? WatchTheme.ink3 : WatchTheme.accentText)
              .contentTransition(.numericText(value: Double(log.homeMinor ?? 0)))
          }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .padding(.top, 4)
      .accessibilityLabel(WatchCurrency.format(log.amountMinor, log.currency))
      .accessibilityHint("Turn the Digital Crown to change, or double tap to type")
      Spacer(minLength: 4)
      Button {
        path.append(.step(.category))
      } label: {
        Text("Next").watchFont(17, .black)
      }
      .buttonStyle(PrimaryButtonStyle(height: 40))
      .disabled(log.amountMinor <= 0)
    }
    .padding(.horizontal, 6)
    .padding(.top, -8)
    .ignoresSafeArea(edges: .bottom)
    .focusable()
    .focused($crownFocused)
    .focusEffectDisabled()
    .digitalCrownRotation(
      detent: $crown, from: 0, through: Double(LogExpense.detentCount - 1), by: 1,
      sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true
    )
    .onChange(of: crown) { _, value in
      let detent = Int(value.rounded())
      if detent != log.amountDetent { withAnimation(.snappy) { log.dial(to: detent) } }
    }
    .onChange(of: log.amountDetent) { _, detent in
      if crown != Double(detent) { crown = Double(detent) }
    }
    .onAppear {
      crown = Double(log.amountDetent)
      crownFocused = true
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          path.append(.keypad)
        } label: {
          Image(systemName: "circle.grid.3x3.fill").foregroundStyle(.white)
        }
        .accessibilityLabel("Type an amount")
      }
    }
    .containerBackground(.black, for: .navigation)
  }
}

// MARK: F3

/// F3 · What was it? Six everyday categories, with the rest a Crown turn away. One tap picks and
/// moves on.
struct CategoryStepView: View {
  let log: LogExpense
  let choose: (ExpenseCategory) -> Void

  var body: some View {
    ScrollView {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 10)
      {
        ForEach(ExpenseCategory.watchOrder, id: \.self) { category in
          Button {
            choose(category)
          } label: {
            CategoryTile(category: category, selected: category == log.category)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.top, 4)
    }
    .toolbar { AmountBadge(log: log) }
    .containerBackground(.black, for: .navigation)
  }
}

struct CategoryTile: View {
  let category: ExpenseCategory
  let selected: Bool

  var body: some View {
    VStack(spacing: 5) {
      Image(systemName: category.symbol)
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(category.tileGlyph)
        .frame(width: 50, height: 50)
        .background(category.tileBackground, in: .circle)
        .padding(4.5)
        .overlay {
          // A white ring with a black gap, so it reads on every tile colour.
          if selected { Circle().strokeBorder(.white, lineWidth: 2) }
        }
        .padding(-4.5)
      Text(category.watchTitle)
        .watchFont(10, .heavy)
        .foregroundStyle(selected ? .white : WatchTheme.ink2)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity)
    .contentShape(.rect)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(category.watchTitle)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// The amount, pink, top-right while picking the category and the split.
struct AmountBadge: ToolbarContent {
  let log: LogExpense

  var body: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Text(WatchCurrency.format(log.amountMinor, log.currency, compact: true))
        .watchFont(14, .black)
        .foregroundStyle(WatchTheme.accentText)
        .lineLimit(1)
        .fixedSize()
    }
  }
}

// MARK: F4

/// F4 · Shared or just me? Paid by you and shared with everyone unless you say otherwise.
struct SplitStepView: View {
  let log: LogExpense
  let save: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Segmented(
        options: [.init(id: "shared", label: "Shared"), .init(id: "me", label: "Just me")],
        selection: log.isShared ? "shared" : "me", fill: WatchTheme.accent
      ) { id in
        withAnimation(.snappy) { log.isShared = id == "shared" }
      }
      if log.isShared, let trip = log.trip {
        let people = trip.activeTravellers
        PeopleRow(title: "Paid by") {
          ForEach(people) { traveller in
            Button {
              withAnimation(.snappy) { log.paidBy = traveller.id }
            } label: {
              SplitAvatar(
                traveller: traveller, isYou: traveller.id == trip.currentTravellerId,
                on: true, ringed: log.paidBy == traveller.id)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Paid by \(log.name(traveller.id))")
            .accessibilityAddTraits(log.paidBy == traveller.id ? .isSelected : [])
          }
        }
        .padding(.top, 12)
        PeopleRow(title: "Split with") {
          ForEach(people) { traveller in
            let on = log.splitWith.contains(traveller.id)
            Button {
              withAnimation(.snappy) { log.toggle(traveller.id) }
            } label: {
              SplitAvatar(
                traveller: traveller, isYou: traveller.id == trip.currentTravellerId, on: on,
                ringed: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Split with \(log.name(traveller.id))")
            .accessibilityValue(on ? "On" : "Off")
          }
        }
        .padding(.top, 8)
      }
      Spacer(minLength: 4)
      Button(action: save) {
        VStack(spacing: 0) {
          Text("Save").watchFont(17, .black)
          if log.sharers.count > 1, let each = log.each {
            Text("\(WatchCurrency.format(each.minor, each.currency)) each")
              .watchFont(11, .heavy)
              .contentTransition(.numericText(value: Double(each.minor)))
          }
        }
      }
      .buttonStyle(PrimaryButtonStyle(height: 42))
      .disabled(!log.canSave)
    }
    .padding(.horizontal, 6)
    .padding(.top, -6)
    .ignoresSafeArea(edges: .bottom)
    .toolbar { AmountBadge(log: log) }
    .containerBackground(.black, for: .navigation)
  }
}

/// "Paid by" or "Split with", then avatars, scrolling sideways past four people.
struct PeopleRow<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    HStack(spacing: 6) {
      Text(title)
        .watchFont(12, .heavy)
        .foregroundStyle(WatchTheme.ink2)
        .lineLimit(1)
        .fixedSize()
        .frame(width: 66, alignment: .leading)
        .padding(.leading, 6)
      ScrollView(.horizontal) {
        HStack(spacing: 4) { content }.padding(3)
      }
      .scrollIndicators(.hidden)
      .defaultScrollAnchor(.trailing)
    }
  }
}

/// A traveller's avatar, grey when they're left out, with a white ring for whoever paid.
struct SplitAvatar: View {
  let traveller: Traveller
  let isYou: Bool
  let on: Bool
  let ringed: Bool

  var body: some View {
    Group {
      if on {
        WatchAvatar(traveller, isYou: isYou, size: 28)
      } else {
        Text(isYou ? "Y" : traveller.name.prefix(1).uppercased())
          .font(.system(size: 12, weight: .black, design: .rounded))
          .foregroundStyle(WatchTheme.ink2)
          .frame(width: 28, height: 28)
          .background(WatchTheme.card2, in: .circle)
      }
    }
    .padding(2.5)
    .overlay {
      if ringed { Circle().strokeBorder(.white, lineWidth: 2) }
    }
    .contentShape(.circle)
  }
}

// MARK: Shared pieces

/// A two- or three-way toggle on a dark track, the selection filled.
struct Segmented: View {
  struct Option: Identifiable {
    let id: String
    let label: String
  }

  let options: [Option]
  let selection: String
  let fill: Color
  var size: CGFloat = 14
  var height: CGFloat = 32
  let select: (String) -> Void
  @Namespace private var namespace

  var body: some View {
    HStack(spacing: 0) {
      ForEach(options) { option in
        let selected = option.id == selection
        Button {
          select(option.id)
        } label: {
          Text(option.label)
            .watchFont(size, .black)
            .foregroundStyle(selected ? .white : WatchTheme.ink2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
              if selected {
                Capsule().fill(fill).matchedGeometryEffect(id: "selection", in: namespace)
              }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
    .padding(3)
    .background(WatchTheme.card, in: .capsule)
  }
}

/// The accent capsule that moves the flow on: "Next" or "Save".
struct PrimaryButtonStyle: ButtonStyle {
  let height: CGFloat
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .background(isEnabled ? WatchTheme.accent : WatchTheme.card2, in: .capsule)
      .contentShape(.capsule)
      .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.6)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.snappy(duration: 0.15), value: configuration.isPressed)
      .padding(.horizontal, 8)
      .padding(.bottom, 10)
  }
}
