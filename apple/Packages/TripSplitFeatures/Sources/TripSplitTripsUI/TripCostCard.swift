import SwiftUI
import TripSplitDesignSystem
import TripSplitDomain

/// The trip's total with a spending breakdown by group and progress against the budget.
struct TripCostCard: View {
  var trip: TripSnapshot

  var body: some View {
    let ledger = Ledger(trip)
    let currency = trip.homeCurrency
    let people = max(1, trip.activeTravellers.count)
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title).typeface(13, .bold, relativeTo: .footnote)
          .foregroundStyle(Theme.secondary)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          MoneyText(amount: Money.wholeUnits(ledger.total, currency), currency: currency, size: 50)
          if trip.hasCompanions {
            Text("\(Money.whole(ledger.total / Int64(people), currency)) each")
              .typeface(15, .bold, relativeTo: .subheadline, maximum: 1.3)
              .foregroundStyle(Theme.secondary).lineLimit(1).layoutPriority(-1)
          }
        }
        if ledger.unresolved > 0 {
          Label(
            "Home amounts needed · connect to update rates",
            systemImage: "exclamationmark.circle"
          )
          .typeface(13, .semibold, relativeTo: .footnote).foregroundStyle(Theme.bad)
        }
      }
      SpendBreakdown(trip: trip)
      budget(ledger)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
  }

  private var title: String {
    switch trip.phase {
    case .past: "What it really cost"
    case .upcoming: "Planned so far"
    case .now: "The real cost, paid + planned"
    }
  }

  private func budget(_ ledger: Ledger) -> some View {
    let currency = trip.homeCurrency
    let budget = Money.minor(trip.budgetMinor) ?? 0
    let over = ledger.total > budget
    return VStack(alignment: .leading, spacing: 9) {
      HStack {
        Text("Budget \(Money.whole(budget, currency))").foregroundStyle(Theme.ink)
        Spacer()
        Text("\(Money.whole(abs(budget - ledger.total), currency)) \(over ? "over" : "left")")
          .foregroundStyle(over ? Theme.bad : Theme.good)
      }
      .typeface(14, .heavy, relativeTo: .subheadline, maximum: 1.4)
      BudgetBar(paid: ledger.paid, planned: ledger.planned, budget: budget, currency: currency)
      HStack(spacing: 16) {
        swatch("Paid \(Money.whole(ledger.paid, currency))") {
          RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Theme.accent)
        }
        swatch("Planned \(Money.whole(ledger.planned, currency))") {
          Hatch(color: Theme.accent.opacity(0.55), spacing: 4, lineWidth: 1.4)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 1)
            }
        }
      }
      .typeface(12.5, .semibold, relativeTo: .caption, maximum: 1.4)
      .foregroundStyle(Theme.secondary)
    }
    .padding(.top, 16)
    .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
  }

  private func swatch(_ title: String, @ViewBuilder mark: () -> some View) -> some View {
    HStack(spacing: 6) {
      mark().frame(width: 10, height: 10).accessibilityHidden(true)
      Text(title).monospacedDigit()
    }
  }
}

/// A bar split by spend group, growing in segment by segment, with a two-column legend.
private struct SpendBreakdown: View {
  var trip: TripSnapshot

  private var groups: [(group: SpendGroup, amount: Int64)] {
    var totals: [SpendGroup: Int64] = [:]
    for expense in trip.expenses {
      guard let value = expense.homeMinor(in: trip.homeCurrency) else { continue }
      totals[expense.category.group, default: 0] += value
    }
    return SpendGroup.allCases.compactMap { group in
      totals[group].flatMap { $0 > 0 ? (group, $0) : nil }
    }
  }

  var body: some View {
    let groups = groups
    let total = max(1, groups.reduce(0) { $0 + $1.amount })
    if !groups.isEmpty {
      VStack(alignment: .leading, spacing: 14) {
        GeometryReader { geo in
          let available = geo.size.width - CGFloat(groups.count - 1) * 2
          HStack(spacing: 2) {
            ForEach(Array(groups.enumerated()), id: \.element.group) { index, item in
              Rectangle().fill(item.group.color)
                .frame(width: max(0, available * CGFloat(item.amount) / CGFloat(total)))
                .growAcross(delay: 0.2 + Double(index) * 0.07)
            }
          }
          .clipShape(Capsule())
        }
        .frame(height: 12)
        .accessibilityHidden(true)
        LazyVGrid(
          columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible())],
          alignment: .leading, spacing: 10
        ) {
          ForEach(groups, id: \.group) { item in
            HStack(spacing: 7) {
              RoundedRectangle(cornerRadius: 3, style: .continuous).fill(item.group.color)
                .frame(width: 8, height: 8)
              Text(item.group.title).foregroundStyle(Theme.secondary).lineLimit(1)
              Spacer(minLength: 4)
              Text(Money.whole(item.amount, trip.homeCurrency))
                .fontWeight(.heavy).monospacedDigit().foregroundStyle(Theme.ink)
            }
            .typeface(13.5, relativeTo: .footnote, maximum: 1.4)
            .accessibilityElement(children: .combine)
          }
        }
      }
    }
  }
}
