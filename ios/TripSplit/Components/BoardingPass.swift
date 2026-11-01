import SwiftUI

struct BoardingPass: View {
  var trip: TripSnapshot
  var leg: TravelLeg
  var index: Int
  var cleared = false
  private var origin: Stop? { trip.stops.first { $0.id == leg.fromStopId } }
  private var destination: Stop? { trip.stops.first { $0.id == leg.toStopId } }
  var body: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("LEG \(index + 1) OF \(trip.legs.count)")
          Spacer()
          Text("TRIPSPLIT AIR").foregroundStyle(Theme.accent)
        }.font(.system(size: 9, weight: .black)).tracking(1)
        HStack(alignment: .center) {
          airport(origin?.code ?? "HOME", origin?.place ?? "Home")
          Spacer(minLength: 8)
          Image(systemName: "airplane").font(.title3).foregroundStyle(Theme.accent)
          Spacer(minLength: 8)
          airport(destination?.code ?? "HOME", destination?.place ?? "Home")
        }
        HStack(spacing: 20) {
          field("DATE", CivilDate.display(leg.date).uppercased())
          field("PAX", "\(trip.activeTravellers.count)")
          field("TRAVEL", travelAmount)
        }
      }.padding(17).frame(maxWidth: .infinity)
      ZStack {
        Theme.accent
        VStack(spacing: 8) {
          Text(destination?.flag ?? "🏡").font(.title)
          Text(destination.map { "\($0.nights) NIGHTS" } ?? "WELCOME\nHOME").font(
            .system(size: 9, weight: .black)
          ).multilineTextAlignment(.center).tracking(1)
          barcode
        }.foregroundStyle(.white).padding(8)
      }.frame(width: 76).overlay(alignment: .leading) {
        Path { p in
          p.move(to: .zero)
          p.addLine(to: .init(x: 0, y: 160))
        }.stroke(.white.opacity(0.65), style: .init(lineWidth: 2, dash: [3, 3]))
      }
    }.frame(minHeight: 150, maxHeight: 166).background(Theme.surface).clipShape(
      RoundedRectangle(cornerRadius: 20)
    )
    .overlay {
      if cleared {
        Text("CLEARED").font(.system(size: 24, weight: .black, design: .monospaced)).padding(8)
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.good, lineWidth: 3))
          .foregroundStyle(Theme.good).rotationEffect(.degrees(-12))
      }
    }
    .shadow(color: .black.opacity(0.10), radius: 14, y: 8)
    .accessibilityElement(children: .combine)
  }
  private var travelAmount: String {
    let list = trip.expenses.filter { $0.attachment == Attachment(kind: .leg, id: leg.id) }
    return list.isEmpty
      ? "ADD" : Money.format(Ledger(trip, expenses: list).total, trip.homeCurrency, compact: true)
  }
  private func airport(_ code: String, _ city: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(code).font(.system(size: 29, weight: .black, design: .default)).tracking(-1)
      Text(city).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
    }
  }
  private func field(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label).font(.system(size: 8, weight: .heavy)).foregroundStyle(Theme.secondary).tracking(
        1)
      Text(value).font(.system(size: 11, weight: .heavy)).lineLimit(1)
    }
  }
  private var barcode: some View {
    HStack(spacing: 2) {
      ForEach(0..<15) { n in Rectangle().frame(width: (n + index) % 3 == 0 ? 3 : 1) }
    }.frame(height: 20).opacity(0.8).accessibilityHidden(true)
  }
}
struct BoardingPassStack: View {
  var trip: TripSnapshot
  var cleared = false
  var open: ((TravelLeg) -> Void)?
  @State private var expanded = false
  @State private var offset = 0
  @State private var drag: CGSize = .zero
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var ordered: [TravelLeg] {
    guard !trip.legs.isEmpty else { return [] }
    return Array(trip.legs[offset...] + trip.legs[..<offset])
  }
  var body: some View {
    VStack(spacing: 14) {
      ZStack(alignment: .top) {
        ForEach(Array(ordered.enumerated().reversed()), id: \.element.id) { i, leg in
          BoardingPass(
            trip: trip, leg: leg, index: trip.legs.firstIndex(where: { $0.id == leg.id }) ?? 0,
            cleared: cleared
          )
          .scaleEffect(expanded ? 1 : 1 - CGFloat(min(i, 2)) * 0.045, anchor: .top)
          .offset(
            x: i == 0 ? drag.width : 0,
            y: expanded ? CGFloat(i) * 176 : CGFloat(min(i, 2)) * 10 + (i == 0 ? drag.height : 0)
          )
          .opacity(expanded || i < 3 ? 1 : 0).allowsHitTesting(expanded || i == 0)
          .onTapGesture {
            if expanded, let open { open(leg) } else { animate { expanded.toggle() } }
          }
          .accessibilityAddTraits(.isButton).accessibilityAction(
            named: expanded ? "Open travel day" : "Expand boarding passes"
          ) { if expanded { open?(leg) } else { expanded = true } }
        }
      }.frame(height: expanded ? CGFloat(trip.legs.count) * 176 - 10 : 186)
        .gesture(
          DragGesture(minimumDistance: 12).onChanged { value in
            if !expanded {
              drag = .init(
                width: value.translation.width,
                height: min(value.translation.height, value.translation.height * 0.2))
            }
          }.onEnded { value in
            if !expanded && (value.translation.height < -45 || abs(value.translation.width) > 60),
              !trip.legs.isEmpty
            {
              animate {
                offset = (offset + 1) % trip.legs.count
                drag = .zero
              }
            } else {
              animate { drag = .zero }
            }
          })
      Button {
        animate { expanded.toggle() }
      } label: {
        Label(
          expanded ? "Stack them" : "\(trip.legs.count) passes · tap to explore",
          systemImage: expanded ? "rectangle.stack" : "hand.tap"
        ).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
      }
    }
  }
  private func animate(_ action: () -> Void) {
    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), action)
  }
}
