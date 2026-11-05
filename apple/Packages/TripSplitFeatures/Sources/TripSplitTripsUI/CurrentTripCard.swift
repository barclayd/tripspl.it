import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain

/// The accent hero for the trip that's happening now: cost, budget, a bar per day and today's shortcuts.
struct CurrentTripCard: View {
  var trip: TripSnapshot
  @Environment(AppModel.self) private var model
  @State private var pressed = false

  var body: some View {
    let ledger = Ledger(trip)
    let attachment = trip.currentAttachment
    VStack(alignment: .leading, spacing: 18) {
      Button {
        model.open(trip)
      } label: {
        summary(ledger, attachment: attachment)
      }
      .buttonStyle(PressStyle(onPress: { pressed = $0 }))
      .accessibilityHint("Opens the trip")
      DayBars(trip: trip, today: attachment)
      HStack(spacing: 8) {
        todayPill(attachment)
        Button {
          model.open(trip)
          model.editExpense(trip: trip, attachment: attachment)
        } label: {
          Image(systemName: "plus").font(.system(size: 20, weight: .bold))
            .foregroundStyle(Theme.accent)
            .frame(width: 48, height: 48)
            .background(
              Theme.accentInk,
              in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.88))
        .accessibilityLabel("Add today’s expense")
      }
    }
    .padding(20)
    .foregroundStyle(Theme.accentInk)
    .background(
      Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
    )
    .shadow(color: Theme.accent.opacity(0.32), radius: 20, y: 14)
    .scaleEffect(pressed ? 0.98 : 1)
    .animation(Motion.bump, value: pressed)
    .rise()
  }

  private func summary(_ ledger: Ledger, attachment: Attachment) -> some View {
    let currency = trip.homeCurrency
    let budget = Money.minor(trip.budgetMinor) ?? 0
    let people = trip.activeTravellers.count
    let day = (trip.days.firstIndex { $0.id == attachment.id } ?? 0) + 1
    return VStack(alignment: .leading, spacing: 18) {
      HStack {
        HStack(spacing: 4) {
          ForEach(Array(trip.uniqueFlags.enumerated()), id: \.offset) { index, flag in
            Text(flag).font(.system(size: 28)).popIn(delay: 0.25 + Double(index) * 0.1)
          }
        }
        .accessibilityHidden(true)
        Spacer()
        Text("Day \(day) of \(trip.days.count)").typeface(13, .heavy)
          .padding(.vertical, 6).padding(.horizontal, 11)
          .background(Theme.heroChip, in: Capsule())
      }
      VStack(alignment: .leading, spacing: 5) {
        Text(trip.name).typeface(24, .heavy, tracking: -0.025, relativeTo: .title2)
          .lineLimit(2).multilineTextAlignment(.leading)
        Text(
          "\(CivilDate.display(trip.startsOn)) – \(CivilDate.display(trip.endsOn)) · \(trip.hasCompanions ? "\(people) people" : "Solo trip")"
        )
        .typeface(14, relativeTo: .subheadline).opacity(0.86)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(ledger.unresolved > 0 ? "Known cost · home amounts needed" : "This trip costs")
          .typeface(13, .bold, relativeTo: .footnote).opacity(0.86)
        MoneyText(amount: Money.wholeUnits(ledger.total, currency), currency: currency, size: 50)
        if trip.hasCompanions {
          Text("\(Money.whole(ledger.total / Int64(max(1, people)), currency)) each")
            .typeface(14, .semibold, relativeTo: .subheadline).opacity(0.9).padding(.top, 3)
        }
      }
      VStack(spacing: 8) {
        BudgetBar(
          paid: ledger.paid, planned: ledger.planned, budget: budget, currency: currency, hero: true)
        HStack {
          Text("\(Money.whole(ledger.paid, currency)) paid")
          Spacer()
          Text(
            ledger.total <= budget
              ? "\(Money.whole(budget - ledger.total, currency)) left of \(Money.whole(budget, currency))"
              : "\(Money.whole(ledger.total - budget, currency)) over budget")
        }
        .typeface(12.5, .bold, relativeTo: .caption).opacity(0.92)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  private func todayPill(_ attachment: Attachment) -> some View {
    let stop = trip.stop(for: attachment)
    let spent = Ledger(trip, expenses: trip.expenses(for: attachment)).total
    return Button {
      model.open(trip)
      model.openDay(attachment)
    } label: {
      HStack {
        Text("Today in \(stop?.place ?? "your trip") \(stop?.flag ?? "")").lineLimit(1)
        Spacer(minLength: 8)
        Text(Money.whole(spent, trip.homeCurrency)).monospacedDigit()
      }
      .typeface(14.5, .heavy, relativeTo: .subheadline, maximum: 1.3)
      .padding(.horizontal, 14)
      .frame(maxWidth: .infinity, minHeight: 48)
      .background(
        Theme.heroChip, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
  }
}

/// One bar per itinerary day, scaled to the biggest day, past days solid and today dotted.
private struct DayBars: View {
  var trip: TripSnapshot
  var today: Attachment

  var body: some View {
    let totals = trip.dayTotals
    let biggest = max(1, totals.max() ?? 0)
    let todayIndex = trip.days.firstIndex { $0.id == today.id } ?? 0
    HStack(alignment: .bottom, spacing: 5) {
      ForEach(Array(trip.days.enumerated()), id: \.element.id) { index, _ in
        VStack(spacing: 4) {
          RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Theme.accentInk)
            .opacity(index <= todayIndex ? 0.95 : 0.35)
            .frame(height: max(0.08, Double(totals[index]) / Double(biggest)) * 38)
            .growUp(delay: 0.3 + Double(index) * 0.05)
          Circle().fill(Theme.accentInk).frame(width: 4, height: 4)
            .opacity(index == todayIndex ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      }
    }
    .frame(height: 46)
    .accessibilityHidden(true)
  }
}
