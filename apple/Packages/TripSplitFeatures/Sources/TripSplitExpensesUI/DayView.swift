import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitPersistence
import TripSplitSharedUI

/// One itinerary day or travel leg: where you are, what it cost, and every expense on it.
public struct DayView: View {
  public init(tripID: String, attachment: Attachment, showsPaneControls: Bool = false) {
    self.tripID = tripID
    self.attachment = attachment
    self.showsPaneControls = showsPaneControls
  }
  @Environment(AppModel.self) private var model
  @Environment(\.horizontalSizeClass) private var sizeClass
  var tripID: String
  var attachment: Attachment
  /// Two panes show, so the day floats its own Close and Full screen buttons.
  var showsPaneControls = false
  @State private var usesVerticalRail = false
  @State private var landscape = false
  /// Tent: compact width but wider than tall, so the summary and list sit side by side.
  private var tent: Bool { sizeClass == .compact && landscape }
  /// Expenses already on screen, so one that arrives from the sheet can flash.
  @State private var seen: Set<String>?
  @State private var fresh: Set<String> = []

  public var body: some View {
    if let trip = model.store.trip(tripID) {
      let items = trip.expenses(for: attachment)
      ZStack {
        if tent {
          tentLayout(trip, items: items)
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 18) {
              summary(trip, items: items)
              list(trip, items: items)
            }
            .pagePadding().padding(.bottom, 18)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Theme.background)
      .scrollEdgeEffectHidden(showsPaneControls, for: .top)
      .onGeometryChange(for: Bool.self) {
        $0.size.width > $0.size.height
      } action: {
        landscape = $0
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if !usesVerticalRail && !tent { actions(trip) }
      }
      .safeAreaInset(edge: .top) {
        if showsPaneControls {
          HStack {
            Button("Close day", systemImage: "xmark") {
              model.selectedAttachment = nil
              model.fullScreenDay = false
            }
            Spacer()
            Button(
              model.fullScreenDay ? "Show trip alongside" : "Full screen",
              systemImage: model.fullScreenDay
                ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
            ) { model.fullScreenDay.toggle() }
          }
          .labelStyle(.iconOnly).buttonStyle(.glass).padding(.horizontal, 20).padding(.vertical, 4)
        }
      }
      .onChange(of: items.map(\.id), initial: true) { _, ids in noticeNew(ids) }
      .onChange(of: model.expenseDraft == nil) { _, closed in
        if closed { noticeNew(items.map(\.id)) }
      }
      .readVerticalRail($usesVerticalRail)
      .taskRail()
    }
  }

  private var addTitle: String { attachment.kind == .leg ? "Add travel" : "Add expense" }

  private func leg(_ trip: TripSnapshot) -> TravelLeg? {
    attachment.kind == .leg ? trip.legs.first { $0.id == attachment.id } : nil
  }

  /// Flashes expenses that appeared since the last look, once the sheet is out of the way.
  private func noticeNew(_ ids: [String]) {
    guard model.expenseDraft == nil else { return }
    let current = Set(ids)
    defer { seen = current }
    guard let seen else { return }
    let added = current.subtracting(seen)
    guard !added.isEmpty else { return }
    fresh.formUnion(added)
    Task {
      try? await Task.sleep(for: .seconds(1.6))
      fresh.subtract(added)
    }
  }

  private func isToday(_ trip: TripSnapshot) -> Bool {
    trip.days.first { $0.id == attachment.id }.map { trip.isToday($0) } ?? false
  }

  // MARK: - Tent

  /// Standing on a table: the day's number at display size on the leading side, its items on the
  /// trailing side, and nothing important on the bottom edge.
  private func tentLayout(_ trip: TripSnapshot, items: [Expense]) -> some View {
    HStack(alignment: .top, spacing: 24) {
      tentSummary(trip, items: items)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      VStack(spacing: 10) {
        ScrollView {
          list(trip, items: items, compact: true).padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        // Without the rail, the actions sit under the list rather than along the bottom edge.
        if !usesVerticalRail { actionButtons(trip) }
      }
      .frame(maxWidth: .infinity)
    }
    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)
  }

  private func tentSummary(_ trip: TripSnapshot, items: [Expense]) -> some View {
    let ledger = Ledger(trip, expenses: items)
    let today = isToday(trip)
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Group {
          if let leg = leg(trip) {
            Image(systemName: symbol(leg)).font(.system(size: 22, weight: .semibold))
              .foregroundStyle(Theme.accentText)
          } else {
            Text(trip.stop(for: attachment)?.flag ?? "🌍").font(.system(size: 28))
          }
        }
        .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 1) {
          Text(kicker(trip))
            .typeface(11, .black, tracking: 0.06, relativeTo: .caption, maximum: 1.4)
            .foregroundStyle(Theme.accentText)
          Text(place(trip))
            .typeface(17, .heavy, relativeTo: .headline, maximum: 1.4)
            .foregroundStyle(Theme.ink).lineLimit(1)
            .accessibilityAddTraits(.isHeader)
        }
      }
      Spacer(minLength: 12)
      VStack(alignment: .leading, spacing: 0) {
        Text(today ? "Today, paid + planned" : "Spent + planned")
          .typeface(14, .bold, relativeTo: .subheadline, maximum: 1.4)
          .foregroundStyle(Theme.secondary)
        MoneyText(amount: ledger.total, currency: trip.homeCurrency, size: 92, weight: .heavy)
      }
      Spacer(minLength: 12)
      VStack(alignment: .leading, spacing: 8) {
        if attachment.kind == .day, trip.dailyBudget > 0 {
          let budget = trip.dailyBudget
          let over = ledger.total > budget
          let day = today ? "today’s" : "the day’s"
          BudgetBar(
            paid: ledger.paid, planned: ledger.planned, budget: budget, currency: trip.homeCurrency
          )
          .frame(maxWidth: 240)
          Text(
            "\(Money.whole(abs(budget - ledger.total), trip.homeCurrency)) \(over ? "over" : "left of") \(day) \(Money.whole(budget, trip.homeCurrency))"
          )
          .foregroundStyle(over ? Theme.bad : Theme.secondary)
        } else if let local = local(trip, items: items) {
          Text(local).foregroundStyle(Theme.secondary)
        }
        if ledger.unresolved > 0 {
          Label(
            "\(ledger.unresolved) conversion\(ledger.unresolved == 1 ? "" : "s") pending",
            systemImage: "exclamationmark.circle"
          )
          .foregroundStyle(Theme.bad)
        }
      }
      .typeface(14, .heavy, relativeTo: .subheadline, maximum: 1.4).monospacedDigit()
    }
  }

  /// "Porto, Portugal" for a day, or the leg's title.
  private func place(_ trip: TripSnapshot) -> String {
    guard attachment.kind == .day, let stop = trip.stop(for: attachment) else {
      return trip.title(for: attachment)
    }
    let name = CountryMetadata.country(stop.countryCode)?.name ?? stop.place
    return name == stop.place ? name : "\(stop.place), \(name)"
  }

  // MARK: - Summary

  private func summary(_ trip: TripSnapshot, items: [Expense]) -> some View {
    VStack(alignment: .leading, spacing: 22) {
      header(trip)
      total(trip, items: items)
    }
  }

  private func header(_ trip: TripSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 14) {
        tile(trip).popIn(delay: 0.05)
        Text(kicker(trip))
          .typeface(13, .black, tracking: 0.06, relativeTo: .footnote, maximum: 1.4)
          .foregroundStyle(Theme.accentText)
      }
      Text(trip.title(for: attachment))
        .typeface(30, .heavy, tracking: -0.035, relativeTo: .largeTitle, maximum: 1.3)
        .foregroundStyle(Theme.ink)
        .padding(.top, 14)
        .accessibilityAddTraits(.isHeader)
      if let subtitle = subtitle(trip) {
        Text(subtitle)
          .typeface(14.5, .semibold, relativeTo: .subheadline)
          .foregroundStyle(Theme.secondary)
          .padding(.top, 6)
      }
    }
  }

  private func tile(_ trip: TripSnapshot) -> some View {
    Group {
      if let leg = leg(trip) {
        Image(systemName: symbol(leg)).font(.system(size: 24, weight: .semibold))
          .foregroundStyle(Theme.accentText)
      } else {
        Text(trip.stop(for: attachment)?.flag ?? "🌍").font(.system(size: 34))
      }
    }
    .frame(width: 58, height: 58)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    .accessibilityHidden(true)
  }

  private func symbol(_ leg: TravelLeg) -> String {
    switch leg.kind {
    case .outbound: "airplane.departure"
    case .return: "airplane.arrival"
    case .transfer: "tram"
    }
  }

  /// "DAY 4 OF 9 · TODAY", or where a leg sits in the trip.
  private func kicker(_ trip: TripSnapshot) -> String {
    func number(_ id: String) -> String? {
      trip.days.firstIndex { $0.id == id }.map { "DAY \($0 + 1) OF \(trip.days.count)" }
    }
    if let leg = leg(trip) {
      switch leg.kind {
      case .outbound: return "BEFORE DAY 1"
      case .return: return "AFTER DAY \(trip.days.count)"
      case .transfer: return leg.dayId.flatMap(number) ?? "ON THE MOVE"
      }
    }
    return (number(attachment.id) ?? "") + (isToday(trip) ? " · TODAY" : "")
  }

  /// "Lisbon, Portugal · €1 = £0.86" for a day, or the leg's date and route.
  private func subtitle(_ trip: TripSnapshot) -> String? {
    func country(_ stop: Stop) -> String {
      CountryMetadata.country(stop.countryCode)?.name ?? stop.place
    }
    let date = CivilDate.display(trip.date(for: attachment), format: "EEEE d MMMM")
    if let leg = leg(trip) {
      let from = trip.stops.first { $0.id == leg.fromStopId }
      let to = trip.stops.first { $0.id == leg.toStopId }
      switch leg.kind {
      case .outbound:
        return to.map { "\(date) · Home to \(country($0)) \($0.flag)" } ?? date
      case .return:
        return from.map { "\(date) · \($0.place) \($0.flag) to home" } ?? date
      case .transfer:
        guard let from, let to else { return date }
        return "\(from.place) → \(to.place)"
      }
    }
    guard let stop = trip.stop(for: attachment) else { return nil }
    let name = country(stop)
    let place = name == stop.place ? name : "\(stop.place), \(name)"
    return trip.rateLabel(for: stop.currency).map { "\(place) · \($0)" } ?? place
  }

  private func total(_ trip: TripSnapshot, items: [Expense]) -> some View {
    let ledger = Ledger(trip, expenses: items)
    let paid = items.count { $0.status == .paid }
    let planned = items.count - paid
    return VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .bottom, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Spent + planned").typeface(13, .bold, relativeTo: .footnote)
            .foregroundStyle(Theme.secondary)
          MoneyText(amount: ledger.total, currency: trip.homeCurrency, size: tent ? 56 : 42)
        }
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 3) {
          Text(local(trip, items: items) ?? "\(items.count) item\(items.count == 1 ? "" : "s")")
          if !items.isEmpty {
            Text(
              planned == 0
                ? "All paid" : paid == 0 ? "All planned" : "\(paid) paid · \(planned) planned")
          }
        }
        .typeface(13, .semibold, relativeTo: .footnote, maximum: 1.4).monospacedDigit()
        .foregroundStyle(Theme.secondary).multilineTextAlignment(.trailing)
        .padding(.bottom, 6)
      }
      if ledger.unresolved > 0 {
        Label(
          "\(ledger.unresolved) conversion\(ledger.unresolved == 1 ? "" : "s") pending · total incomplete",
          systemImage: "exclamationmark.circle"
        )
        .typeface(13, .semibold, relativeTo: .footnote).foregroundStyle(Theme.bad)
      }
    }
    .padding(.vertical, 18).padding(.horizontal, 20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
  }

  /// "€42 local" when the day's stop spends a foreign currency.
  private func local(_ trip: TripSnapshot, items: [Expense]) -> String? {
    guard attachment.kind == .day, let stop = trip.stop(for: attachment),
      stop.currency != trip.homeCurrency
    else { return nil }
    let spent = items.filter { $0.currency == stop.currency }
    guard !spent.isEmpty else { return nil }
    let sum = spent.compactMap { Money.minor($0.amountMinor) }.reduce(0, +)
    return "\(Money.whole(sum, stop.currency)) local"
  }

  // MARK: - Expenses

  private func list(_ trip: TripSnapshot, items: [Expense], compact: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if items.isEmpty {
        empty(trip)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(items.enumerated()), id: \.element.id) { index, expense in
            ExpenseRow(
              trip: trip, expense: expense, fresh: fresh.contains(expense.id), compact: compact
            )
            .overlay(alignment: .top) {
              if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
            }
            .rise(delay: 0.1 + Double(index) * 0.05)
          }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        if !compact, items.contains(where: { $0.status == .planned }) {
          HStack(spacing: 8) {
            Circle()
              .strokeBorder(Theme.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
              .frame(width: 12, height: 12)
              .accessibilityHidden(true)
            Text("Dashed means planned. Tap the circle once it’s paid.")
          }
          .typeface(12.5, .semibold, relativeTo: .caption)
          .foregroundStyle(Theme.tertiary)
          .padding(.horizontal, 4)
        }
      }
    }
  }

  private func empty(_ trip: TripSnapshot) -> some View {
    let leg = leg(trip)
    return VStack(spacing: 6) {
      Text(
        leg == nil
          ? "Nothing here yet"
          : leg?.kind == .return ? "How are you getting home?" : "How are you getting there?"
      )
      .typeface(17, .heavy, relativeTo: .headline)
      .foregroundStyle(Theme.ink)
      Text(
        leg == nil
          ? "Log what you spent, or plan ahead and tick it off later."
          : "Add the flight, the train, even the taxi to the airport. It all adds up."
      )
      .typeface(14, relativeTo: .subheadline)
      .foregroundStyle(Theme.secondary)
      .multilineTextAlignment(.center)
      .frame(maxWidth: 260)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 36).padding(.horizontal, 20)
    .overlay {
      RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        .strokeBorder(Theme.line2, style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
    }
    .rise(delay: 0.1)
  }

  /// Quick convert for a foreign stop, then the main add button, over a fade.
  private func actions(_ trip: TripSnapshot) -> some View {
    actionButtons(trip)
      .padding(.horizontal, Theme.Spacing.screen).padding(.top, 18).padding(.bottom, 6)
      .frame(maxWidth: 680).frame(maxWidth: .infinity)
      .background {
        LinearGradient(
          stops: [
            .init(color: Theme.background.opacity(0), location: 0),
            .init(color: Theme.background, location: 0.4),
          ],
          startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
      }
  }

  private func actionButtons(_ trip: TripSnapshot) -> some View {
    HStack(spacing: 10) {
      if trip.isAbroad(attachment) {
        Button {
          model.showConverter = true
        } label: {
          Image(systemName: "arrow.left.arrow.right").font(.system(size: 19, weight: .bold))
        }
        .buttonStyle(LipButtonStyle(.secondary))
        .frame(width: 58)
        .accessibilityLabel("Quick convert")
      }
      PrimaryButton(title: addTitle, symbol: "plus") {
        model.editExpense(trip: trip, attachment: attachment)
      }
    }
  }
}

/// An expense: tap the circle to tick it off, tap the rest to edit.
private struct ExpenseRow: View {
  var trip: TripSnapshot
  var expense: Expense
  var fresh: Bool
  /// Tent: a smaller icon and the home amount only, with no byline.
  var compact = false
  @Environment(AppModel.self) private var model

  var body: some View {
    let paid = expense.status == .paid
    let amount = Money.minor(expense.amountMinor) ?? 0
    HStack(spacing: 13) {
      Button {
        if paid { Haptics.lightImpact() } else { Haptics.success() }
        model.toggleExpense(expense, trip: trip)
      } label: {
        StatusCircle(category: expense.category, paid: paid, size: compact ? 38 : 44)
      }
      .buttonStyle(PressStyle(scale: 0.88))
      .accessibilityLabel(paid ? "Paid" : "Planned")
      .accessibilityHint(
        paid ? "Moves \(expense.title) back to planned" : "Marks \(expense.title) as paid")
      Button {
        model.editExpense(trip: trip, attachment: expense.attachment, expense: expense)
      } label: {
        HStack(spacing: 10) {
          VStack(alignment: .leading, spacing: 3) {
            Text(expense.title)
              .typeface(15.5, .heavy, relativeTo: .subheadline, maximum: 1.4)
              .foregroundStyle(Theme.ink).lineLimit(1)
            if !compact {
              Text(byline).typeface(13, relativeTo: .footnote, maximum: 1.4)
                .foregroundStyle(Theme.secondary).lineLimit(1)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          if compact {
            Text(homeAmount(amount))
              .typeface(15.5, .heavy, relativeTo: .subheadline, maximum: 1.4).monospacedDigit()
              .foregroundStyle(paid ? Theme.ink : Theme.secondary)
              .fixedSize()
          } else {
            VStack(alignment: .trailing, spacing: 3) {
              Text(Money.format(amount, expense.currency, compact: true))
                .typeface(15.5, .heavy, relativeTo: .subheadline, maximum: 1.4).monospacedDigit()
                .foregroundStyle(paid ? Theme.ink : Theme.secondary)
              if let detail = detail(amount) {
                Text(detail.text)
                  .typeface(12, .semibold, relativeTo: .caption, maximum: 1.4).monospacedDigit()
                  .foregroundStyle(detail.pending ? Theme.bad : Theme.tertiary)
              }
            }
            .fixedSize()
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint("Edits the expense")
    }
    .padding(.vertical, compact ? 10 : 13).padding(.horizontal, compact ? 12 : 16)
    .background(fresh ? Theme.accentSoft : .clear)
    .animation(.easeOut(duration: fresh ? 0.2 : 0.8), value: fresh)
  }

  /// The amount back home, or as spent while its conversion is pending.
  private func homeAmount(_ amount: Int64) -> String {
    if expense.currency == trip.homeCurrency { return Money.format(amount, expense.currency) }
    guard let home = expense.homeMinor(in: trip.homeCurrency) else {
      return Money.format(amount, expense.currency, compact: true)
    }
    return Money.format(home, trip.homeCurrency)
  }

  /// "Tom paid · Split 3 ways" or "Planned · Just you".
  private var byline: String {
    expense.status == .paid
      ? "\(trip.displayName(expense.paidBy)) paid · \(who)" : "Planned · \(who)"
  }

  private var who: String {
    let ids = expense.splitWith
    if ids.count == 1 {
      return ids[0] == trip.currentTravellerId ? "Just you" : "Just \(trip.displayName(ids[0]))"
    }
    if Set(ids) == Set(trip.activeTravellers.map(\.id)) { return "Split \(ids.count) ways" }
    // "You and Maya": the current traveller first, then everyone else in trip order.
    let ordered = ids.sorted { lhs, _ in lhs == trip.currentTravellerId }
    return ordered.map(trip.displayName).formatted(.list(type: .and))
  }

  /// The home value of a foreign expense, or each person's share of a shared home one.
  private func detail(_ amount: Int64) -> (text: String, pending: Bool)? {
    if expense.currency != trip.homeCurrency {
      guard let home = expense.homeMinor(in: trip.homeCurrency) else {
        return ("Conversion pending", true)
      }
      return (Money.format(home, trip.homeCurrency), false)
    }
    guard expense.splitWith.count > 1 else { return nil }
    let share = Money.split(amount, among: expense.splitWith).values.max() ?? 0
    return ("\(Money.format(share, expense.currency, compact: true)) each", false)
  }
}

/// The category icon, with a check badge once the expense is paid.
private struct StatusCircle: View {
  var category: ExpenseCategory
  var paid: Bool
  var size: CGFloat = 44

  var body: some View {
    CategoryIcon(category: category, paid: paid, size: size)
      .overlay(alignment: .bottomTrailing) {
        if paid {
          Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(Theme.goodInk)
            .frame(width: 18, height: 18)
            .background(Theme.good, in: Circle())
            .background(Circle().fill(Theme.surface).padding(-2.5))
            .offset(x: 3, y: 3)
            .transition(.scale(scale: 0.3).combined(with: .opacity))
        }
      }
      .tick(on: paid)
      .animation(Motion.popIn, value: paid)
  }
}
