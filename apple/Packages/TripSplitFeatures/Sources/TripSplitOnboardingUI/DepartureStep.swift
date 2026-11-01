import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitSharedUI

/// Step 2: the day you set off, then the day you're home, on one calendar. "Today" is the phone's
/// date, as you plan from where you are rather than where you're going.
struct DepartureStep: View {
  @Environment(AppModel.self) private var model
  @State private var timeZoneSelection: DestinationTimeZoneSelection?
  @State private var picking = End.leaving

  enum End { case leaving, home }

  private var draft: OnboardingDraft { model.onboarding }
  private var today: String { CivilDate.today(timeZone: TimeZone.current.identifier) }

  /// Stops in countries with several zones, or whose zone couldn't be worked out.
  private var ambiguousStops: [Stop] {
    draft.stops.filter {
      $0.resolvedTimeZone == nil
        || DestinationTimeZones.identifiers(countryCode: $0.countryCode).count > 1
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      StepTitle("How long is your trip?", "Pick the day you set off and return")
      DepartureCalendar(
        start: draft.startsOn, end: draft.returnDate, today: today, isSelectable: isSelectable,
        hint: picking == .leaving ? "Sets the day you set off" : "Sets the day you're home"
      ) { date in
        Haptics.selection()
        withAnimation(Motion.spring) { select(date) }
      }
      if !ambiguousStops.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          Kicker(title: "Time zones")
          ForEach(ambiguousStops) { stop in
            Button {
              timeZoneSelection = .init(id: stop.id)
            } label: {
              DestinationTimeZoneRow(
                place: stop.place, identifier: stop.resolvedTimeZone,
                date: CivilDate.date(draft.startsOn)
              )
              .padding(14)
              .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(PressStyle()).accessibilityIdentifier("onboarding.timezone.\(stop.id)")
          }
        }
      }
    }
    // A draft saved on an earlier day can't still leave in the past.
    .onAppear { if draft.startsOn < today { model.onboarding.setDeparture(today) } }
    .sheet(item: $timeZoneSelection) { selection in
      if let stop = draft.stops.first(where: { $0.id == selection.id }) {
        TimeZonePicker(
          selection: timeZoneBinding(for: stop.id),
          allowedIdentifiers: DestinationTimeZones.identifiers(countryCode: stop.countryCode),
          title: stop.place, referenceDate: CivilDate.date(draft.startsOn))
      }
    }
  }

  /// Any day from today. Picking home, it's also within a year of leaving, and leaves a night for
  /// each stop on a longer route; a day before leaving moves the start instead.
  private func isSelectable(_ date: String) -> Bool {
    guard date >= today else { return false }
    guard picking == .home, date >= draft.startsOn else { return true }
    let nights = CivilDate.days(from: draft.startsOn, to: date)
    return draft.tripNights.contains(nights)
  }

  /// The first tap moves the whole trip to leave that day, the next sets the day home, then it
  /// starts over. A day before leaving moves the start instead.
  private func select(_ date: String) {
    switch picking {
    case .leaving:
      model.onboarding.setDeparture(date)
      picking = .home
    case .home where date < draft.startsOn:
      model.onboarding.setDates(leaving: date, home: draft.returnDate)
    case .home:
      model.onboarding.setReturn(date)
      picking = .leaving
    }
  }

  private func timeZoneBinding(for stopID: String) -> Binding<String> {
    Binding(
      get: { model.onboarding.stops.first(where: { $0.id == stopID })?.resolvedTimeZone ?? "" },
      set: { zone in
        guard let index = model.onboarding.stops.firstIndex(where: { $0.id == stopID }) else {
          return
        }
        model.onboarding.stops[index].timeZone = zone
      })
  }
}

/// A Monday-first month grid that shades the whole trip, from departure to the day you're back.
struct DepartureCalendar: View {
  init(
    start: String, end: String, today: String,
    isSelectable: @escaping (String) -> Bool = { _ in true }, hint: String = "",
    select: @escaping (String) -> Void
  ) {
    self.start = start
    self.end = end
    self.today = today
    self.isSelectable = isSelectable
    self.hint = hint
    self.select = select
    _month = State(initialValue: Self.firstOfMonth(start))
  }
  let start: String
  let end: String
  let today: String
  let isSelectable: (String) -> Bool
  let hint: String
  let select: (String) -> Void
  @State private var month: String
  /// The open Duo shows two months side by side, so a trip across a month end fits in one view.
  @Environment(\.onboardingWide) private var wide

  private static let weekdays = ["M", "T", "W", "T", "F", "S", "S"]
  private static let weekdayNames = [
    "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
  ]

  var body: some View {
    Group {
      if wide {
        HStack(alignment: .top, spacing: 12) {
          card(month) { compactHeader(month, symbol: "chevron.left", label: "Previous month", offset: -1) }
          card(Self.addingMonths(1, to: month)) {
            compactHeader(
              Self.addingMonths(1, to: month), symbol: "chevron.right", label: "Next month", offset: 1)
          }
        }
      } else {
        card(month) { header }
      }
    }
    .onChange(of: start) { _, start in
      let shown = Self.firstOfMonth(start)
      let visible = wide ? [month, Self.addingMonths(1, to: month)] : [month]
      if !visible.contains(shown) { month = shown }
    }
  }

  private func card(_ month: String, @ViewBuilder header: () -> some View) -> some View {
    VStack(spacing: 8) {
      header()
      HStack(spacing: 0) {
        ForEach(Self.weekdays.indices, id: \.self) { index in
          Text(Self.weekdays[index]).typeface(11, .heavy, relativeTo: .caption2, maximum: 1.3)
            .foregroundStyle(Theme.tertiary).frame(maxWidth: .infinity)
            .accessibilityLabel(Self.weekdayNames[index])
        }
      }.accessibilityHidden(true)
      let weeks = weeks(month)
      VStack(spacing: 2) {
        ForEach(weeks.indices, id: \.self) { row in
          HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { column in
              if let date = weeks[row][column] {
                cell(date, column: column, month: month)
              } else {
                Color.clear.frame(maxWidth: .infinity).frame(height: cellHeight)
              }
            }
          }
        }
      }
      .id(month)
      .animation(Motion.spring, value: start)
      // Keeps both months the same height when one runs to six weeks.
      if wide, weeks.count < 6 {
        Color.clear.frame(height: CGFloat(6 - weeks.count) * (cellHeight + 2))
      }
    }
    .padding(.top, 12).padding(.horizontal, 12).padding(.bottom, 10)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
  }

  private var cellHeight: CGFloat { wide ? 36 : 40 }

  /// The month on the left with one arrow: the open Duo's side-by-side months.
  private func compactHeader(_ month: String, symbol: String, label: String, offset: Int)
    -> some View
  {
    HStack {
      Text(CivilDate.display(month, format: "MMMM yyyy"))
        .typeface(15, .heavy, relativeTo: .headline, maximum: 1.3).foregroundStyle(Theme.ink)
        .contentTransition(.numericText()).accessibilityAddTraits(.isHeader)
      Spacer(minLength: 4)
      monthButton(symbol, label: label, offset: offset, size: 30)
    }
    .padding(.leading, 6).frame(height: 36)
  }

  private var header: some View {
    HStack {
      monthButton("chevron.left", label: "Previous month", offset: -1)
      Spacer()
      Text(CivilDate.display(month, format: "MMMM yyyy"))
        .typeface(16, .heavy, relativeTo: .headline, maximum: 1.3).foregroundStyle(Theme.ink)
        .contentTransition(.numericText()).accessibilityAddTraits(.isHeader)
      Spacer()
      monthButton("chevron.right", label: "Next month", offset: 1)
    }
  }

  private func monthButton(_ symbol: String, label: String, offset: Int, size: CGFloat = 34)
    -> some View
  {
    // Nothing before this month can be picked, so there's no going back past it.
    let isDisabled = offset < 0 && month <= Self.firstOfMonth(today)
    return Button {
      withAnimation(Motion.push) { month = Self.addingMonths(offset, to: month) }
    } label: {
      Image(systemName: symbol).font(.system(size: 13, weight: .heavy))
        .foregroundStyle(isDisabled ? Theme.tertiary : Theme.ink).frame(width: size, height: size)
        .background(Theme.inset, in: Circle())
        .frame(width: 44, height: 44).contentShape(Rectangle())
    }.buttonStyle(PressStyle(scale: 0.9)).disabled(isDisabled).accessibilityLabel(label)
  }

  private func cell(_ date: String, column: Int, month: String) -> some View {
    let isStart = date == start
    let isEnd = date == end && end != start
    let inRange = date >= start && date <= end
    let isDisabled = !isSelectable(date)
    let day = Int(date.suffix(2)) ?? 0
    let lastDay = Self.daysInMonth(month)
    let leftFilled = inRange && !isStart
    let rightFilled = inRange && date != end
    let roundLeading: CGFloat = column == 0 || day == 1 ? 20 : 0
    let roundTrailing: CGFloat = column == 6 || day == lastDay ? 20 : 0
    return Button {
      select(date)
    } label: {
      ZStack {
        HStack(spacing: 0) {
          Rectangle().fill(leftFilled ? Theme.accentSoft : .clear)
          Rectangle().fill(rightFilled ? Theme.accentSoft : .clear)
        }
        .clipShape(
          UnevenRoundedRectangle(
            topLeadingRadius: roundLeading, bottomLeadingRadius: roundLeading,
            bottomTrailingRadius: roundTrailing, topTrailingRadius: roundTrailing)
        )
        .frame(height: cellHeight - 4)
        Circle().fill(isStart ? Theme.accent : isEnd ? Theme.ink : .clear)
          .overlay {
            if date == today, !isStart, !isEnd {
              Circle().strokeBorder(Theme.tertiary, lineWidth: 1.5)
            }
          }
          // Shrinks with a narrow column, so two months side by side fit beside the open Duo's sidebar.
          .aspectRatio(1, contentMode: .fit).frame(maxWidth: cellHeight - 4, maxHeight: cellHeight - 4)
          .scaleEffect(isStart ? 1.08 : 1)
        Text("\(day)")
          .typeface(15, isStart || isEnd ? .heavy : .bold, relativeTo: .body, maximum: 1.25)
          .monospacedDigit()
          .foregroundStyle(
            isStart
              ? Theme.accentInk
              : isEnd
                ? Theme.background
                : isDisabled ? Theme.tertiary.opacity(0.6) : inRange ? Theme.accentText : Theme.ink)
      }
      .frame(maxWidth: .infinity).frame(height: cellHeight).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .accessibilityLabel(CivilDate.display(date, format: "EEEE d MMMM yyyy"))
    .accessibilityValue(
      isStart ? "Leaving" : isEnd ? "Home" : inRange ? "On your trip" : date == today ? "Today" : "")
    .accessibilityAddTraits(isStart || isEnd ? .isSelected : [])
    .accessibilityHint(hint)
    .accessibilityIdentifier("onboarding.calendar.\(date)")
  }

  /// Each week of the shown month, Monday first, with nil padding either side.
  private func weeks(_ month: String) -> [[String?]] {
    let calendar = CivilDate.calendar()
    let first = CivilDate.date(month)
    let weekday = calendar.component(.weekday, from: first)
    let leading = (weekday + 5) % 7
    let days = (0..<Self.daysInMonth(month)).map { CivilDate.adding($0, to: month) }
    var cells: [String?] = Array(repeating: nil, count: leading) + days
    cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
    return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
  }

  private static func firstOfMonth(_ date: String) -> String { String(date.prefix(8)) + "01" }

  private static func addingMonths(_ months: Int, to date: String) -> String {
    let calendar = CivilDate.calendar()
    guard let moved = calendar.date(byAdding: .month, value: months, to: CivilDate.date(date))
    else { return date }
    return firstOfMonth(CivilDate.string(moved))
  }

  private static func daysInMonth(_ month: String) -> Int {
    CivilDate.calendar().range(of: .day, in: .month, for: CivilDate.date(month))?.count ?? 30
  }
}
