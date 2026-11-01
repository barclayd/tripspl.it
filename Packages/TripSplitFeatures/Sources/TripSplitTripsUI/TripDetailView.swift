import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitPersistence
import TripSplitSharedUI
import TripSplitSync

public struct TripDetailView: View {
  public init(tripID: String, compact: Bool = false) {
    self.tripID = tripID
    self.compact = compact
  }
  @Environment(AppModel.self) private var model
  var tripID: String
  var compact = false
  @State private var segment = 0
  @State private var repayment: Settlement?
  public var body: some View {
    if let trip = model.store.trip(tripID) {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          if !compact {
            VStack(alignment: .leading, spacing: 10) {
              Text(trip.flags).font(.system(size: 38))
              Text(trip.name).font(.system(size: 32, weight: .heavy, design: .default)).tracking(
                -1.2)
              HStack(spacing: -7) {
                ForEach(trip.activeTravellers) {
                  Avatar(traveller: $0, size: 28).overlay(
                    Circle().stroke(Theme.background, lineWidth: 2))
                }
                Text(
                  "\(CivilDate.display(trip.startsOn)) – \(CivilDate.display(trip.endsOn)) · \(trip.days.count) days"
                ).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary).padding(
                  .leading, 17)
              }
            }
            BoardingPassStack(trip: trip) { model.openDay(.init(kind: .leg, id: $0.id)) }
            costCard(trip)
          }
          SyncNotice(tripID: trip.id)
          Picker("Trip section", selection: $segment) {
            Text("Days").tag(0)
            Text("Who owes who").tag(1)
          }.pickerStyle(.segmented)
          if segment == 0 { itinerary(trip) } else { balances(trip) }
        }.pagePadding().padding(.bottom, 24)
      }.background(Theme.background).navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $repayment) { settlement in
          RepaymentView(tripID: trip.id, settlement: settlement)
        }
    }
  }
  private func costCard(_ trip: TripSnapshot) -> some View {
    let ledger = Ledger(trip)
    let budget = Money.minor(trip.budgetMinor) ?? 0
    return Card {
      VStack(alignment: .leading, spacing: 15) {
        Text(
          trip.phase == .upcoming
            ? "Planned so far"
            : trip.phase == .past ? "What it really cost" : "The real cost, paid + planned"
        ).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary)
        MoneyText(amount: ledger.total, currency: trip.homeCurrency)
        if ledger.unresolved > 0 {
          Label(
            "\(ledger.unresolved) conversion\(ledger.unresolved == 1 ? "" : "s") pending · total incomplete",
            systemImage: "exclamationmark.circle"
          ).font(.footnote).foregroundStyle(Theme.bad)
        }
        Text(
          "\(Money.format(ledger.total / Int64(max(trip.activeTravellers.count, 1)), trip.homeCurrency)) average each"
        ).font(.subheadline).foregroundStyle(Theme.secondary)
        categoryBar(trip)
        Divider()
        HStack {
          Text("Budget \(Money.format(budget, trip.homeCurrency, compact: true))")
          Spacer()
          Text(
            "\(Money.format(abs(budget - ledger.total), trip.homeCurrency, compact: true)) \(ledger.total > budget ? "over" : "left")"
          ).foregroundStyle(ledger.total > budget ? Theme.bad : Theme.good)
        }.font(.subheadline.weight(.bold))
        BudgetBar(
          paid: ledger.paid, planned: ledger.planned, budget: budget, currency: trip.homeCurrency)
        HStack {
          Text("Paid \(Money.format(ledger.paid, trip.homeCurrency, compact: true))")
          Spacer()
          Text("Planned \(Money.format(ledger.planned, trip.homeCurrency, compact: true))")
        }.font(.caption).foregroundStyle(Theme.secondary)
      }
    }
  }
  private func categoryBar(_ trip: TripSnapshot) -> some View {
    let categories = ExpenseCategory.allCases.filter { c in
      trip.expenses.contains { $0.category == c }
    }
    return VStack(alignment: .leading, spacing: 12) {
      GeometryReader { geo in
        HStack(spacing: 2) {
          ForEach(categories, id: \.self) { category in
            let total = trip.expenses.filter { $0.category == category }.compactMap {
              $0.homeMinor(in: trip.homeCurrency)
            }.reduce(0, +)
            RoundedRectangle(cornerRadius: 3).fill(
              Color(hue: category.hue, saturation: 0.40, brightness: 0.86)
            ).frame(
              width: max(
                0,
                (geo.size.width - CGFloat(categories.count * 2)) * CGFloat(total)
                  / CGFloat(max(1, Ledger(trip).total))))
          }
        }
      }.frame(height: 12)
      LazyVGrid(
        columns: [
          .init(.flexible(), alignment: .leading), .init(.flexible(), alignment: .leading),
        ], alignment: .leading, spacing: 8
      ) {
        ForEach(categories, id: \.self) { category in
          HStack(spacing: 6) {
            Circle().fill(Color(hue: category.hue, saturation: 0.4, brightness: 0.86)).frame(
              width: 7, height: 7)
            Text(category.title).font(.caption).foregroundStyle(Theme.secondary)
          }
        }
      }
    }
  }
  private func itinerary(_ trip: TripSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 22) {
      if let leg = trip.legs.first { travelRow(leg, trip) }
      ForEach(trip.stops) { stop in
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text(stop.flag).font(.title2)
            VStack(alignment: .leading, spacing: 3) {
              Text(stop.place).font(.headline)
              Text("\(stop.nights) nights · \(stop.currency)").font(.caption).foregroundStyle(
                Theme.secondary)
            }
          }
          VStack(spacing: 0) {
            ForEach(trip.days.filter { $0.stopId == stop.id }) { day in
              dayRow(day, trip)
              if day.id != trip.days.last(where: { $0.stopId == stop.id })?.id {
                Divider().padding(.leading, 64)
              }
            }
          }.background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
          ForEach(trip.legs.filter { $0.kind == .transfer && $0.fromStopId == stop.id }) {
            travelRow($0, trip)
          }
        }
      }
      if let leg = trip.legs.last { travelRow(leg, trip) }
    }
  }
  private func dayRow(_ day: TripDay, _ trip: TripSnapshot) -> some View {
    let attachment = Attachment(kind: .day, id: day.id)
    let items = trip.expenses(for: .init(kind: .day, id: day.id))
    let ledger = Ledger(trip, expenses: items)
    return Button {
      model.openDay(attachment)
    } label: {
      HStack(spacing: 12) {
        VStack(spacing: 3) {
          Text(CivilDate.display(day.date, format: "EEE").uppercased()).font(
            .system(size: 9, weight: .heavy))
          Text(CivilDate.display(day.date, format: "d")).font(.title3.weight(.heavy))
        }.foregroundStyle(Theme.secondary).frame(width: 34)
        VStack(alignment: .leading, spacing: 5) {
          HStack {
            Text("Day \((trip.days.firstIndex(where: { $0.id == day.id }) ?? 0) + 1)").font(
              .subheadline.weight(.heavy))
            if trip.isToday(day) {
              Text("TODAY").font(.system(size: 8, weight: .black)).foregroundStyle(Theme.accent)
                .padding(4).background(Theme.accentSoft, in: Capsule())
            }
          }
          Text(
            items.isEmpty ? "No expenses" : items.map(\.title).joined(separator: ", ")
          ).font(.caption).lineLimit(1).foregroundStyle(Theme.secondary)
        }
        Spacer(minLength: 0)
        VStack(alignment: .trailing, spacing: 4) {
          Text(items.isEmpty ? "—" : Money.format(ledger.total, trip.homeCurrency, compact: true))
            .font(.subheadline.weight(.heavy))
          if items.contains(where: { $0.status == .planned }) {
            Text("\(items.filter { $0.status == .planned }.count) planned").font(.caption2)
              .foregroundStyle(Theme.secondary)
          }
          if ledger.unresolved > 0 {
            Text("+ pending FX").font(.caption2).foregroundStyle(Theme.bad)
          }
        }
      }.padding(14).background(
        model.selectedAttachment == attachment || trip.isToday(day)
          ? Theme.accentSoft.opacity(0.7) : .clear)
    }.buttonStyle(.plain)
  }
  private func travelRow(_ leg: TravelLeg, _ trip: TripSnapshot) -> some View {
    Button {
      model.openDay(.init(kind: .leg, id: leg.id))
    } label: {
      Card(padding: 15) {
        HStack {
          Image(systemName: leg.kind == .transfer ? "train.side.front.car" : "airplane").font(
            .title3
          ).foregroundStyle(Theme.accent).frame(width: 42, height: 42).background(
            Theme.accentSoft, in: RoundedRectangle(cornerRadius: 13))
          VStack(alignment: .leading, spacing: 4) {
            Text(leg.title).font(.subheadline.weight(.heavy))
            Text(
              trip.expenses(for: .init(kind: .leg, id: leg.id)).isEmpty
                ? "Flights, trains, airport taxis" : CivilDate.display(leg.date)
            ).font(.caption).foregroundStyle(Theme.secondary)
          }
          Spacer()
          Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(
            Theme.secondary)
        }
      }
    }.buttonStyle(.plain)
  }
  private func balances(_ trip: TripSnapshot) -> some View {
    let ledger = Ledger(trip)
    return VStack(alignment: .leading, spacing: 20) {
      Card {
        VStack(spacing: 20) {
          ForEach(trip.travellers) { person in
            HStack(spacing: 12) {
              Avatar(traveller: person, size: 38)
              VStack(alignment: .leading, spacing: 5) {
                Text(person.name).font(.subheadline.weight(.heavy))
                Text(
                  "Paid \(Money.format(ledger.paidBy[person.id, default: 0], trip.homeCurrency))"
                ).font(.caption).foregroundStyle(Theme.secondary)
              }
              Spacer()
              let net = ledger.balances[person.id, default: 0]
              Text(
                net == 0
                  ? "Square" : "\(net > 0 ? "+" : "−")\(Money.format(abs(net), trip.homeCurrency))"
              ).font(.subheadline.weight(.heavy)).foregroundStyle(net >= 0 ? Theme.good : Theme.bad)
            }
          }
        }
      }
      Kicker(title: "To settle up")
      if !ledger.balancesComplete {
        Label(
          "Conversions are still pending. Settle up once all paid costs are converted.",
          systemImage: "exclamationmark.circle"
        ).font(.subheadline).foregroundStyle(Theme.bad)
      } else if ledger.settlements.isEmpty {
        Card {
          Label("All square. Nobody owes anything.", systemImage: "checkmark.circle.fill").font(
            .subheadline.weight(.semibold)
          ).foregroundStyle(Theme.good)
        }
      } else {
        ForEach(ledger.settlements) { settlement in
          Button {
            repayment = settlement
          } label: {
            Card(padding: 16) {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text(
                    "\(trip.travellers.first(where: { $0.id == settlement.from })?.name ?? "Traveller") pays \(trip.travellers.first(where: { $0.id == settlement.to })?.name ?? "traveller")"
                  ).font(.subheadline.weight(.heavy))
                  Text("Record a repayment").font(.caption).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text(Money.format(settlement.amount, trip.homeCurrency)).font(.headline)
                  .foregroundStyle(Theme.accent)
              }
            }
          }.buttonStyle(.plain)
        }
      }
      Text(
        "Only paid expenses count here. Planned ones join in once you tick them off. Repayments record money transferred elsewhere."
      ).font(.footnote).foregroundStyle(Theme.secondary)
      if !trip.repayments.isEmpty {
        Kicker(title: "Repayments")
        ForEach(trip.repayments) { repayment in
          HStack {
            Image(systemName: "arrow.turn.down.right").foregroundStyle(Theme.good)
            Text(
              "\(trip.travellers.first(where: { $0.id == repayment.fromTravellerId })?.name ?? "Traveller") → \(trip.travellers.first(where: { $0.id == repayment.toTravellerId })?.name ?? "Traveller")"
            )
            Spacer()
            Text(Money.format(Money.minor(repayment.amountMinor) ?? 0, repayment.currency))
          }.font(.caption).contextMenu {
            Button("Delete repayment", systemImage: "trash", role: .destructive) {
              model.perform {
                try model.store.enqueue(
                  .init(
                    syncEpoch: trip.syncEpoch, type: "repayment.delete", entityId: repayment.id,
                    expectedRevision: repayment.revision, payload: .none), tripID: trip.id)
                model.changed()
              }
            }
          }
        }
      }
    }
  }
}
