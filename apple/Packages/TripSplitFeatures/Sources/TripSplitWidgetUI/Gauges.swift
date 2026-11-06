import SwiftUI
import TripSplitWidgetModel
import WidgetKit

/// The watch's segmented gauge as a bar: `filled` capsules out of `count`, 3pt apart. Filled
/// segments join the accent group in Clear and Tinted.
struct SegmentBar: View {
  var count: Int
  var filled: Int
  var color: Color
  var height: CGFloat = 6
  var gap: CGFloat = 3
  @Environment(\.widgetLook) private var look

  var body: some View {
    HStack(spacing: gap) {
      ForEach(0..<count, id: \.self) { index in
        Capsule().fill(index < filled ? color : look.palette.track)
          .widgetAccentable(index < filled)
      }
    }
    .frame(height: height)
    .animation(.smooth(duration: 0.6), value: filled)
    .accessibilityHidden(true)
  }
}

extension BudgetFigures {
  /// Good while a quarter or more is left, accent below that, bad once over.
  func color(_ palette: WidgetPalette) -> Color {
    switch tone {
    case .good: palette.good
    case .low: palette.accent
    case .over: palette.bad
    }
  }
}

/// One segment per day of the trip, grouped by stop with wider breaks: done, today, still to come.
struct DaySegments: View {
  var groups: [ProgressFigures.Group]
  var height: CGFloat = 6
  @Environment(\.widgetLook) private var look

  /// More than this and segments get too thin to read, so each stop becomes one bar.
  static let most = 14

  var body: some View {
    let days = groups.reduce(0) { $0 + $1.days.count }
    Group {
      if days > Self.most {
        stops
      } else {
        segments
      }
    }
    .frame(height: height)
    .accessibilityHidden(true)
  }

  private var segments: some View {
    HStack(spacing: 0) {
      ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
        if index > 0 { Color.clear.frame(width: 5) }
        ForEach(Array(group.days.enumerated()), id: \.offset) { offset, kind in
          if offset > 0 { Color.clear.frame(width: 3) }
          Capsule().fill(color(kind)).widgetAccentable(kind != .future)
            .frame(maxWidth: .infinity)
        }
      }
    }
  }

  /// Long trips: a bar per stop, sized by its days and filled up to today.
  private var stops: some View {
    GeometryReader { proxy in
      let days = CGFloat(groups.reduce(0) { $0 + $1.days.count })
      let width = proxy.size.width - CGFloat(groups.count - 1) * 5
      HStack(spacing: 5) {
        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
          let share = CGFloat(group.days.count) / days
          let done = CGFloat(group.days.filter { $0 != .future }.count)
            / CGFloat(group.days.count)
          let today = group.days.contains(.today)
          Capsule().fill(look.palette.track)
            .overlay(alignment: .leading) {
              Capsule().fill(today ? look.palette.accent : past)
                .frame(width: max(width * share * done, done > 0 ? height : 0))
                .widgetAccentable()
            }
            .frame(width: width * share)
        }
      }
    }
  }

  private var past: Color {
    look.mode == .vibrant ? look.palette.ink3 : look.palette.ink2
  }

  private func color(_ kind: ProgressFigures.Kind) -> Color {
    switch kind {
    case .past: past
    case .today: look.palette.accent
    case .future: look.palette.track
    }
  }
}

// MARK: Rings

/// What one ring segment shows.
enum RingSegment: Hashable {
  case filled, current, empty
}

/// The Lock Screen's segmented ring, drawn in the design's 50-unit box: radius 21, stroke 3.5 and
/// 2.2 between segments. Closed rings go all the way round from the top; open ones sweep 270°
/// from the bottom left, leaving a gap at the bottom for a label.
struct SegmentRing: View {
  var segments: [RingSegment]
  var open: Bool
  /// Filled segments step back behind the current one, as days gone do behind today.
  var dimsFilled = false
  @Environment(\.widgetLook) private var look

  init(segments: [RingSegment], open: Bool, dimsFilled: Bool = false) {
    self.segments = segments
    self.open = open
    self.dimsFilled = dimsFilled
  }

  init(count: Int, filled: Int, open: Bool) {
    self.init(
      segments: (0..<count).map { $0 < filled ? .filled : .empty }, open: open)
  }

  var body: some View {
    GeometryReader { proxy in
      let scale = min(proxy.size.width, proxy.size.height) / 50
      let style = StrokeStyle(lineWidth: 3.5 * scale, lineCap: .round)
      ZStack {
        ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
          Arc(range: range(index)).stroke(color(segment), style: style)
            .widgetAccentable(segment != .empty)
        }
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityHidden(true)
  }

  private func color(_ segment: RingSegment) -> Color {
    switch segment {
    case .filled: dimsFilled ? look.palette.ink3 : look.palette.ink
    case .current: look.palette.ink
    case .empty: look.palette.track
    }
  }

  /// The segment's span in degrees, clockwise from three o'clock, with room for its round caps.
  private func range(_ index: Int) -> ClosedRange<Double> {
    let radius = 21.0
    let gap = 2.2 / radius * 180 / .pi
    let cap = 1.75 / radius * 180 / .pi
    let sweep = open ? 270.0 : 360.0
    let start = open ? 135.0 : -90.0
    let count = Double(max(segments.count, 1))
    let pitch = open ? (sweep + gap) / count : sweep / count
    let from = start + pitch * Double(index) + (open ? 0 : gap / 2) + cap
    let to = max(from + 0.1, from + pitch - gap - 2 * cap)
    return from...to
  }
}

/// An arc of the ring's circle, in degrees clockwise from three o'clock.
struct Arc: Shape {
  var range: ClosedRange<Double>

  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width, rect.height) / 50
    var path = Path()
    path.addArc(
      center: CGPoint(x: rect.midX, y: rect.midY), radius: 21 * scale,
      startAngle: .degrees(range.lowerBound), endAngle: .degrees(range.upperBound),
      clockwise: false)
    return path
  }
}

extension SegmentRing {
  /// One segment per day, today brightest. Long trips are squeezed into 16 so each stays legible.
  static func days(day: Int, of days: Int) -> SegmentRing {
    let count = min(days, 16)
    let current = days > count ? Int((Double(day - 1) / Double(days) * Double(count))) : day - 1
    return SegmentRing(
      segments: (0..<count).map { $0 < current ? .filled : $0 == current ? .current : .empty },
      open: true, dimsFilled: true)
  }
}
