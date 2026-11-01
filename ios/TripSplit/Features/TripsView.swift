import SwiftUI

struct TripsView: View {
  @Environment(AppModel.self) private var model
  var compact = false
  private var trips: [TripSnapshot] { model.store.trips }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        if !compact {
          if !trips.isEmpty {
            HStack {
              Text(
                Array(Set(trips.flatMap { $0.stops.map(\.flag) })).sorted().joined(separator: " ")
              ).font(.title2)
              Spacer()
              Text(
                "\(trips.count) trips · \(Set(trips.flatMap { $0.stops.map(\.countryCode) }).count) countries"
              ).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
            }
          }
        }
        if trips.isEmpty {
          empty
        } else if compact {
          sidebar
        } else {
          ForEach(trips.filter { $0.phase == .now }) { trip in
            VStack(alignment: .leading, spacing: 10) {
              HStack(spacing: 8) {
                Circle().fill(Theme.accent).frame(width: 7, height: 7)
                Kicker(title: "Happening now")
              }
              CurrentTripCard(trip: trip)
              if trip.showsHomeConverter {
                Button {
                  model.open(trip)
                  model.showConverter = true
                } label: {
                  Card(padding: 16) {
                    HStack {
                      Text(trip.stop(for: trip.currentAttachment)?.flag ?? "🌍").font(.title)
                      VStack(alignment: .leading, spacing: 3) {
                        Text("Quick convert").font(.headline)
                        Text(
                          "\(trip.stop(for: trip.currentAttachment)?.currency ?? "") → \(trip.homeCurrency)"
                        ).font(.caption).foregroundStyle(Theme.secondary)
                      }
                      Spacer()
                      Image(systemName: "arrow.left.arrow.right").padding(10).background(
                        Theme.accentSoft, in: Capsule()
                      ).foregroundStyle(Theme.accent)
                    }
                  }
                }.buttonStyle(.plain).accessibilityIdentifier("home.quickConvert")
              }
            }
          }
          departures
          if trips.contains(where: { $0.phase == .past }) { passport }
        }
      }.pagePadding().padding(.bottom, 28)
    }.background(Theme.background).toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("New trip", systemImage: "plus") { model.showOnboarding = true }
      }
      ToolbarItem {
        Button("Account & sync", systemImage: "person.crop.circle") { model.showSettings = true }
      }
    }
    .refreshable { await model.sync.syncAll() }
  }
  private var empty: some View {
    VStack(alignment: .leading, spacing: 28) {
      ZStack(alignment: .bottomTrailing) {
        VStack(alignment: .leading, spacing: 15) {
          Kicker(title: "Your next chapter")
          Text("Less maths.\nMore memories.").font(
            .system(size: 43, weight: .heavy, design: .default)
          ).tracking(-2)
          Text("Plan the adventure. Split the costs.\nKnow what it really comes to.").font(.body)
            .foregroundStyle(Theme.secondary).lineSpacing(4)
        }.padding(26).frame(maxWidth: .infinity, alignment: .leading).background(
          Theme.surface, in: RoundedRectangle(cornerRadius: 28))
        Text("✈️").font(.system(size: 56)).rotationEffect(.degrees(-12)).offset(x: -10, y: 28)
      }.padding(.top, 12).padding(.bottom, 20)
      VStack(alignment: .leading, spacing: 12) {
        Label("A budget for the whole crew", systemImage: "person.2")
        Label("Every day, every little coffee", systemImage: "cup.and.saucer")
        Label("Clear totals, even across currencies", systemImage: "arrow.left.arrow.right")
      }.font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary)
      PrimaryButton(title: "Plan your first trip", symbol: "plus") { model.showOnboarding = true }
      Text(
        "Start here, sign in when you’re ready to share. Your trips save automatically on this device."
      ).font(.footnote).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).frame(
        maxWidth: .infinity)
    }
  }
  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 24) {
      ForEach(TripSnapshot.Phase.allCases, id: \.self) { phase in
        let group = trips.filter { $0.phase == phase }
        if !group.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            Kicker(title: phase == .now ? "Now" : phase == .upcoming ? "Coming up" : "Been there")
            ForEach(group) { trip in
              Button {
                model.open(trip)
              } label: {
                HStack(spacing: 12) {
                  Text(trip.stops.first?.flag ?? "🌍").font(.title2).frame(width: 40, height: 44)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                  VStack(alignment: .leading, spacing: 4) {
                    Text(trip.name).font(.subheadline.weight(.heavy))
                    Text(
                      "\(CivilDate.display(trip.startsOn)) · \(trip.activeTravellers.count) \(trip.activeTravellers.count == 1 ? "person" : "people")"
                    ).font(.caption).foregroundStyle(Theme.secondary)
                  }
                  Spacer()
                  Text(Money.format(Ledger(trip).total, trip.homeCurrency, compact: true)).font(
                    .subheadline.weight(.bold))
                }.padding(12).background(
                  model.selectedTripID == trip.id ? Theme.accentSoft : .clear,
                  in: RoundedRectangle(cornerRadius: 16))
              }.buttonStyle(.plain)
            }
          }
        }
      }
    }
  }
  private var departures: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Label("DEPARTURES", systemImage: "airplane").font(
          .system(size: 12, weight: .black, design: .monospaced)
        ).tracking(2).foregroundStyle(Theme.amber)
        Spacer()
        Image(systemName: "clock").foregroundStyle(.white.opacity(0.6))
      }
      HStack {
        Text("DESTINATION")
        Spacer()
        Text("DATE")
        Text("STATUS").frame(width: 63)
      }.font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(
        .white.opacity(0.40)
      ).tracking(1)
      ForEach(trips.filter { $0.phase != .past }) { trip in
        Button {
          model.open(trip)
        } label: {
          HStack(spacing: 7) {
            Text(trip.stops.first?.flag ?? "🌍").font(.subheadline)
            FlapText(
              value: (trip.stops.first?.place ?? trip.name)
                + (trip.stops.count > 1 ? " +\(trip.stops.count - 1)" : ""), count: 9, size: 12)
            Spacer(minLength: 0)
            FlapText(value: CivilDate.display(trip.startsOn, format: "dd MMM"), count: 6, size: 10)
            FlapText(
              value: trip.phase == .now ? "ON TRIP" : "SOON", count: 7, size: 10,
              color: trip.phase == .now ? Color(hex: 0x5BE49B) : Theme.amber)
          }
        }.buttonStyle(.plain).accessibilityLabel(
          "\(trip.name), \(CivilDate.display(trip.startsOn)), \(trip.phase == .now ? "On trip" : "Upcoming")"
        )
      }
      Button {
        model.showOnboarding = true
      } label: {
        Label("ADD A TRIP", systemImage: "plus").font(
          .system(size: 11, weight: .bold, design: .monospaced)
        ).foregroundStyle(.white.opacity(0.50)).frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 6)
      }
    }.padding(19).background(Theme.board, in: RoundedRectangle(cornerRadius: 22))
  }
  private var passport: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Kicker(title: "Passport · visas")
        Spacer()
        Text("\(trips.filter { $0.phase == .past }.count) STAMPS").font(
          .system(size: 9, weight: .heavy, design: .monospaced)
        ).foregroundStyle(Theme.secondary)
      }
      LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 20) {
        ForEach(Array(trips.filter { $0.phase == .past }.enumerated()), id: \.element.id) {
          index, trip in
          Button {
            model.open(trip)
          } label: {
            VStack(spacing: 5) {
              Text("ARRIVED").font(.system(size: 10, weight: .black, design: .monospaced)).tracking(
                3)
              Text(trip.stops.first?.place.uppercased() ?? trip.name.uppercased()).font(
                .system(size: 17, weight: .black, design: .default))
              Text(trip.flags).font(.title2)
              Text(CivilDate.display(trip.startsOn, format: "MMM yyyy").uppercased()).font(
                .system(size: 10, weight: .bold, design: .monospaced))
              Text(Money.format(Ledger(trip).total, trip.homeCurrency, compact: true)).font(
                .system(size: 17, weight: .black, design: .default))
            }.frame(maxWidth: .infinity).padding(.vertical, 17).overlay(
              RoundedRectangle(cornerRadius: index % 2 == 0 ? 70 : 14).stroke(lineWidth: 2.5)
            ).padding(4).overlay(
              RoundedRectangle(cornerRadius: index % 2 == 0 ? 74 : 18).stroke(lineWidth: 1)
            ).rotationEffect(.degrees(index % 2 == 0 ? -7 : 6)).foregroundStyle(
              index % 2 == 0 ? Color(hex: 0x9B4A42) : Color(hex: 0x615396))
          }.buttonStyle(.plain)
        }
      }.padding(.vertical, 8)
    }.padding(20).background(
      Color.adaptive(0xF5EFDF, 0x2B2821), in: RoundedRectangle(cornerRadius: 20))
  }
}
struct CurrentTripCard: View {
  @Environment(AppModel.self) private var model
  var trip: TripSnapshot
  var body: some View {
    let ledger = Ledger(trip)
    let budget = Money.minor(trip.budgetMinor) ?? 0
    VStack(alignment: .leading, spacing: 15) {
      Button {
        model.open(trip)
      } label: {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text(trip.flags).font(.title)
            Spacer()
            Text(
              "Day \((trip.days.firstIndex(where: { $0.date == trip.today }) ?? 0) + 1) of \(trip.days.count)"
            ).font(.caption.weight(.bold)).padding(.horizontal, 12).padding(.vertical, 6)
              .background(.white.opacity(0.2), in: Capsule())
          }
          Text(trip.name).font(.system(size: 25, weight: .heavy, design: .default)).tracking(-0.6)
          Text(
            "\(CivilDate.display(trip.startsOn)) – \(CivilDate.display(trip.endsOn)) · \(trip.activeTravellers.count) \(trip.activeTravellers.count == 1 ? "person" : "people")"
          ).font(.subheadline).opacity(0.85)
          Text(ledger.unresolved > 0 ? "Known cost · conversion pending" : "This trip costs").font(
            .subheadline.weight(.semibold)
          ).padding(.top, 5)
          MoneyText(amount: ledger.total, currency: trip.homeCurrency, size: 52)
          Text(
            "\(Money.format(ledger.total / Int64(max(1, trip.activeTravellers.count)), trip.homeCurrency)) average each"
          ).font(.subheadline).opacity(0.88)
          BudgetBar(
            paid: ledger.paid, planned: ledger.planned, budget: budget, currency: trip.homeCurrency,
            hero: true)
          HStack {
            Text("\(Money.format(ledger.paid, trip.homeCurrency, compact: true)) paid")
            Spacer()
            Text(
              ledger.total > budget
                ? "\(Money.format(ledger.total - budget, trip.homeCurrency, compact: true)) over"
                : "\(Money.format(budget - ledger.total, trip.homeCurrency, compact: true)) left")
          }.font(.caption.weight(.semibold))
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.buttonStyle(.plain)
      HStack(alignment: .bottom, spacing: 5) {
        ForEach(trip.days) { day in
          let amount = Ledger(trip, expenses: trip.expenses(for: .init(kind: .day, id: day.id)))
            .total
          Capsule().fill(.white.opacity(day.date > trip.today ? 0.35 : 0.9)).frame(
            height: max(6, min(44, CGFloat(amount) / CGFloat(max(1, ledger.total)) * 150))
          ).overlay(alignment: .bottom) {
            if day.date == trip.today {
              Circle().fill(.white).frame(width: 4, height: 4).offset(y: 7)
            }
          }
        }
      }.frame(height: 48).padding(.bottom, 8).accessibilityHidden(true)
      HStack {
        Button {
          model.open(trip)
          model.openDay(trip.currentAttachment)
        } label: {
          Text(
            "Today in \(trip.stop(for: trip.currentAttachment)?.place ?? "your trip") \(trip.stop(for: trip.currentAttachment)?.flag ?? "")"
          ).font(.caption.weight(.heavy)).padding(12).background(
            .white.opacity(0.18), in: Capsule())
        }
        Spacer()
        Button {
          model.open(trip)
          model.editExpense(trip: trip, attachment: trip.currentAttachment)
        } label: {
          Image(systemName: "plus").font(.title2.weight(.bold)).foregroundStyle(Theme.accent).frame(
            width: 46, height: 46
          ).background(.white, in: RoundedRectangle(cornerRadius: 16))
        }.accessibilityLabel("Add today’s expense")
      }
    }.padding(21).foregroundStyle(.white).background(
      Theme.accent, in: RoundedRectangle(cornerRadius: 28)
    ).shadow(color: Theme.accent.opacity(0.23), radius: 18, y: 10)
  }
}
