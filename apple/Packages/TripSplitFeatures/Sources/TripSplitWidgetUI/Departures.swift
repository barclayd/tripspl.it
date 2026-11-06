import SwiftUI
import TripSplitDesignSystem
import TripSplitWatchModel
import TripSplitWidgetModel
import WidgetKit

/// The departures board's own colours: always dark, whatever the appearance.
public enum DeparturesBoard {
  public static let background = Color(hex: 0x121316)
  static let flapTop = Color(hex: 0x27282C)
  static let flapBottom = Color(hex: 0x1F2023)
  static let text = Color(hex: 0xF3EFE6)
  static let amber = Color(hex: 0xF7C948)
  static let green = Color(hex: 0x5BE49B)
  static let dim = Color(hex: 0xF3EFE6, opacity: 0.45)
  static let rule = Color.white.opacity(0.07)

  /// Cells per column: destination, date and status.
  static let columns = [10, 6, 7]
}

/// Medium Departures: the trip under way and the next departures as split-flap rows. Only cells
/// whose letter changed turn over. Tapping a row opens that trip, elsewhere opens Trips.
public struct DeparturesMediumView: View {
  var figures: DeparturesFigures
  @Environment(\.widgetLook) private var look

  public init(figures: DeparturesFigures) {
    self.figures = figures
  }

  public var body: some View {
    VStack(spacing: 0) {
      header.padding(.bottom, 4)
      ForEach(figures.rows) { row in
        Link(destination: WatchLink.trip(row.tripID).url) {
          FlapRow(
            id: row.id, flag: AnyView(Text(row.flag).font(.system(size: 15))),
            cells: [row.destination, row.date, row.status],
            colors: [DeparturesBoard.text, DeparturesBoard.text, statusColor(row.kind)])
        }
        .accessibilityLabel(row.accessibilityLabel)
      }
      if figures.addTrip {
        Link(destination: WatchLink.newTrip.url) {
          FlapRow(
            id: "add",
            flag: AnyView(
              Image(systemName: "plus").font(.system(size: 11, weight: .heavy))
                .foregroundStyle(DeparturesBoard.dim)),
            cells: ["ADD A TRIP", "", ""],
            colors: [DeparturesBoard.dim, DeparturesBoard.dim, DeparturesBoard.dim])
        }
        .accessibilityLabel("Add a trip")
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 12).padding(.horizontal, 14)
    .environment(\.colorScheme, .dark)
    .widgetURL(WatchLink.trips.url)
  }

  private var header: some View {
    HStack(spacing: 6) {
      PlaneGlyph(size: 13, heading: 45).foregroundStyle(DeparturesBoard.amber)
      Text("DEPARTURES").font(.system(size: 11, weight: .heavy)).tracking(1.76)
        .foregroundStyle(DeparturesBoard.amber)
      Spacer(minLength: 4)
      Text(.currentDate, format: Date.FormatStyle(date: .omitted, time: .shortened))
        .font(.system(size: 12, weight: .bold, design: .monospaced))
        .foregroundStyle(DeparturesBoard.amber)
        .accessibilityHidden(true)
    }
    .widgetAccentable()
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }

  private func statusColor(_ kind: DeparturesFigures.Status) -> Color {
    kind == .onTrip ? DeparturesBoard.green : DeparturesBoard.amber
  }
}

/// One row of the board: a flag and three columns of flaps, 1pt apart within a column and 8pt
/// between columns, under a hairline rule.
private struct FlapRow: View {
  var id: String
  var flag: AnyView
  var cells: [String]
  var colors: [Color]

  var body: some View {
    VStack(spacing: 0) {
      Rectangle().fill(DeparturesBoard.rule).frame(height: 1)
      GeometryReader { proxy in
        let counts = DeparturesBoard.columns
        let total = counts.reduce(0, +)
        let gaps = CGFloat(counts.reduce(0) { $0 + $1 - 1 })
        let width = (proxy.size.width - 28 - CGFloat(counts.count - 1) * 8 - gaps) / CGFloat(total)
        HStack(spacing: 0) {
          flag.frame(width: 20, alignment: .leading)
          Spacer(minLength: 8)
          HStack(spacing: 8) {
            ForEach(Array(counts.enumerated()), id: \.offset) { column, count in
              let text = Array(cells[column].prefix(count))
              HStack(spacing: 1) {
                ForEach(0..<count, id: \.self) { index in
                  let character = index < text.count ? String(text[index]) : " "
                  Flap(character: character, color: colors[column], width: width)
                }
              }
            }
          }
        }
        .frame(maxHeight: .infinity)
      }
      .frame(height: 29)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
  }
}

/// One split-flap cell: a lighter top half over a darker bottom half, the letter across both.
private struct Flap: View {
  var character: String
  var color: Color
  var width: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      VStack(spacing: 0.5) {
        DeparturesBoard.flapTop
        DeparturesBoard.flapBottom
      }
      .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
      Text(character).font(.system(size: 12, weight: .bold, design: .monospaced))
        .foregroundStyle(color).minimumScaleFactor(0.6)
        .id(character)
        .transition(FlapTurn(enabled: !reduceMotion))
    }
    .frame(width: max(width, 4), height: 17)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: character)
  }
}

/// A letter turning over on its horizontal axis, as a flap does. Reduce Motion shows the new
/// letter in place.
private struct FlapTurn: Transition {
  var enabled: Bool

  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .rotation3DEffect(
        .degrees(enabled ? phase.value * -90 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.4
      )
      .opacity(phase.isIdentity || !enabled ? 1 : 0)
  }
}
