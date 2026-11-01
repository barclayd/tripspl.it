import MapKit
import SwiftUI

struct GlobeView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var highlighted: String?
  var body: some View {
    @Bindable var model = model
    let trips = model.store.trips.filter {
      model.mapFilter == "All" || model.mapFilter == "Upcoming" && $0.phase == .upcoming
        || model.mapFilter == "Past" && $0.phase == .past
    }
    ZStack(alignment: .bottom) {
      Map(position: $model.mapPosition) {
        ForEach(trips) { trip in
          ForEach(trip.stops) { stop in
            Annotation(
              stop.place, coordinate: .init(latitude: stop.latitude, longitude: stop.longitude)
            ) {
              Button {
                select(trip, stop: stop)
              } label: {
                Text(stop.flag).font(.title).padding(6).background(.regularMaterial, in: Circle())
                  .shadow(color: .black.opacity(0.3), radius: 5, y: 4)
              }.accessibilityLabel("\(stop.place), \(trip.name)")
            }
          }
          if trip.stops.count > 1 {
            MapPolyline(
              coordinates: trip.stops.map { .init(latitude: $0.latitude, longitude: $0.longitude) }
            ).stroke(
              highlighted == trip.id ? Theme.accent : .white.opacity(0.6),
              style: StrokeStyle(
                lineWidth: highlighted == trip.id ? 3 : 1.5,
                dash: trip.phase == .upcoming ? [5, 5] : []))
          }
        }
      }.mapStyle(.imagery(elevation: .realistic)).mapControls {
        MapCompass()
        MapScaleView()
      }.ignoresSafeArea(edges: .bottom)
      VStack(alignment: .leading, spacing: 15) {
        if let trip = trips.first(where: { $0.id == highlighted }) {
          Text(trip.flags).font(.title2)
          Text(trip.name).font(.title2.weight(.heavy))
          HStack {
            Text("\(CivilDate.display(trip.startsOn)) – \(CivilDate.display(trip.endsOn))")
            Spacer()
            Text(Money.format(Ledger(trip).total, trip.homeCurrency, compact: true)).fontWeight(
              .bold)
          }.font(.subheadline)
          if Ledger(trip).unresolved > 0 {
            Label(
              "Known cost · \(Ledger(trip).unresolved) conversion\(Ledger(trip).unresolved == 1 ? "" : "s") pending",
              systemImage: "exclamationmark.circle"
            ).font(.caption).foregroundStyle(Theme.bad)
          }
          Button("Open trip", systemImage: "chevron.right") { model.open(trip) }.buttonStyle(
            .borderedProminent)
        } else {
          HStack {
            stat("Countries", "\(Set(trips.flatMap { $0.stops.map(\.countryCode) }).count)")
            Spacer()
            stat("Trips", "\(trips.count)")
          }
        }
        ScrollView(.horizontal, showsIndicators: false) {
          HStack {
            ForEach(trips) { trip in
              Button {
                if let stop = trip.stops.first { select(trip, stop: stop) }
              } label: {
                Text("\(trip.stops.first?.flag ?? "🌍") \(trip.name)").font(.caption.weight(.bold))
                  .padding(10).background(
                    highlighted == trip.id ? Theme.accent.opacity(0.3) : .white.opacity(0.1),
                    in: Capsule())
              }
            }
          }
        }
      }.padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26)).padding(20)
    }.navigationTitle("Your world")
      .toolbarColorScheme(.dark, for: .navigationBar)
      .toolbarBackground(Color.black.opacity(0.65), for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("New trip", systemImage: "plus") { model.showOnboarding = true }
        }
        ToolbarItem {
          Picker("Filter trips", selection: $model.mapFilter) {
            Text("All").tag("All")
            Text("Upcoming").tag("Upcoming")
            Text("Past").tag("Past")
          }
        }
      }
  }
  private func stat(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(value).font(.title.weight(.heavy))
      Text(title).font(.caption).foregroundStyle(.secondary)
    }
  }
  private func select(_ trip: TripSnapshot, stop: Stop) {
    highlighted = trip.id
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.1)) {
      model.mapPosition = .camera(
        MapCamera(
          centerCoordinate: .init(latitude: stop.latitude, longitude: stop.longitude),
          distance: 1_500_000))
    }
  }
}
