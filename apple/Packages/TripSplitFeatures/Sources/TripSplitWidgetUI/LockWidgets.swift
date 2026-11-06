import SwiftUI
import TripSplitDesignSystem
import TripSplitWatchModel
import TripSplitWidgetModel
import WidgetKit

// MARK: Circular

/// What the Today circular shows, picked when the widget's configured.
public enum BudgetRingStyle: String, CaseIterable, Hashable, Sendable {
  /// Closed 12-segment ring of what's left, the country code in the middle.
  case code
  /// Closed ring with the share left as a percentage.
  case percent
  /// Open 10-segment ring with the amount left and the code in the gap.
  case amount
  /// Open ring from nothing to the trip budget, filling as you spend.
  case totalSpent
}

/// The circular disc, drawn in the design's 50-unit box so every size scales with the frame.
struct CircularFace<Content: View>: View {
  @ViewBuilder var content: (_ unit: CGFloat) -> Content
  @Environment(\.widgetLookOverride) private var override

  var body: some View {
    ZStack {
      if override != nil {
        // The in-app gallery has no Lock Screen material behind it.
        Circle().fill(Color(hex: 0x3A3A3C))
      } else {
        AccessoryWidgetBackground()
      }
      GeometryReader { proxy in
        let unit = min(proxy.size.width, proxy.size.height) / 50
        content(unit).frame(width: proxy.size.width, height: proxy.size.height)
      }
    }
  }
}

/// A short label in an open ring's gap at the bottom, or at either end of it.
struct GapLabel: View {
  var text: String
  var unit: CGFloat
  var x: CGFloat = 0
  @Environment(\.widgetLook) private var look

  var body: some View {
    Text(text).font(.system(size: 7.7 * unit, weight: .bold, design: .rounded))
      .foregroundStyle(look.palette.ink2).lineLimit(1).fixedSize()
      .offset(x: x * unit, y: 19 * unit)
  }
}

/// Lock Screen Today circular in any of its four styles. Opens Budget.
public struct BudgetCircularView: View {
  var figures: TodayFigures
  var style: BudgetRingStyle
  @Environment(\.widgetLook) private var look

  public init(figures: TodayFigures, style: BudgetRingStyle) {
    self.figures = figures
    self.style = style
  }

  public var body: some View {
    CircularFace { unit in
      ZStack {
        ring
        centre(unit)
        switch style {
        case .amount:
          GapLabel(text: figures.place.code, unit: unit)
        case .totalSpent:
          GapLabel(text: "0", unit: unit, x: -9.7)
          GapLabel(text: figures.trip.compactBudget, unit: unit, x: 9.7)
        case .code, .percent:
          EmptyView()
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibility)
    .widgetURL(WatchLink.trip(figures.tripID, page: .budget).url)
  }

  private var budget: BudgetFigures { style == .totalSpent ? figures.trip : figures.budget }

  @ViewBuilder private var ring: some View {
    switch style {
    case .code, .percent:
      SegmentRing(count: 12, filled: budget.filled(12), open: false)
    case .amount:
      SegmentRing(count: 10, filled: budget.filled(10), open: true)
    case .totalSpent:
      SegmentRing(
        count: 10, filled: Int((min(budget.spentFraction, 1) * 10).rounded()), open: true)
    }
  }

  @ViewBuilder private func centre(_ unit: CGFloat) -> some View {
    let ink = look.palette.ink
    switch style {
    case .code:
      // Over budget the ring is full, so the word says which way.
      Text(budget.isOver ? "OVER" : figures.place.code)
        .font(.system(size: (budget.isOver ? 9 : 12) * unit, weight: .heavy, design: .rounded))
        .foregroundStyle(ink)
    case .percent:
      Text(budget.percent).font(.system(size: 14.5 * unit, weight: .bold, design: .rounded))
        .foregroundStyle(ink).minimumScaleFactor(0.6).lineLimit(1).frame(width: 34 * unit)
    case .amount:
      Text(budget.compactLeft).font(.system(size: 13.5 * unit, weight: .bold, design: .rounded))
        .foregroundStyle(ink).minimumScaleFactor(0.6).lineLimit(1).frame(width: 34 * unit)
        .amount(look)
    case .totalSpent:
      Text(budget.compactSpent).font(.system(size: 13.5 * unit, weight: .bold, design: .rounded))
        .foregroundStyle(ink).minimumScaleFactor(0.6).lineLimit(1).frame(width: 34 * unit)
        .amount(look)
    }
  }

  private var accessibility: String {
    switch style {
    case .code, .percent, .amount:
      return "\(figures.line), \(figures.budget.percent)"
    case .totalSpent:
      return "\(figures.trip.compactSpent) spent of \(figures.trip.compactBudget)"
    }
  }
}

/// Lock Screen Where you are: one segment per day, today brightest. Opens Today.
public struct WhereCircularView: View {
  var figures: ProgressFigures
  @Environment(\.widgetLook) private var look

  public init(figures: ProgressFigures) {
    self.figures = figures
  }

  public var body: some View {
    CircularFace { unit in
      ZStack {
        SegmentRing.days(day: figures.day, of: figures.days)
        Text(figures.place.code).font(.system(size: 12 * unit, weight: .heavy, design: .rounded))
          .foregroundStyle(look.palette.ink)
        GapLabel(text: figures.fraction, unit: unit)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(figures.place.name), \(figures.dayOfDays)")
    .widgetURL(WatchLink.trip(figures.tripID, page: .today).url)
  }
}

/// Lock Screen Quick convert: the ×10 amount over what it comes to. Opens Quick convert.
public struct ConvertCircularView: View {
  var figures: ConvertFigures
  @Environment(\.widgetLook) private var look

  public init(figures: ConvertFigures) {
    self.figures = figures
  }

  public var body: some View {
    CircularFace { unit in
      VStack(spacing: 0) {
        Text(figures.sample.from).font(.system(size: 9.5 * unit, weight: .semibold, design: .rounded))
          .foregroundStyle(look.palette.ink2)
        Text(figures.sample.to).font(.system(size: 14 * unit, weight: .bold, design: .rounded))
          .foregroundStyle(look.palette.ink)
      }
      .lineLimit(1).minimumScaleFactor(0.6).frame(width: 40 * unit)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(figures.sample.from) is \(figures.sample.to)")
    .widgetURL(WatchLink.convert.url)
  }
}

/// Lock Screen Countdown: days to go over an open ring that fills as departure nears. Opens the
/// trip.
public struct CountdownCircularView: View {
  var figures: CountdownFigures
  @Environment(\.widgetLook) private var look

  public init(figures: CountdownFigures) {
    self.figures = figures
  }

  public var body: some View {
    CircularFace { unit in
      ZStack {
        SegmentRing(count: 10, filled: figures.filled(10), open: true)
        VStack(spacing: -1 * unit) {
          if figures.isDepartureDay {
            Text("GO").font(.system(size: 14 * unit, weight: .bold, design: .rounded))
              .foregroundStyle(look.palette.ink)
          } else {
            Text("\(figures.days)").font(.system(size: 14 * unit, weight: .bold, design: .rounded))
              .foregroundStyle(look.palette.ink).minimumScaleFactor(0.6)
            Text(figures.unit.uppercased())
              .font(.system(size: 6.5 * unit, weight: .heavy, design: .rounded))
              .foregroundStyle(look.palette.ink2)
          }
        }
        .lineLimit(1).frame(width: 32 * unit)
        GapLabel(text: figures.place.code, unit: unit)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(figures.line)
    .widgetURL(WatchLink.trip(figures.tripID).url)
  }
}

/// Lock Screen Owed to you: your net balance. Opens Who owes who.
public struct OwedCircularView: View {
  var figures: BalanceFigures
  @Environment(\.widgetLook) private var look

  public init(figures: BalanceFigures) {
    self.figures = figures
  }

  public var body: some View {
    CircularFace { unit in
      VStack(spacing: 0) {
        Text(figures.label).font(.system(size: 6.5 * unit, weight: .heavy, design: .rounded))
          .foregroundStyle(look.palette.ink2)
        Text(figures.amount).font(.system(size: 14.5 * unit, weight: .bold, design: .rounded))
          .foregroundStyle(look.palette.ink).amount(look)
      }
      .lineLimit(1).minimumScaleFactor(0.6).frame(width: 40 * unit)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      figures.balance > 0
        ? "You're owed \(figures.amount)"
        : figures.balance < 0 ? "You owe \(figures.amount)" : "All square")
    .widgetURL(WatchLink.trip(figures.tripID, page: .balances).url)
  }
}

/// The plane on the disc: the gallery preview, first install and no trips. Opens Trips, or New
/// trip when there aren't any.
public struct PlaceholderCircularView: View {
  var hasTrips: Bool
  @Environment(\.widgetLook) private var look

  public init(hasTrips: Bool = true) {
    self.hasTrips = hasTrips
  }

  public var body: some View {
    CircularFace { unit in
      PlaneGlyph(size: 22 * unit).foregroundStyle(look.palette.ink)
    }
    .accessibilityLabel(hasTrips ? "TripSplit" : "No trips yet")
    .widgetURL(hasTrips ? WatchLink.trips.url : WatchLink.newTrip.url)
  }
}

// MARK: Rectangular

/// Lock Screen Today: where you are, what's left and the gauge. Opens Trip › Today.
public struct TodayRectangularView: View {
  var figures: TodayFigures
  @Environment(\.widgetLook) private var look

  public init(figures: TodayFigures) {
    self.figures = figures
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 5) {
        if !figures.place.code.isEmpty { CodeBadge(code: figures.place.code) }
        Text(figures.title).type(13).foregroundStyle(look.palette.ink2).lineLimit(1)
      }
      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text(figures.budget.hero).amount(look)
        Text(figures.label)
      }
      .figure(19).foregroundStyle(look.palette.ink)
      SegmentBar(
        count: 12, filled: figures.budget.filled(12), color: figures.budget.color(look.palette),
        height: 5
      )
      .padding(.top, 2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .widgetURL(WatchLink.trip(figures.tripID, page: .today).url)
  }
}

/// Lock Screen Daily spend: a mini chart against the daily budget. Opens Budget.
public struct DailyRectangularView: View {
  var figures: DailyFigures
  @Environment(\.widgetLook) private var look

  public init(figures: DailyFigures) {
    self.figures = figures
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("Daily spend")
        Spacer(minLength: 4)
        Text(figures.budgetAmount).amount(look)
      }
      .type(13).foregroundStyle(look.palette.ink2).lineLimit(1)
      DailyChart(figures: figures, height: 36, gap: 4, letters: false, compact: true)
    }
    .widgetURL(WatchLink.trip(figures.tripID, page: .budget).url)
  }
}

/// Lock Screen Who owes who: your balance, then the biggest other one. Opens Who owes who.
public struct BalanceRectangularView: View {
  var figures: BalanceFigures
  @Environment(\.widgetLook) private var look

  public init(figures: BalanceFigures) {
    self.figures = figures
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Who owes who").type(13).foregroundStyle(look.palette.ink2)
      if let row = figures.yours ?? figures.others {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(row.text)
          Text(row.amount).amount(look)
        }
        .figure(17).foregroundStyle(look.palette.ink)
        if let other = figures.rows.first(where: { $0 != row }) {
          Text(other.line).type(13).foregroundStyle(look.palette.ink2).lineLimit(1).amount(look)
        }
      } else {
        Text(figures.pending ? "Converting" : "All square").figure(17)
          .foregroundStyle(look.palette.ink)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .widgetURL(WatchLink.trip(figures.tripID, page: .balances).url)
  }
}

/// Lock Screen no trips: the plane and a nudge. Opens New trip.
public struct NoTripsRectangularView: View {
  @Environment(\.widgetLook) private var look

  public init() {}

  public var body: some View {
    HStack(spacing: 8) {
      PlaneGlyph(size: 22).foregroundStyle(look.palette.ink)
      VStack(alignment: .leading, spacing: 0) {
        Text("No trips yet").figure(17).foregroundStyle(look.palette.ink)
        Text("Plan your first trip").type(13).foregroundStyle(look.palette.ink2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .widgetURL(WatchLink.newTrip.url)
  }
}

// MARK: Inline

/// One line beside the date: a symbol and a short phrase.
public struct InlineView: View {
  var symbol: String
  var text: String
  var url: URL
  /// Whether the line is a personal amount, hidden while locked when the setting is on. A rate
  /// or a countdown isn't.
  var isAmount: Bool
  @Environment(\.widgetLook) private var look

  public init(symbol: String, text: String, url: URL, isAmount: Bool = false) {
    self.symbol = symbol
    self.text = text
    self.url = url
    self.isAmount = isAmount
  }

  public var body: some View {
    Label(text, systemImage: symbol).privacySensitive(isAmount && look.hidesAmounts).widgetURL(url)
  }
}

extension InlineView {
  /// "£241 left today".
  public static func today(_ figures: TodayFigures) -> InlineView {
    InlineView(
      symbol: "gauge.with.dots.needle.67percent", text: figures.line,
      url: WatchLink.trip(figures.tripID, page: .today).url, isAmount: true)
  }

  /// "€10 = £8.62".
  public static func convert(_ figures: ConvertFigures) -> InlineView {
    InlineView(
      symbol: "arrow.left.arrow.right", text: "\(figures.sample.from) = \(figures.sample.to)",
      url: WatchLink.convert.url)
  }

  /// "Zermatt in 49 days".
  public static func countdown(_ figures: CountdownFigures) -> InlineView {
    InlineView(symbol: "airplane", text: figures.line, url: WatchLink.trip(figures.tripID).url)
  }

  /// "Plan a trip", when there are none.
  public static var noTrips: InlineView {
    InlineView(symbol: "airplane", text: "Plan a trip", url: WatchLink.newTrip.url)
  }
}
