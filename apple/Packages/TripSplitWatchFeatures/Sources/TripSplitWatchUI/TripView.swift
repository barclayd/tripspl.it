import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign
import TripSplitWatchModel

/// Everywhere a trip can be opened from, by id, so a page always shows the latest sync.
enum TripRoute: Hashable {
  /// A trip, opening on a page when a complication or notification asks for one.
  case trip(String, page: TripPages.Page? = nil)
  case day(trip: String, day: String)
  case people(String)
  case person(trip: String, traveller: String)

  var tripID: String {
    switch self {
    case .trip(let id, _), .people(let id): id
    case .day(let id, _), .person(let id, _): id
    }
  }
}

/// Resolves a route against the model's trips, falling back when the phone has removed the trip.
struct TripDestination: View {
  @Environment(WatchModel.self) private var model
  let route: TripRoute

  var body: some View {
    if let trip = model.trip(route.tripID) {
      let pages = model.pages(for: trip)
      switch route {
      case .trip(_, let page): TripView(pages: pages, page: page)
      case .day(_, let day): DayView(pages: pages, dayID: day)
      case .people: PeopleView(pages: pages)
      case .person(_, let traveller): PersonView(pages: pages, travellerID: traveller)
      }
    } else {
      ContentUnavailableView(
        "Trip removed", systemImage: "suitcase",
        description: Text("It's no longer on your iPhone."))
    }
  }
}

/// A trip as vertical pages: Today (while it's happening), Budget, Who owes who and Days.
struct TripView: View {
  @Environment(WatchModel.self) private var model
  let pages: TripPages
  @State private var page: TripPages.Page
  @State private var logging = false

  init(pages: TripPages, page: TripPages.Page? = nil) {
    self.pages = pages
    let page = page.flatMap { pages.pages.contains($0) ? $0 : nil }
    _page = State(initialValue: page ?? pages.firstPage)
  }

  var body: some View {
    TabView(selection: $page) {
      ForEach(pages.pages, id: \.self) { page in
        content(page).tag(page)
      }
    }
    .tabViewStyle(.verticalPage)
    .toolbar {
      if pages.canLog {
        ToolbarItem(placement: .topBarTrailing) {
          LogButton { logging = true }
        }
      }
    }
    .sheet(isPresented: $logging) { LogExpenseView(model: model, trip: pages.trip) }
  }

  @ViewBuilder private func content(_ page: TripPages.Page) -> some View {
    switch page {
    case .today:
      if let day = pages.today {
        TodayPage(pages: pages, day: day)
      }
    case .budget: BudgetPage(pages: pages)
    case .balances: BalancesPage(pages: pages)
    case .days: DaysPage(pages: pages)
    }
  }
}

/// D1 · Today. Where you are, what today has cost against the daily budget, and, past the bar,
/// everything logged today.
struct TodayPage: View {
  let pages: TripPages
  let day: TripDay

  var body: some View {
    let spending = pages.trip.spending(on: day)
    let items = pages.items(day)
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        DayHeader(pages: pages, day: day)
        Text(WatchCurrency.format(spending.amount, pages.currency))
          .watchFont(40, .black)
          .tracking(em: -0.02, size: 40)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .contentTransition(.numericText(value: Double(spending.amount)))
          .padding(.top, 10)
        Text(caption(spending))
          .watchFont(12, .bold)
          .foregroundStyle(spending.unresolved > 0 ? WatchTheme.amber : WatchTheme.ink2)
          .padding(.top, 1)
        if spending.budget > 0 {
          Meter(
            value: spending.fraction, fill: WatchTheme.accentText, track: WatchTheme.card2,
            height: 7
          )
          .padding(.top, 14)
          Text(budgetLine(spending))
            .watchFont(12, .heavy)
            .foregroundStyle(spending.left >= 0 ? WatchTheme.good : WatchTheme.bad)
            .padding(.top, 8)
        }
        VStack(spacing: 5) {
          if items.isEmpty {
            Text("Nothing logged today")
              .watchFont(12, .bold)
              .foregroundStyle(WatchTheme.ink3)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          ForEach(items) { ExpenseItem(expense: $0, pages: pages) }
        }
        .padding(.top, 22)
      }
      .padding(.horizontal, 6)
    }
    .containerBackground(WatchTheme.wash, for: .tabView)
  }

  /// "spent today · 3 things", noting spends still waiting for a rate.
  private func caption(_ spending: DaySpending) -> String {
    if spending.unresolved > 0 { return "spent today · \(spending.unresolved) not converted" }
    return "spent today · \(spending.count) \(spending.count == 1 ? "thing" : "things")"
  }

  /// "£241 left of £300" or "£42 over".
  private func budgetLine(_ spending: DaySpending) -> String {
    let budget = WatchCurrency.whole(spending.budget, pages.currency)
    return spending.left >= 0
      ? "\(WatchCurrency.whole(spending.left, pages.currency)) left of \(budget)"
      : "\(WatchCurrency.whole(-spending.left, pages.currency)) over \(budget)"
  }
}

/// "🇵🇹 Porto" over "Day 4 of 8 · Sat 31 Oct".
struct DayHeader: View {
  let pages: TripPages
  let day: TripDay

  var body: some View {
    let stop = pages.stop(day)
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        if let flag = stop?.flag, !flag.isEmpty { Text(flag).font(.system(size: 16)) }
        Text(stop?.place ?? pages.trip.destination).watchFont(16, .black).lineLimit(1)
      }
      Text(pages.dayLine(day))
        .watchFont(11, .bold)
        .foregroundStyle(WatchTheme.ink2)
        .lineLimit(1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

/// D2 · Budget. A ring that laps past 100% in red, like an Activity ring overshooting.
struct BudgetPage: View {
  let pages: TripPages

  var body: some View {
    let over = pages.spent - pages.budget
    let each = WatchCurrency.whole(pages.each, pages.currency)
    VStack(spacing: 0) {
      ZStack {
        BudgetRing(fraction: pages.budgetFraction)
        VStack(spacing: 0) {
          if pages.budget > 0 {
            Text(pages.budgetFraction, format: .percent.precision(.fractionLength(0)))
              .watchFont(26, .black)
            Text("of \(WatchCurrency.whole(pages.budget, pages.currency))")
              .watchFont(10, .heavy)
              .foregroundStyle(WatchTheme.ink2)
          } else {
            Text("No budget").watchFont(13, .black).foregroundStyle(WatchTheme.ink2)
          }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 18)
      }
      .frame(width: 126, height: 126)
      Text("\(WatchCurrency.whole(pages.spent, pages.currency)) spent")
        .watchFont(16, .black)
        .padding(.top, 10)
      Group {
        if pages.budget == 0 {
          Text("\(each) each").foregroundStyle(WatchTheme.ink2)
        } else if over > 0 {
          Text("\(WatchCurrency.whole(over, pages.currency)) over · \(each) each")
            .foregroundStyle(WatchTheme.bad)
        } else {
          Text("\(WatchCurrency.whole(-over, pages.currency)) left · \(each) each")
            .foregroundStyle(WatchTheme.good)
        }
      }
      .watchFont(12, .heavy)
      .padding(.top, 2)
    }
    .lineLimit(1)
    .minimumScaleFactor(0.8)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
    .containerBackground(.black, for: .tabView)
  }
}

struct BudgetRing: View {
  let fraction: Double
  private let width: CGFloat = 13

  var body: some View {
    ZStack {
      Circle().stroke(WatchTheme.card2, lineWidth: width)
      Circle()
        .trim(from: 0, to: min(fraction, 1))
        .stroke(WatchTheme.accentText, style: StrokeStyle(lineWidth: width, lineCap: .round))
      if fraction > 1 {
        Circle()
          .trim(from: 0, to: min(fraction - 1, 1))
          .stroke(WatchTheme.bad, style: StrokeStyle(lineWidth: width, lineCap: .round))
          .shadow(color: .black.opacity(0.45), radius: 3)
      }
    }
    .rotationEffect(.degrees(-90))
    .padding(width / 2)
    .accessibilityHidden(true)
  }
}
