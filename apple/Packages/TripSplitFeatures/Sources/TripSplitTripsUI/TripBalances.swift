import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitPersistence
import TripSplitSync

/// Who paid what, where everyone stands and the fewest moves to settle up.
struct TripBalances: View {
  var trip: TripSnapshot
  /// Opens the repayment sheet for a suggested move.
  var settle: (Settlement) -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    let ledger = Ledger(trip)
    VStack(alignment: .leading, spacing: 12) {
      people(ledger)
      Kicker(title: "To settle up").padding(.top, 10).padding(.horizontal, 4)
      moves(ledger)
      Text("Only paid expenses count here. Planned ones join in once you tick them off.")
        .typeface(12.5, .semibold, relativeTo: .caption)
        .foregroundStyle(Theme.tertiary)
        .padding(.vertical, 2).padding(.horizontal, 4)
      if !trip.repayments.isEmpty { repayments }
    }
  }

  /// Everyone still on the trip, plus anyone archived who still has money involved.
  private func travellers(_ ledger: Ledger) -> [Traveller] {
    trip.travellers.filter {
      !$0.archived || ledger.balances[$0.id, default: 0] != 0 || ledger.paidBy[$0.id, default: 0] != 0
    }
  }

  private func people(_ ledger: Ledger) -> some View {
    let people = travellers(ledger)
    let most = max(1, people.map { ledger.paidBy[$0.id, default: 0] }.max() ?? 0)
    return VStack(spacing: 0) {
      ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
        let paid = ledger.paidBy[person.id, default: 0]
        let net = ledger.balances[person.id, default: 0]
        HStack(spacing: 12) {
          Avatar(traveller: person, size: 38)
          VStack(alignment: .leading, spacing: 5) {
            Text(name(person.id)).typeface(15.5, .heavy, relativeTo: .subheadline, maximum: 1.4)
              .foregroundStyle(Theme.ink).lineLimit(1)
            HStack(spacing: 8) {
              Capsule().fill(Theme.inset)
                .overlay(alignment: .leading) {
                  GeometryReader { geo in
                    Capsule().fill(AvatarPalette(hue: person.hue).background)
                      .frame(width: geo.size.width * CGFloat(paid) / CGFloat(most))
                      .growAcross(delay: 0.1 + Double(index) * 0.06, duration: 0.7)
                  }
                }
                .frame(height: 5)
              Text("paid \(Money.whole(paid, trip.homeCurrency))")
                .typeface(12, .semibold, relativeTo: .caption, maximum: 1.4).monospacedDigit()
                .foregroundStyle(Theme.secondary).fixedSize()
            }
          }
          Text(net == 0 ? "Square" : "\(net > 0 ? "+" : "−")\(Money.whole(abs(net), trip.homeCurrency))")
            .typeface(15.5, .heavy, relativeTo: .subheadline, maximum: 1.4).monospacedDigit()
            .foregroundStyle(net == 0 ? Theme.tertiary : net > 0 ? Theme.good : Theme.bad)
            .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.vertical, 13).padding(.horizontal, 16)
        .overlay(alignment: .top) {
          if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          "\(person.name), paid \(Money.format(paid, trip.homeCurrency)), \(net == 0 ? "square" : net > 0 ? "owed \(Money.format(net, trip.homeCurrency))" : "owes \(Money.format(-net, trip.homeCurrency))")"
        )
      }
    }
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
  }

  @ViewBuilder private func moves(_ ledger: Ledger) -> some View {
    if !ledger.balancesComplete {
      Label(
        "Conversions are still pending. Settle up once all paid costs are converted.",
        systemImage: "exclamationmark.circle"
      )
      .typeface(14, .semibold, relativeTo: .subheadline)
      .foregroundStyle(Theme.bad)
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    } else if ledger.settlements.isEmpty {
      Text("All square. Nobody owes anything.")
        .typeface(14.5, .semibold, relativeTo: .subheadline)
        .foregroundStyle(Theme.secondary)
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    } else {
      VStack(spacing: 0) {
        ForEach(Array(ledger.settlements.enumerated()), id: \.element.id) { index, settlement in
          Button {
            settle(settlement)
          } label: {
            move(settlement)
              .overlay(alignment: .top) {
                if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
              }
          }
          .buttonStyle(MoveRowStyle())
          .accessibilityHint("Records a repayment")
          .rise(delay: Double(index) * 0.08)
        }
      }
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
  }

  private func move(_ settlement: Settlement) -> some View {
    HStack(spacing: 12) {
      HStack(spacing: 4) {
        avatar(settlement.from)
        Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
          .foregroundStyle(Theme.tertiary)
        avatar(settlement.to)
      }
      .accessibilityHidden(true)
      Text(sentence(settlement)).typeface(14.5, relativeTo: .subheadline, maximum: 1.4)
        .foregroundStyle(Theme.secondary).lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(Money.format(settlement.amount, trip.homeCurrency, compact: true))
        .typeface(16, .heavy, relativeTo: .headline, maximum: 1.4).monospacedDigit()
        .foregroundStyle(Theme.ink).fixedSize()
    }
    .padding(.vertical, 14).padding(.horizontal, 16)
    .contentShape(Rectangle())
  }

  @ViewBuilder private func avatar(_ id: String) -> some View {
    if let person = trip.travellers.first(where: { $0.id == id }) {
      Avatar(traveller: person, size: 32)
    }
  }

  /// "Tom pays you", "You pay Tom" or "Tom pays Sam".
  private func sentence(_ settlement: Settlement) -> String {
    if settlement.from == trip.currentTravellerId { return "You pay \(name(settlement.to))" }
    return "\(name(settlement.from)) pays \(settlement.to == trip.currentTravellerId ? "you" : name(settlement.to))"
  }

  private func name(_ id: String) -> String {
    trip.travellers.first { $0.id == id }?.name ?? "Traveller"
  }

  private var repayments: some View {
    VStack(alignment: .leading, spacing: 12) {
      Kicker(title: "Repayments").padding(.top, 10).padding(.horizontal, 4)
      VStack(spacing: 0) {
        ForEach(Array(trip.repayments.enumerated()), id: \.element.id) { index, repayment in
          HStack(spacing: 12) {
            Image(systemName: "arrow.turn.down.right").font(.system(size: 14, weight: .bold))
              .foregroundStyle(Theme.good).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
              Text("\(name(repayment.fromTravellerId)) → \(name(repayment.toTravellerId))")
                .typeface(14.5, .bold, relativeTo: .subheadline, maximum: 1.4)
                .foregroundStyle(Theme.ink)
              Text(CivilDate.display(repayment.paidOn, format: "d MMM"))
                .typeface(12, .semibold, relativeTo: .caption, maximum: 1.4)
                .foregroundStyle(Theme.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Money.format(Money.minor(repayment.amountMinor) ?? 0, repayment.currency, compact: true))
              .typeface(15, .heavy, relativeTo: .subheadline, maximum: 1.4).monospacedDigit()
              .foregroundStyle(Theme.ink)
          }
          .padding(.vertical, 12).padding(.horizontal, 16)
          .overlay(alignment: .top) {
            if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
          }
          .contentShape(Rectangle())
          .contextMenu {
            Button("Delete repayment", systemImage: "trash", role: .destructive) {
              delete(repayment)
            }
          }
          .accessibilityElement(children: .combine)
          .accessibilityAction(named: "Delete repayment") { delete(repayment) }
        }
      }
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
  }

  private func delete(_ repayment: Repayment) {
    model.perform {
      try model.store.enqueue(
        .init(
          syncEpoch: trip.syncEpoch, type: "repayment.delete", entityId: repayment.id,
          expectedRevision: repayment.revision, payload: .none), tripID: trip.id)
      model.changed()
    }
  }
}

private struct MoveRowStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(configuration.isPressed ? Theme.inset : Color.clear)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}
