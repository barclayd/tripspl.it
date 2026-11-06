import SwiftUI
import TripSplitWidgetModel
import WidgetKit

/// Each day's spend as a column against the daily budget's dashed line. Past days are ink with
/// the part over the line in bad, today is accent and days to come are dashed outlines at what's
/// still planned.
struct DailyChart: View {
  var figures: DailyFigures
  var height: CGFloat
  var gap: CGFloat = 8
  var letters = true
  /// The Lock Screen's version: past secondary, today primary, no bad.
  var compact = false
  @Environment(\.widgetLook) private var look

  var body: some View {
    VStack(spacing: 4) {
      bars.frame(height: height)
      if letters {
        HStack(spacing: gap) {
          ForEach(figures.columns) { column in
            Text(column.letter)
              .font(.system(size: 11, weight: column.kind == .today ? .heavy : .semibold))
              .foregroundStyle(column.kind == .today ? look.palette.accentText : look.palette.ink2)
              .frame(maxWidth: .infinity)
          }
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibility)
  }

  private var bars: some View {
    GeometryReader { proxy in
      let line = proxy.size.height * (1 - figures.budgetLine)
      ZStack(alignment: .topLeading) {
        HStack(alignment: .bottom, spacing: gap) {
          ForEach(figures.columns) { column in
            Bar(column: column, figures: figures, compact: compact)
              .frame(maxWidth: .infinity)
          }
        }
        Path { path in
          path.move(to: CGPoint(x: 0, y: line))
          path.addLine(to: CGPoint(x: proxy.size.width, y: line))
        }
        .stroke(
          compact ? look.palette.ink3 : look.palette.ink2,
          style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3]))
      }
    }
  }

  private var accessibility: String {
    let over = figures.columns.filter { $0.kind != .future && $0.spent > figures.budget }.count
    let base = "Daily spend against \(figures.budgetLabel)"
    return over > 0 ? "\(base), \(over) \(over == 1 ? "day" : "days") over" : base
  }
}

private struct Bar: View {
  var column: DailyFigures.Column
  var figures: DailyFigures
  var compact: Bool
  @Environment(\.widgetLook) private var look

  var body: some View {
    GeometryReader { proxy in
      let full = proxy.size.height
      let radius = min(proxy.size.width / 2, 4)
      let shape = UnevenRoundedRectangle(
        topLeadingRadius: radius, bottomLeadingRadius: 1.5, bottomTrailingRadius: 1.5,
        topTrailingRadius: radius, style: .continuous)
      VStack(spacing: 0) {
        Spacer(minLength: 0)
        switch column.kind {
        case .future:
          if column.planned > 0 {
            shape.strokeBorder(
              look.palette.ink3, style: StrokeStyle(lineWidth: 1.25, dash: [2.5, 2]))
              .frame(height: max(full * figures.height(column.planned), 4))
          } else {
            shape.fill(look.palette.track).frame(height: 3)
          }
        case .today:
          shape.fill(look.palette.accent).widgetAccentable()
            .frame(height: max(full * figures.height(column.spent), 3))
        case .past:
          past(full: full, shape: shape)
        }
      }
    }
  }

  @ViewBuilder
  private func past(full: CGFloat, shape: UnevenRoundedRectangle) -> some View {
    let total = max(full * figures.height(column.spent), 3)
    let under = min(total, full * figures.budgetLine)
    let ink = compact ? look.palette.ink2 : look.palette.ink
    if column.spent > figures.budget, !compact {
      VStack(spacing: 0) {
        Rectangle().fill(look.palette.bad).frame(height: total - under)
        Rectangle().fill(ink).frame(height: under)
      }
      .clipShape(shape)
    } else {
      shape.fill(ink).frame(height: total)
    }
  }
}
