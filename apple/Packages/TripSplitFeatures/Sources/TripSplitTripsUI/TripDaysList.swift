import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain

/// The itinerary: getting there, each stop's days with transfers between them, then getting home.
struct TripDaysList: View {
  var trip: TripSnapshot
  var compact = false
  @Environment(AppModel.self) private var model

  var body: some View {
    let legs = trip.orderedLegs
    VStack(alignment: .leading, spacing: 20) {
      ForEach(legs.filter { $0.kind == .outbound }) { TravelBlock(trip: trip, leg: $0) }
      ForEach(trip.stops) { stop in
        StopGroup(trip: trip, stop: stop, compact: compact)
        ForEach(legs.filter { $0.kind == .transfer && $0.fromStopId == stop.id }) {
          TravelBlock(trip: trip, leg: $0)
        }
      }
      ForEach(legs.filter { $0.kind == .return }) { TravelBlock(trip: trip, leg: $0) }
    }
  }
}

/// A travel leg as a tappable card: what's booked and what it costs.
private struct TravelBlock: View {
  var trip: TripSnapshot
  var leg: TravelLeg
  @Environment(AppModel.self) private var model

  var body: some View {
    let items = trip.travelExpenses(on: leg)
    let ledger = Ledger(trip, expenses: items)
    let planned = items.count { $0.status == .planned }
    let palette = CategoryPalette(.flight)
    Button {
      model.openDay(.init(kind: .leg, id: leg.id))
    } label: {
      HStack(spacing: 14) {
        Image(systemName: leg.kind == .outbound ? "airplane" : "tram")
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(palette.foreground)
          .frame(width: 44, height: 44)
          .background(palette.background, in: RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          // The Duo's open Trip pane is narrow, so the title shrinks a touch rather than wrapping.
          Text(leg.title).typeface(16, .heavy, relativeTo: .headline, maximum: 1.4)
            .foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.8)
          Text(
            items.isEmpty
              ? "Add flights, trains, airport taxis" : items.map(\.title).joined(separator: " · ")
          )
          .typeface(13, relativeTo: .footnote, maximum: 1.4)
          .foregroundStyle(Theme.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .trailing, spacing: 2) {
          if !items.isEmpty {
            Text(Money.whole(ledger.total, trip.homeCurrency))
              .typeface(15.5, .heavy, relativeTo: .subheadline, maximum: 1.4).monospacedDigit()
              .foregroundStyle(Theme.ink)
          }
          Text(items.isEmpty ? "Add" : planned > 0 ? "\(planned) planned" : "\(items.count) paid")
            .typeface(12, .semibold, relativeTo: .caption, maximum: 1.4)
            .foregroundStyle(ledger.unresolved > 0 ? Theme.bad : Theme.tertiary)
        }
        .fixedSize()
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
          .foregroundStyle(Theme.tertiary).accessibilityHidden(true)
      }
      .padding(.vertical, 14).padding(.horizontal, 16)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle(scale: 0.98))
    .accessibilityHint(items.isEmpty ? "Adds travel" : "Opens travel")
  }
}

/// A stop's heading, then its days in one grouped card.
private struct StopGroup: View {
  var trip: TripSnapshot
  var stop: Stop
  var compact: Bool

  var body: some View {
    let days = trip.days.filter { $0.stopId == stop.id }
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline) {
        Text("\(stop.flag) \(stop.place)")
          .typeface(18, .heavy, tracking: -0.015, relativeTo: .headline, maximum: 1.4)
          .foregroundStyle(Theme.ink).lineLimit(1)
        Spacer(minLength: 8)
        Text(meta).typeface(12.5, .bold, relativeTo: .caption, maximum: 1.4)
          .foregroundStyle(Theme.tertiary).monospacedDigit().lineLimit(1)
      }
      .padding(.horizontal, 4)
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isHeader)
      VStack(spacing: 0) {
        ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
          DayRow(trip: trip, day: day, compact: compact)
            .overlay(alignment: .top) {
              if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
      }
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
  }

  /// "3 nights · €1 = £0.86", with the rate only for a foreign stop whose rate is known.
  private var meta: String {
    let nights = "\(stop.nights) night\(stop.nights == 1 ? "" : "s")"
    return trip.rateLabel(for: stop.currency).map { "\(nights) · \($0)" } ?? nights
  }
}

private struct DayRow: View {
  var trip: TripSnapshot
  var day: TripDay
  var compact: Bool
  @Environment(AppModel.self) private var model

  var body: some View {
    let attachment = Attachment(kind: .day, id: day.id)
    let items = trip.expenses(for: attachment)
    let ledger = Ledger(trip, expenses: items)
    let planned = items.count { $0.status == .planned }
    let today = trip.isToday(day)
    let selected = compact && model.selectedAttachment == attachment
    let number = (trip.days.firstIndex { $0.id == day.id } ?? 0) + 1
    Button {
      model.openDay(attachment)
    } label: {
      HStack(spacing: 14) {
        VStack(spacing: 1) {
          Text(CivilDate.display(day.date, format: "EEE").uppercased())
            .typeface(10.5, .heavy, tracking: 0.06, relativeTo: .caption2, maximum: 1.3)
            .foregroundStyle(today ? Theme.accentText : Theme.tertiary)
          Text(CivilDate.display(day.date, format: "d"))
            .typeface(22, .bold, tracking: -0.03, relativeTo: .title3, maximum: 1.3)
            .foregroundStyle(Theme.ink)
        }
        .frame(width: 40)
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 7) {
            Text("Day \(number)").typeface(15.5, .heavy, relativeTo: .subheadline, maximum: 1.4)
              .foregroundStyle(Theme.ink)
            if today {
              Text("TODAY").typeface(10.5, .black, tracking: 0.04, relativeTo: .caption2, maximum: 1.3)
                .foregroundStyle(Theme.accentInk)
                .padding(.vertical, 3).padding(.horizontal, 7)
                .background(Theme.accent, in: Capsule())
            }
          }
          Text(items.isEmpty ? "Nothing yet" : items.map(\.title).joined(separator: " · "))
            .typeface(13, relativeTo: .footnote, maximum: 1.4)
            .foregroundStyle(items.isEmpty ? Theme.tertiary : Theme.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .trailing, spacing: 2) {
          Text(items.isEmpty ? "—" : Money.whole(ledger.total, trip.homeCurrency))
            .typeface(15.5, .heavy, relativeTo: .subheadline, maximum: 1.4).monospacedDigit()
            .foregroundStyle(items.isEmpty ? Theme.tertiary : Theme.ink)
          if let sub = sub(items, ledger: ledger, planned: planned) {
            Text(sub).typeface(12, .semibold, relativeTo: .caption, maximum: 1.4).monospacedDigit()
              .foregroundStyle(ledger.unresolved > 0 ? Theme.bad : Theme.tertiary)
          }
        }
        .fixedSize()
      }
      .padding(.vertical, 13).padding(.horizontal, 16)
      .contentShape(Rectangle())
    }
    .buttonStyle(DayRowStyle(highlighted: today || selected))
    .overlay(alignment: .leading) {
      // The Duo column marks the open day with an accent edge.
      if selected { Rectangle().fill(Theme.accent).frame(width: 4) }
    }
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  /// Planned count, pending conversions, or the total in the stop's own currency.
  private func sub(_ items: [Expense], ledger: Ledger, planned: Int) -> String? {
    if ledger.unresolved > 0 { return "+ pending FX" }
    if planned > 0 { return "\(planned) planned" }
    guard let stop = trip.stop(for: .init(kind: .day, id: day.id)),
      stop.currency != trip.homeCurrency
    else { return nil }
    let local = items.filter { $0.currency == stop.currency }
    guard !local.isEmpty else { return nil }
    return Money.whole(local.compactMap { Money.minor($0.amountMinor) }.reduce(0, +), stop.currency)
  }
}

private struct DayRowStyle: ButtonStyle {
  var highlighted: Bool
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(
        configuration.isPressed ? Theme.inset : highlighted ? Theme.accentSoft : Color.clear
      )
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}
