import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain

/// A Solari board listing the trip under way and every upcoming departure.
struct DeparturesBoard: View {
  var trips: [TripSnapshot]
  @Environment(AppModel.self) private var model
  /// The page's scheme, outside the board's own dark one.
  @Environment(\.colorScheme) private var colorScheme
  @State private var narrow = false

  /// The trip under way first, then upcoming trips by departure date.
  private var rows: [TripSnapshot] {
    trips.filter { $0.phase == .now }.prefix(1)
      + trips.filter { $0.phase == .upcoming }.sorted { $0.startsOn < $1.startsOn }
  }

  var body: some View {
    let rows = rows
    // Cells shrink on 375pt screens so the four columns still fit.
    let cell = narrow ? Cell(width: 10, height: 17, font: 11.5) : Cell(width: 11, height: 18, font: 12.5)
    VStack(alignment: .leading, spacing: 10) {
      Kicker(title: "Departures")
      VStack(alignment: .leading, spacing: 0) {
        header
        columns(cell)
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, trip in
          Button {
            model.open(trip)
          } label: {
            row(trip, index: index, cell: cell)
          }
          .buttonStyle(BoardRowStyle())
          .accessibilityLabel(label(trip))
          .tripActions(trip, colorScheme: colorScheme)
        }
        Button {
          model.showOnboarding = true
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "plus").font(.system(size: 12, weight: .heavy))
              .foregroundStyle(Theme.flapInk.opacity(0.5)).frame(width: 22)
            flap(
              "ADD A TRIP", count: 10, cell: cell, color: Theme.flapInk.opacity(0.45),
              delay: 0.2 + Double(rows.count) * 0.24)
          }
          .padding(.horizontal, 2).padding(.top, 7).padding(.bottom, 6)
          .frame(maxWidth: .infinity, alignment: .leading)
          .overlay(alignment: .top) { divider }
          .contentShape(Rectangle())
        }
        .buttonStyle(BoardRowStyle())
        .accessibilityLabel("Add a trip")
      }
      .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 8)
      .background(Theme.board, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
      // A row swiped open for its actions slides under the board's edge rather than off it.
      .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
          .strokeBorder(.white.opacity(0.05))
      }
      .shadow(color: .black.opacity(0.35), radius: 14, y: 12)
      .environment(\.colorScheme, .dark)
      .onGeometryChange(for: Bool.self) { $0.size.width < 340 } action: { narrow = $0 }
    }
  }

  private var header: some View {
    HStack {
      Label {
        Text("DEPARTURES")
      } icon: {
        Image(systemName: "airplane").rotationEffect(.degrees(-45))
      }
      .labelStyle(BoardLabelStyle())
      .typeface(12, .black, tracking: 0.16, relativeTo: .caption, maximum: 1.2)
      Spacer()
      TimelineView(.everyMinute) { context in
        Text(context.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
          .typeface(13, .bold, design: .monospaced, tracking: 0.06, relativeTo: .caption, maximum: 1.2)
      }
      .accessibilityHidden(true)
    }
    .foregroundStyle(Theme.amber)
    .padding(.horizontal, 2).padding(.bottom, 10)
  }

  private func columns(_ cell: Cell) -> some View {
    HStack(spacing: 8) {
      Color.clear.frame(width: 22, height: 1)
      Text("DESTINATION").frame(width: cell.span(10), alignment: .leading)
      Text("DATE").frame(width: cell.span(6), alignment: .leading)
      Text("STATUS").frame(width: cell.span(7), alignment: .leading)
    }
    .typeface(9, .heavy, tracking: 0.14, relativeTo: .caption2, maximum: 1)
    .foregroundStyle(Theme.flapInk.opacity(0.45))
    .lineLimit(1)
    .padding(.horizontal, 2).padding(.bottom, 6)
    .accessibilityHidden(true)
  }

  private func row(_ trip: TripSnapshot, index: Int, cell: Cell) -> some View {
    let lag = Double(index) * 0.24
    let live = trip.phase == .now
    return HStack(spacing: 8) {
      Text(trip.stops.first?.flag ?? "🌍").font(.system(size: 17)).frame(width: 22)
      flap(destination(trip), count: 10, cell: cell, delay: 0.15 + lag)
      flap(
        CivilDate.display(trip.startsOn).uppercased(), count: 6, cell: cell, delay: 0.26 + lag)
      flap(
        live ? "ON TRIP" : status(trip), count: 7, cell: cell,
        color: live ? Theme.signal : Theme.amber, delay: 0.38 + lag)
    }
    .padding(.horizontal, 2).padding(.vertical, 7)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .top) { divider }
    .contentShape(Rectangle())
  }

  private var divider: some View {
    Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
  }

  private func flap(
    _ value: String, count: Int, cell: Cell, color: Color = Theme.flapInk, delay: Double
  ) -> some View {
    FlapText(
      value, count: count, delay: delay, cellWidth: cell.width, cellHeight: cell.height,
      fontSize: cell.font, color: color)
  }

  /// "LISBON", or the first stop and a count of the rest: "LISBON +2".
  private func destination(_ trip: TripSnapshot) -> String {
    let first = (trip.stops.first?.place ?? trip.name).uppercased()
    let others = Set(trip.stops.map(\.place)).count - 1
    return others > 0 ? "\(first.prefix(7)) +\(others)" : String(first.prefix(10))
  }

  /// Counts down on the phone's calendar: you leave from where you are now.
  private func daysToGo(_ trip: TripSnapshot) -> Int {
    CivilDate.days(from: CivilDate.today(timeZone: TimeZone.current.identifier), to: trip.startsOn)
  }

  private func status(_ trip: TripSnapshot) -> String {
    let days = daysToGo(trip)
    return days <= 0 ? "TODAY" : "IN \(min(days, 999))D"
  }

  private func label(_ trip: TripSnapshot) -> String {
    let when =
      trip.phase == .now
      ? "on trip now"
      : {
        let days = daysToGo(trip)
        return days <= 0 ? "departs today" : "departs in \(days) \(days == 1 ? "day" : "days")"
      }()
    return "\(trip.name), \(CivilDate.display(trip.startsOn, format: "d MMMM")), \(when)"
  }

  private struct Cell {
    var width: CGFloat
    var height: CGFloat
    var font: CGFloat
    /// The width `count` cells take with their 1pt gaps.
    func span(_ count: Int) -> CGFloat { CGFloat(count) * width + CGFloat(count - 1) }
  }
}

private struct BoardRowStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
      .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
  }
}

private struct BoardLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 8) {
      configuration.icon.font(.system(size: 14, weight: .bold))
      configuration.title
    }
  }
}
