import MapKit
import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitPersistence

/// Every trip on one globe: route arcs from home, a flag pin per stop and a glass card to fly
/// between trips.
public struct GlobeView: View {
  public init() {
  }
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var position = MapCameraPosition.camera(
    Self.globe(at: GeoPoint(latitude: 30, longitude: 0)))
  /// Where the globe last settled, so the spin and the return from a trip carry on from there.
  @State private var settled: MapCamera?
  @State private var touchedAt = Date.distantPast

  static let space = Color(hex: 0x04060B)
  /// As far out as MapKit's globe goes; it clamps anything further.
  private static let globeDistance: Double = 32_000_000

  public var body: some View {
    let trips = model.store.trips.filter(model.globeFilter.includes)
    let selected = trips.first { $0.id == model.globeTripID }
    let home = Destination.home(region: Locale.current.region?.identifier)
    ZStack(alignment: .top) {
      Self.space.ignoresSafeArea()
      map(trips: trips, selected: selected, home: home)
      header
      VStack {
        Spacer()
        GlobeCard(trips: trips, selected: selected)
          .padding(.horizontal, 12).padding(.bottom, 8)
      }
    }
    .environment(\.colorScheme, .dark)
    .toolbar(.hidden, for: .navigationBar)
    .sensoryFeedback(.selection, trigger: model.globeTripID)
    .onAppear {
      // Flies rather than jumps: MapKit skips annotations on a camera that never moves after mount.
      if let selected {
        fly(to: selected, animated: true)
      } else if let home {
        position = .camera(Self.globe(at: GeoPoint(latitude: 30, longitude: home.longitude)))
      }
    }
    .onChange(of: model.globeTripID) {
      if let selected { fly(to: selected, animated: true) } else { zoomOut() }
    }
    // A slow spin while nothing is selected, paused for a few seconds after each touch.
    .task(id: selected == nil && !reduceMotion) {
      guard selected == nil, !reduceMotion else { return }
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled, model.globeTripID == nil,
          Date.now.timeIntervalSince(touchedAt) > 5
        else { continue }
        var camera =
          settled ?? position.camera
          ?? Self.globe(at: GeoPoint(latitude: 30, longitude: home?.longitude ?? 0))
        camera.centerCoordinate.longitude = Self.wrap(camera.centerCoordinate.longitude + 5)
        settled = camera
        withAnimation(.linear(duration: 2)) { position = .camera(camera) }
      }
    }
  }

  /// Where a trip's arc starts and ends: the origin picked for it, else the device's home city.
  static func origin(of trip: TripSnapshot, home: Destination?)
    -> (name: String, point: GeoPoint)?
  {
    if let origin = trip.origin { return (origin.place, origin.point) }
    return home.map { ("Home", $0.point) }
  }

  /// One home dot per distinct starting point across the trips on the globe.
  static func origins(of trips: [TripSnapshot], home: Destination?)
    -> [(name: String, point: GeoPoint)]
  {
    var seen = Set<GeoPoint>()
    return trips.compactMap { origin(of: $0, home: home) }
      .filter { seen.insert($0.point).inserted }
  }

  private func map(trips: [TripSnapshot], selected: TripSnapshot?, home: Destination?)
    -> some View
  {
    // The selected trip draws last so its arc and pins sit on top.
    let ordered = trips.filter { $0.id != selected?.id } + (selected.map { [$0] } ?? [])
    return Map(position: $position) {
      ForEach(ordered) { trip in
        let ends = Self.origin(of: trip, home: home).map { [$0.point] } ?? []
        let route = ends + trip.stops.map(\.point) + ends
        if route.count > 1 {
          MapPolyline(coordinates: route.map(\.location), contourStyle: .geodesic)
            .stroke(
              arcColour(trip, selected: selected),
              style: StrokeStyle(
                lineWidth: trip.id == selected?.id ? 3 : 1.4, lineCap: .round,
                dash: trip.phase == .upcoming ? [1, 5] : []))
        }
      }
      ForEach(Self.origins(of: ordered, home: home), id: \.point) { origin in
        Annotation(origin.name, coordinate: origin.point.location, anchor: .center) {
          Circle().fill(.white).frame(width: 10, height: 10)
            .overlay(Circle().stroke(Color(hex: 0x24548F), lineWidth: 2.5))
            .accessibilityHidden(true)
        }
        .annotationTitles(.hidden)
      }
      ForEach(ordered) { trip in
        ForEach(Self.uniqueStops(trip)) { stop in
          Annotation(stop.place, coordinate: stop.point.location, anchor: .center) {
            GlobePin(
              flag: stop.flag, selected: trip.id == selected?.id,
              dimmed: selected != nil && trip.id != selected?.id
            ) { model.globeTripID = trip.id }
            .accessibilityLabel("\(stop.place), \(trip.name)")
          }
          .annotationTitles(.hidden)
        }
      }
    }
    .mapStyle(.imagery(elevation: .realistic))
    .mapControlVisibility(.hidden)
    .onMapCameraChange(frequency: .onEnd) { context in
      if position.positionedByUser {
        settled = context.camera
        touchedAt = .now
      }
    }
    // Keeps the globe centred in the space between the header and the card.
    .safeAreaPadding(.top, 70).safeAreaPadding(.bottom, 150)
    .ignoresSafeArea()
  }

  private func arcColour(_ trip: TripSnapshot, selected: TripSnapshot?) -> Color {
    if trip.id == selected?.id { return Theme.accent }
    // White reads on satellite imagery where the prototype's navy would sink into the ocean.
    return .white.opacity(selected == nil ? 0.6 : 0.2)
  }

  private var header: some View {
    let trips = model.store.trips
    let countries = Set(trips.flatMap { $0.stops.map(\.countryCode) }).count
    return VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Your world").typeface(34, .heavy, tracking: -0.035, relativeTo: .largeTitle, maximum: 1.3)
          .foregroundStyle(.white)
          .accessibilityAddTraits(.isHeader)
        Text(
          "\(countries) \(countries == 1 ? "country" : "countries") · \(trips.count) \(trips.count == 1 ? "trip" : "trips")"
        )
        .typeface(14, relativeTo: .subheadline).foregroundStyle(.white.opacity(0.68))
      }
      .padding(.top, 6)
      .allowsHitTesting(false)
      GlobeFilterPills()
    }
    .padding(.horizontal, 20).padding(.bottom, 24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      LinearGradient(
        stops: [
          .init(color: Self.space, location: 0.35), .init(color: Self.space.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom
      )
      .ignoresSafeArea(edges: .top)
      .allowsHitTesting(false)
    }
  }

  private func fly(to trip: TripSnapshot, animated: Bool) {
    guard let centre = trip.centre else { return }
    let camera = MapCamera(
      centerCoordinate: centre.location,
      distance: min(max(trip.reach * 6, 6_000_000), Self.globeDistance))
    withAnimation(animated && !reduceMotion ? .easeInOut(duration: 1.1) : nil) {
      position = .camera(camera)
    }
  }

  private func zoomOut() {
    let longitude =
      (settled ?? position.camera)?.centerCoordinate.longitude
      ?? model.store.trips.first?.centre?.longitude ?? 0
    let camera = Self.globe(at: GeoPoint(latitude: 30, longitude: longitude))
    settled = camera
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.1)) { position = .camera(camera) }
  }

  private static func globe(at point: GeoPoint) -> MapCamera {
    MapCamera(centerCoordinate: point.location, distance: globeDistance)
  }

  private static func wrap(_ longitude: Double) -> Double {
    longitude > 180 ? longitude - 360 : longitude
  }

  /// One pin per place on a trip, even when the route returns to it.
  private static func uniqueStops(_ trip: TripSnapshot) -> [Stop] {
    var seen = Set<String>()
    return trip.stops.filter { seen.insert($0.place).inserted }
  }
}

private struct GlobePin: View {
  let flag: String
  let selected: Bool
  let dimmed: Bool
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      Text(flag).font(.system(size: 16))
        .frame(width: 30, height: 30)
        .background(.white, in: Circle())
        .overlay { if selected { Circle().stroke(Theme.accent, lineWidth: 3.5) } }
        .shadow(color: .black.opacity(0.4), radius: 2.5, y: 2)
    }
    .buttonStyle(PressStyle(scale: 0.9))
    .scaleEffect(selected ? 1.3 : dimmed ? 0.8 : 1)
    .opacity(dimmed ? 0.6 : 1)
    .animation(Motion.spring, value: selected)
    .animation(Motion.spring, value: dimmed)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

private struct GlobeFilterPills: View {
  @Environment(AppModel.self) private var model
  @Namespace private var thumb
  var body: some View {
    HStack(spacing: 4) {
      ForEach(GlobeFilter.allCases) { filter in
        let on = model.globeFilter == filter
        Button {
          withAnimation(Motion.spring) { model.globeFilter = filter }
        } label: {
          Text(filter.rawValue).typeface(13, .bold, relativeTo: .footnote)
            .foregroundStyle(on ? Color(hex: 0x0A0C0F) : .white.opacity(0.75))
            .padding(.vertical, 7).padding(.horizontal, 13)
            .background {
              if on { Capsule().fill(.white).matchedGeometryEffect(id: "thumb", in: thumb) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
      }
    }
    .padding(4)
    .glassEffect(.regular.tint(Color(hex: 0x282C34, opacity: 0.6)), in: Capsule())
  }
}

extension GeoPoint {
  var location: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}
