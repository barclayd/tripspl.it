import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign
import TripSplitWatchModel

/// D4 · Days. Newest first with today outlined, then the days still to come.
struct DaysPage: View {
  let pages: TripPages

  var body: some View {
    let rows = pages.dayRows
    ScrollView {
      VStack(alignment: .leading, spacing: 6) {
        Text("Days")
          .watchFont(15, .black)
          .padding(.horizontal, 6)
          .accessibilityAddTraits(.isHeader)
        ForEach(rows.started) { row($0) }
        if !rows.upcoming.isEmpty {
          SectionLabel("Still to come", colour: WatchTheme.ink3)
          ForEach(rows.upcoming) { row($0) }
        }
      }
    }
    .containerBackground(.black, for: .tabView)
  }

  private func row(_ row: TripPages.DayRow) -> some View {
    NavigationLink(value: TripRoute.day(trip: pages.trip.id, day: row.id)) {
      DayRowView(row: row, currency: pages.currency)
    }
    .buttonStyle(.plain)
  }
}

/// "🇵🇹 Today · Porto / Day 4 · Sat   £59".
struct DayRowView: View {
  let row: TripPages.DayRow
  let currency: String

  var body: some View {
    let weekday = CivilDate.display(row.day.date, format: "EEE")
    HStack(spacing: 8) {
      Text(row.flag).font(.system(size: 15)).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 4) {
          Text(row.isToday ? "Today · \(row.place)" : row.place).watchFont(13, .black)
          if row.hasUnsynced { UnsyncedDot() }
        }
        Text("Day \(row.number) · \(weekday)")
          .watchFont(10, .bold)
          .foregroundStyle(WatchTheme.ink2)
      }
      .lineLimit(1)
      Spacer(minLength: 2)
      if row.hasStarted || row.spending.count > 0 {
        Text(WatchCurrency.whole(row.spending.amount, currency))
          .watchFont(13, .black)
          .lineLimit(1)
          .fixedSize()
      } else {
        Text("Nothing yet").watchFont(11, .bold).foregroundStyle(WatchTheme.ink3).fixedSize()
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 46)
    .background(WatchTheme.card, in: .rect(cornerRadius: 16))
    .overlay {
      if row.isToday {
        RoundedRectangle(cornerRadius: 16).strokeBorder(WatchTheme.accentText, lineWidth: 2)
      }
    }
    .contentShape(.rect(cornerRadius: 16))
    .accessibilityElement(children: .combine)
  }
}

/// One day's spends, reached from Days.
struct DayView: View {
  let pages: TripPages
  let dayID: String

  var body: some View {
    ScrollView {
      if let day = pages.trip.days.first(where: { $0.id == dayID }) {
        let spending = pages.trip.spending(on: day)
        let items = pages.items(day)
        VStack(alignment: .leading, spacing: 0) {
          DayHeader(pages: pages, day: day)
          Text(WatchCurrency.format(spending.amount, pages.currency))
            .watchFont(30, .black)
            .tracking(em: -0.02, size: 30)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.top, 8)
          Text("\(spending.count) \(spending.count == 1 ? "thing" : "things")")
            .watchFont(12, .bold)
            .foregroundStyle(WatchTheme.ink2)
          VStack(spacing: 5) {
            if items.isEmpty {
              Text("Nothing yet")
                .watchFont(12, .bold)
                .foregroundStyle(WatchTheme.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(items) { ExpenseRow(expense: $0, pages: pages) }
          }
          .padding(.top, 14)
        }
        .padding(.horizontal, 6)
      }
    }
    .containerBackground(.black, for: .navigation)
  }
}
