import SwiftUI
import TripSplitWatchModel
import TripSplitWidgetModel
import WidgetKit

// MARK: Shared pieces

/// A widget's top line: flag, a title and something trailing, all 13pt semibold.
struct WidgetHeader<Trailing: View>: View {
  var place: Place?
  var title: String
  var flagSize: CGFloat = 15
  var titleSize: CGFloat = 13
  var titleWeight: Font.Weight = .semibold
  var titleColor: Color?
  @ViewBuilder var trailing: Trailing
  @Environment(\.widgetLook) private var look

  var body: some View {
    HStack(spacing: 5) {
      if let place { FlagMark(place: place, size: flagSize) }
      // Long titles ("Who owes who") shrink a touch rather than truncate in the small width.
      Text(title).type(titleSize, titleWeight).foregroundStyle(titleColor ?? look.palette.ink)
        .lineLimit(1).minimumScaleFactor(0.85)
      Spacer(minLength: Trailing.self == EmptyView.self ? 0 : 4)
      trailing
    }
  }
}

extension WidgetHeader where Trailing == EmptyView {
  init(
    place: Place?, title: String, flagSize: CGFloat = 15, titleSize: CGFloat = 13,
    titleWeight: Font.Weight = .semibold, titleColor: Color? = nil
  ) {
    self.init(
      place: place, title: title, flagSize: flagSize, titleSize: titleSize,
      titleWeight: titleWeight, titleColor: titleColor
    ) { EmptyView() }
  }
}

/// An 11pt semibold secondary caption.
struct Caption: View {
  var text: String
  @Environment(\.widgetLook) private var look

  var body: some View {
    Text(text).type(11).foregroundStyle(look.palette.ink2).lineLimit(1).minimumScaleFactor(0.85)
  }
}

// MARK: B1 Today

/// Small Today: what's left to spend today (or on the whole trip), in big type over a 12-segment
/// gauge. Opens Trip › Today.
public struct TodaySmallView: View {
  var figures: TodayFigures
  @Environment(\.widgetLook) private var look

  public init(figures: TodayFigures) {
    self.figures = figures
  }

  public var body: some View {
    Group {
      if look.standBy {
        standBy
      } else {
        TodaySummary(figures: figures)
      }
    }
    .widgetURL(WatchLink.trip(figures.tripID, page: .today).url)
  }

  /// D2: rebuilt bigger rather than scaled, with colour only in the gauge.
  private var standBy: some View {
    VStack(alignment: .leading, spacing: 0) {
      WidgetHeader(
        place: figures.place, title: figures.title, flagSize: 12, titleSize: 11,
        titleColor: look.palette.ink2)
      Spacer(minLength: 0)
      Text(figures.budget.hero).figure(52).foregroundStyle(look.palette.ink).amount(look)
      Text(figures.label).type(12).foregroundStyle(look.palette.ink2)
      SegmentBar(
        count: 12, filled: figures.budget.filled(12), color: figures.budget.color(look.palette),
        height: 5, gap: 2.5
      )
      .padding(.top, 8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

/// B1's content, shared by the small, medium and placeholder layouts.
struct TodaySummary: View {
  var figures: TodayFigures
  var showsHeader = true
  @Environment(\.widgetLook) private var look
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if showsHeader {
        WidgetHeader(place: figures.place, title: figures.place.name) {
          if !typeSize.isAccessibilitySize {
            Text(figures.dayLabel).type(13).foregroundStyle(look.palette.ink2).lineLimit(1)
          }
        }
      }
      Spacer(minLength: 0)
      Text(figures.budget.hero).figure(34)
        .foregroundStyle(figures.budget.isOver ? look.palette.bad : look.palette.ink)
        .widgetAccentable().amount(look)
      Text(figures.label).type(13).foregroundStyle(look.palette.ink2).padding(.top, 2)
      SegmentBar(
        count: 12, filled: figures.budget.filled(12), color: figures.budget.color(look.palette)
      )
      .padding(.top, 10)
      if !typeSize.isAccessibilitySize {
        Caption(text: figures.budget.caption).amount(look).padding(.top, 6)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibility)
  }

  private var accessibility: String {
    var parts = [figures.place.name]
    if !figures.dayLabel.isEmpty { parts.append(figures.dayLabel) }
    parts.append(figures.line)
    parts.append(figures.budget.caption)
    return parts.joined(separator: ", ")
  }
}

// MARK: B6 Today with actions

/// Medium Today: B1 on the left, the local rate and Convert and Log expense buttons on the right.
public struct TodayMediumView: View {
  var figures: TodayFigures
  @Environment(\.widgetLook) private var look

  public init(figures: TodayFigures) {
    self.figures = figures
  }

  public var body: some View {
    HStack(spacing: 16) {
      TodaySummary(figures: figures)
      VStack(spacing: 8) {
        if let rate = figures.rate {
          RateChip(text: rate).frame(maxWidth: .infinity, alignment: .trailing)
        }
        Spacer(minLength: 0)
        Actions(tripID: figures.tripID, axis: .vertical)
      }
      .frame(width: 124)
    }
    .widgetURL(WatchLink.trip(figures.tripID, page: .today).url)
  }
}

/// Convert and Log expense, as links so they work from the Home Screen without an intent.
struct Actions: View {
  var tripID: String
  var axis: Axis

  var body: some View {
    let layout = axis == .vertical ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
    layout {
      Link(destination: WatchLink.convert.url) {
        CapsuleLabel(title: "Convert", symbol: "arrow.left.arrow.right", kind: .secondary)
      }
      Link(destination: WatchLink.log(trip: tripID).url) {
        CapsuleLabel(title: "Log expense", symbol: "plus", kind: .primary)
      }
    }
  }
}

// MARK: B9 Large

/// Large: the watch's four trip pages in one view, with both actions.
public struct TodayLargeView: View {
  var today: TodayFigures
  var progress: ProgressFigures?
  var daily: DailyFigures?
  var balances: BalanceFigures?
  @Environment(\.widgetLook) private var look

  public init(
    today: TodayFigures, progress: ProgressFigures?, daily: DailyFigures?,
    balances: BalanceFigures?
  ) {
    self.today = today
    self.progress = progress
    self.daily = daily
    self.balances = balances
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      WidgetHeader(place: today.place, title: today.tripName, flagSize: 16, titleWeight: .bold) {
        Text(today.dayOfDays).type(13).foregroundStyle(look.palette.ink2).lineLimit(1)
      }
      if let progress {
        DaySegments(groups: progress.groups, height: 5).padding(.top, 8)
      }
      hero.padding(.top, 12)
      SegmentBar(count: 12, filled: today.budget.filled(12), color: today.budget.color(look.palette))
        .padding(.top, 8)
      if let daily {
        rule
        DailyChart(figures: daily, height: 40, gap: 10)
      }
      if let balances, !balances.rows.isEmpty {
        rule
        VStack(spacing: 8) {
          ForEach(Array(balances.rows.prefix(2).enumerated()), id: \.offset) { index, row in
            BalanceRow(row: row, primary: index == 0)
          }
        }
      }
      Spacer(minLength: 12)
      Actions(tripID: today.tripID, axis: .horizontal)
    }
    .widgetURL(WatchLink.trip(today.tripID).url)
  }

  private var hero: some View {
    HStack(alignment: .bottom, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(today.budget.hero).figure(38)
          .foregroundStyle(today.budget.isOver ? look.palette.bad : look.palette.ink)
          .widgetAccentable().amount(look)
        Text("\(today.label) · \(today.budget.caption)").type(13)
          .foregroundStyle(look.palette.ink2).lineLimit(1).minimumScaleFactor(0.8).amount(look)
      }
      .accessibilityElement(children: .combine)
      Spacer(minLength: 0)
      if let rate = today.rate { RateChip(text: rate).padding(.bottom, 2) }
    }
  }

  private var rule: some View {
    Rectangle().fill(look.palette.track).frame(height: 1).padding(.vertical, 12)
  }
}

/// "Tom owes you" and the amount, for the large widget.
struct BalanceRow: View {
  var row: BalanceFigures.Row
  var primary: Bool
  @Environment(\.widgetLook) private var look

  var body: some View {
    HStack(spacing: 8) {
      InitialAvatar(initial: row.initial, hue: row.hue, size: 22)
      Text(row.text).type(13).foregroundStyle(primary ? look.palette.ink : look.palette.ink2)
        .lineLimit(1)
      Spacer(minLength: 4)
      Text(row.amount).figure(17).foregroundStyle(color).amount(look)
    }
    .accessibilityElement(children: .combine)
  }

  private var color: Color {
    row.tone == .owedToYou ? look.palette.good : look.palette.ink
  }
}

// MARK: B2 Quick convert

/// The 30pt Swap circle. The widget extension wraps it in a `Button(intent:)`.
public struct SwapBadge: View {
  @Environment(\.widgetLook) private var look

  public init() {}

  public var body: some View {
    Image(systemName: "arrow.left.arrow.right").font(.system(size: 14, weight: .bold))
      .foregroundStyle(look.palette.accentText)
      .frame(width: 30, height: 30)
      .background(look.palette.accentSoft, in: Circle())
      .accessibilityLabel("Swap currencies")
  }
}

/// Small Quick convert: four handy amounts in the local currency and what they come to at home.
/// Opens Quick convert.
public struct ConvertSmallView<Swap: View>: View {
  var figures: ConvertFigures
  var swap: Swap
  @Environment(\.widgetLook) private var look

  public init(figures: ConvertFigures, @ViewBuilder swap: () -> Swap) {
    self.figures = figures
    self.swap = swap()
  }

  public var body: some View {
    Group {
      if look.standBy {
        standBy
      } else {
        regular
      }
    }
    .widgetURL(WatchLink.convert.url)
  }

  private var place: Place { Place(flag: figures.flag, code: figures.code, name: "") }

  private var regular: some View {
    VStack(alignment: .leading, spacing: 0) {
      WidgetHeader(place: place, title: figures.title) { swap }
        .accessibilityElement(children: .contain)
      Spacer(minLength: 4)
      VStack(spacing: 2) {
        ForEach(figures.rows, id: \.self) { row in
          HStack(alignment: .firstTextBaseline) {
            Text(row.from).type(13).foregroundStyle(look.palette.ink2)
            Spacer(minLength: 4)
            Text(row.to).figure(17, tracking: 0).foregroundStyle(look.palette.ink)
              .widgetAccentable()
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(row.from) is \(row.to)")
        }
      }
      Caption(text: caption).padding(.top, 6)
    }
  }

  /// D2: the ×10 amount, huge.
  private var standBy: some View {
    VStack(alignment: .leading, spacing: 0) {
      WidgetHeader(
        place: place, title: figures.title, flagSize: 12, titleSize: 11,
        titleColor: look.palette.ink2)
      Spacer(minLength: 0)
      Text(figures.sample.from).figure(22).foregroundStyle(look.palette.ink2)
      Text(figures.sample.to).figure(52).foregroundStyle(look.palette.ink)
      Caption(text: caption).padding(.top, 2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(figures.sample.from) is \(figures.sample.to). \(figures.rate)")
  }

  /// "€1 = £0.862 · 08:00".
  private var caption: String {
    guard let fetched = figures.fetchedAt else { return figures.rate }
    return "\(figures.rate) · \(fetched.formatted(date: .omitted, time: .shortened))"
  }
}

extension ConvertSmallView where Swap == SwapBadge {
  /// With a Swap badge that does nothing, for previews and the gallery.
  public init(figures: ConvertFigures) {
    self.init(figures: figures) { SwapBadge() }
  }
}

// MARK: B3 Where you are

/// Small Where you are: today's stop, the day and one segment per day grouped by stop. Opens the
/// trip's days.
public struct WhereSmallView: View {
  var figures: ProgressFigures
  @Environment(\.widgetLook) private var look
  @Environment(\.dynamicTypeSize) private var typeSize

  public init(figures: ProgressFigures) {
    self.figures = figures
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      FlagMark(place: figures.place, size: 34)
      Spacer(minLength: 0)
      Text(figures.place.name).figure(24).foregroundStyle(look.palette.ink)
      Text(figures.dayOfDays).type(13).foregroundStyle(look.palette.ink2).padding(.top, 2)
      DaySegments(groups: figures.groups).padding(.top, 10)
      if !typeSize.isAccessibilitySize {
        Caption(text: figures.next).padding(.top, 6)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(figures.place.name), \(figures.dayOfDays). Next: \(figures.next)")
    .widgetURL(WatchLink.trip(figures.tripID, page: .days).url)
  }
}

// MARK: B4 Countdown

/// Small Countdown: days to go and how far through the wait, or a greeting on departure day.
/// Opens the trip.
public struct CountdownSmallView: View {
  var figures: CountdownFigures
  @Environment(\.widgetLook) private var look
  @Environment(\.dynamicTypeSize) private var typeSize

  public init(figures: CountdownFigures) {
    self.figures = figures
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      WidgetHeader(place: figures.place, title: figures.place.name)
      Spacer(minLength: 0)
      if figures.isDepartureDay {
        Text(figures.greeting).font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(look.palette.accentText).lineLimit(1).minimumScaleFactor(0.5)
          .widgetAccentable()
        Text("You leave today").type(13).foregroundStyle(look.palette.ink2).padding(.top, 2)
      } else {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
          Text("\(figures.days)").figure(48, tracking: -0.02).foregroundStyle(look.palette.ink)
            .widgetAccentable()
          Text(figures.unit).type(15).foregroundStyle(look.palette.ink2)
        }
      }
      SegmentBar(count: 10, filled: figures.filled(10), color: look.palette.accent)
        .padding(.top, 10)
      if !typeSize.isAccessibilitySize {
        Caption(text: figures.isDepartureDay ? figures.firstLeg ?? figures.caption : figures.caption)
          .padding(.top, 6)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      figures.isDepartureDay
        ? "\(figures.place.name). You leave today. \(figures.firstLeg ?? "")"
        : "\(figures.line). \(figures.caption)")
    .widgetURL(WatchLink.trip(figures.tripID).url)
  }
}

// MARK: B5 Who owes who

/// Small Who owes who: your balance big, the biggest other one underneath. Opens Who owes who.
public struct BalanceSmallView: View {
  var figures: BalanceFigures
  @Environment(\.widgetLook) private var look

  public init(figures: BalanceFigures) {
    self.figures = figures
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      WidgetHeader(place: figures.place, title: "Who owes who")
      Spacer(minLength: 0)
      if let row = figures.yours ?? figures.others {
        HStack(spacing: 6) {
          InitialAvatar(initial: row.initial, hue: row.hue, size: 20)
          Text(row.text).type(13).foregroundStyle(look.palette.ink).lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        Text(row.amount).figure(34)
          .foregroundStyle(row.tone == .owedToYou ? look.palette.good : look.palette.ink)
          .widgetAccentable().amount(look).padding(.top, 4)
        Caption(text: caption(after: row)).amount(look).padding(.top, 6)
      } else {
        Text(figures.pending ? "Converting" : "All square").figure(24)
          .foregroundStyle(look.palette.ink)
        Caption(
          text: figures.pending ? "Balances update once rates arrive" : "Nobody owes anything"
        )
        .padding(.top, 6)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .widgetURL(WatchLink.trip(figures.tripID, page: .balances).url)
  }

  private func caption(after row: BalanceFigures.Row) -> String {
    figures.rows.first { $0 != row }?.line ?? " "
  }
}

// MARK: B7 Daily spend

/// Medium Daily spend: each day against the daily budget. Opens Budget.
public struct DailyMediumView: View {
  var figures: DailyFigures
  @Environment(\.widgetLook) private var look

  public init(figures: DailyFigures) {
    self.figures = figures
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      WidgetHeader(place: figures.place, title: "Daily spend") {
        Text(figures.budgetLabel).type(13).foregroundStyle(look.palette.ink2).lineLimit(1)
      }
      Spacer(minLength: 8)
      DailyChart(figures: figures, height: 78)
    }
    .widgetURL(WatchLink.trip(figures.tripID, page: .budget).url)
  }
}

// MARK: E2 No trips

/// No trips yet: a nudge to plan one. Opens New trip.
public struct NoTripsView: View {
  @Environment(\.widgetLook) private var look

  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PlaneGlyph(size: 20).foregroundStyle(look.palette.accentText)
        .frame(width: 40, height: 40)
        .background(look.palette.accentSoft, in: Circle())
        .widgetAccentable()
      Spacer(minLength: 0)
      Text("No trips yet").font(.system(size: 20, weight: .bold, design: .rounded))
        .foregroundStyle(look.palette.ink).lineLimit(1).minimumScaleFactor(0.7)
      Text("Plan your first trip").type(13, .bold).foregroundStyle(look.palette.accentText)
        .padding(.top, 2)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .widgetURL(WatchLink.newTrip.url)
  }
}

// MARK: E1 Placeholder

/// Track-coloured shapes where B1's content goes, while the widget loads.
public struct PlaceholderView: View {
  @Environment(\.widgetLook) private var look

  public init() {}

  public var body: some View {
    let track = look.palette.track
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        Circle().fill(track).frame(width: 15, height: 15)
        Capsule().fill(track).frame(width: 46, height: 9)
      }
      Spacer(minLength: 0)
      RoundedRectangle(cornerRadius: 6, style: .continuous).fill(track).frame(width: 84, height: 28)
      Capsule().fill(track).frame(width: 64, height: 9).padding(.top, 8)
      SegmentBar(count: 12, filled: 0, color: track).padding(.top, 10)
      Capsule().fill(track).frame(width: 96, height: 7).padding(.top, 8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityHidden(true)
  }
}
