import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign
import TripSplitWatchModel

/// D3 · Who owes who. The same fewest transfers as the phone. Amounts involving you are green
/// when owed to you and red when you owe.
struct BalancesPage: View {
  let pages: TripPages

  var body: some View {
    let id = pages.trip.id
    ScrollView {
      VStack(alignment: .leading, spacing: 6) {
        Text("Who owes who")
          .watchFont(15, .black)
          .padding(.horizontal, 6)
          .accessibilityAddTraits(.isHeader)
        if !pages.balancesComplete {
          Notice(
            symbol: "exclamationmark.circle",
            text: "Conversions pending. Settle up once everything's converted.")
        } else if pages.settlements.isEmpty {
          Notice(symbol: "checkmark.circle", text: "All square. Nobody owes anything.")
        } else {
          ForEach(pages.settlements) { settlement in
            NavigationLink(value: TripRoute.person(trip: id, traveller: pages.subject(of: settlement))) {
              SettlementRow(pages: pages, settlement: settlement)
            }
            .buttonStyle(.plain)
          }
          Text("Tap a row to see that person")
            .watchFont(11, .bold)
            .foregroundStyle(WatchTheme.ink3)
            .padding(.horizontal, 6)
            .accessibilityHidden(true)
        }
        NavigationLink(value: TripRoute.people(id)) {
          HStack(spacing: 6) {
            Image(systemName: "person.2.fill").font(.system(size: 12, weight: .bold))
            Text("People · \(pages.people.count)").watchFont(13, .heavy)
            Spacer(minLength: 2)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy))
          }
          .foregroundStyle(WatchTheme.ink2)
          .padding(.horizontal, 12)
          .frame(height: 36)
          .background(WatchTheme.card, in: .capsule)
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
      }
    }
    .containerBackground(.black, for: .tabView)
  }
}

/// "T → M   £92".
struct SettlementRow: View {
  let pages: TripPages
  let settlement: Settlement

  var body: some View {
    HStack(spacing: 6) {
      PersonAvatar(pages: pages, id: settlement.from, size: 26)
      Image(systemName: "arrow.right")
        .font(.system(size: 13, weight: .heavy))
        .foregroundStyle(WatchTheme.ink3)
      PersonAvatar(pages: pages, id: settlement.to, size: 26)
      Spacer(minLength: 4)
      Text(WatchCurrency.whole(settlement.amount, pages.currency))
        .watchFont(17, .black)
        .foregroundStyle(colour)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .padding(.horizontal, 10)
    .frame(height: 46)
    .background(WatchTheme.card, in: .rect(cornerRadius: 18))
    .contentShape(.rect(cornerRadius: 18))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(pages.sentence(settlement))
  }

  private var colour: Color {
    if settlement.to == pages.you { return WatchTheme.good }
    if settlement.from == pages.you { return WatchTheme.bad }
    return .white
  }
}

/// A traveller's avatar by id, or an empty disc if they've left the trip entirely.
struct PersonAvatar: View {
  let pages: TripPages
  let id: String
  let size: CGFloat

  var body: some View {
    if let traveller = pages.traveller(id) {
      WatchAvatar(traveller, isYou: id == pages.you, size: size)
    } else {
      Circle().fill(WatchTheme.card2).frame(width: size, height: size)
    }
  }
}

struct Notice: View {
  let symbol: String
  let text: String

  var body: some View {
    Label(text, systemImage: symbol)
      .watchFont(12, .bold)
      .foregroundStyle(WatchTheme.ink2)
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(WatchTheme.card, in: .rect(cornerRadius: 18))
  }
}

/// E1 · People. Everyone on the trip, whoever owes most first.
struct PeopleView: View {
  let pages: TripPages

  var body: some View {
    let people = pages.people
    ScrollView {
      VStack(alignment: .leading, spacing: 6) {
        Text("People · \(people.count)")
          .watchFont(15, .black)
          .padding(.horizontal, 6)
          .accessibilityAddTraits(.isHeader)
        ForEach(people) { row in
          NavigationLink(value: TripRoute.person(trip: pages.trip.id, traveller: row.id)) {
            PersonRowView(pages: pages, row: row)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .containerBackground(.black, for: .navigation)
  }
}

struct PersonRowView: View {
  let pages: TripPages
  let row: TripPages.PersonRow

  var body: some View {
    HStack(spacing: 10) {
      WatchAvatar(row.traveller, isYou: row.isYou, size: 30)
      VStack(alignment: .leading, spacing: 1) {
        Text(row.isYou ? "You" : row.traveller.name).watchFont(14, .black)
        Text(pages.status(row))
          .watchFont(11, .heavy)
          .foregroundStyle(
            row.balance < 0 ? WatchTheme.bad : row.balance > 0 ? WatchTheme.good : WatchTheme.ink3)
      }
      .lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .frame(height: 50)
    .background(WatchTheme.card, in: .rect(cornerRadius: 18))
    .contentShape(.rect(cornerRadius: 18))
    .accessibilityElement(children: .combine)
  }
}

/// E2 · Person. What they owe or are owed, washed in their colour, with "Mark paid" for anything
/// between them and you.
struct PersonView: View {
  @Environment(WatchModel.self) private var model
  let pages: TripPages
  let travellerID: String

  var body: some View {
    let person = pages.person(travellerID)
    let traveller = pages.traveller(travellerID)
    let isYou = travellerID == pages.you
    ScrollView {
      VStack(spacing: 0) {
        PersonAvatar(pages: pages, id: travellerID, size: 46)
        Text(person.headline)
          .watchFont(16, .black)
          .multilineTextAlignment(.center)
          .padding(.top, 8)
          .contentTransition(.opacity)
        if let detail = person.detail {
          Text(detail)
            .watchFont(11, .bold)
            .foregroundStyle(WatchTheme.ink2)
            .multilineTextAlignment(.center)
            .padding(.top, 3)
        }
        if let settlement = person.settlement {
          MarkPaidButton(amount: WatchCurrency.whole(settlement.amount, pages.currency)) {
            model.markPaid(settlement, in: pages.trip)
          }
          .padding(.top, 14)
          // A fresh confirm step for each transfer, so a new balance never inherits a half-tap.
          .id(settlement)
        }
      }
      .frame(maxWidth: .infinity)
      .animation(.snappy, value: person)
    }
    .containerBackground(
      traveller?.wash(isYou: isYou) ?? WatchTheme.wash, for: .navigation)
  }
}

/// "Mark £66 paid", which asks for a second press or a double tap before it records anything.
struct MarkPaidButton: View {
  let amount: String
  let action: () -> Void
  @State private var confirming = false
  @State private var paid = 0

  var body: some View {
    Button {
      if confirming {
        confirming = false
        paid += 1
        action()
      } else {
        withAnimation(.snappy) { confirming = true }
      }
    } label: {
      Text(confirming ? "Tap again to confirm" : "Mark \(amount) paid")
        .watchFont(15, .black)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .contentTransition(.opacity)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
    }
    .buttonStyle(.plain)
    .background(confirming ? WatchTheme.tint : WatchTheme.card2, in: .capsule)
    .overlay {
      Capsule().strokeBorder(WatchTheme.accentText, lineWidth: confirming ? 2 : 0)
    }
    .contentShape(.capsule)
    .handGestureShortcut(.primaryAction, isEnabled: confirming)
    .sensoryFeedback(.success, trigger: paid)
    .task(id: confirming) {
      guard confirming else { return }
      try? await Task.sleep(for: .seconds(4))
      withAnimation(.snappy) { confirming = false }
    }
    .accessibilityLabel(confirming ? "Confirm \(amount) paid" : "Mark \(amount) paid")
  }
}
