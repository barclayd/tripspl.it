import SwiftUI
import TripSplitAppleAdapters
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitPersistence
import TripSplitSharedUI

struct DayLocationSheet: View {
  init(trip: TripSnapshot, day: TripDay) {
    self.tripID = trip.id
    self.dayID = day.id
    _selected = State(initialValue: day.location)
  }
  let tripID: String
  let dayID: String
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var query = ""
  @State private var selected: TripOrigin?
  @State private var search = DestinationSearch()
  @State private var error: String?
  @FocusState private var searching: Bool

  var body: some View {
    NavigationStack {
      if let trip = model.store.trip(tripID), let day = trip.days.first(where: { $0.id == dayID }) {
        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            heading(trip, day: day)
            HStack(spacing: 10) {
              Image(systemName: "magnifyingglass").foregroundStyle(Theme.tertiary)
              TextField("Search cities and places", text: $query)
                .focused($searching).submitLabel(.search).onSubmit(searchMaps)
                .autocorrectionDisabled().accessibilityIdentifier("day.location.search")
              if !query.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                  .labelStyle(.iconOnly).foregroundStyle(Theme.tertiary)
              }
            }
            .typeface(16, .semibold, relativeTo: .body)
            .padding(15).background(Theme.inset, in: RoundedRectangle(cornerRadius: 16))

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              if let stop = trip.stops.first(where: { $0.id == day.stopId }) {
                VStack(alignment: .leading, spacing: 10) {
                  sectionTitle("FROM YOUR ITINERARY")
                  locationRow(.init(place: stop.place, countryCode: stop.countryCode,
                    latitude: stop.latitude, longitude: stop.longitude),
                    detail: "Use itinerary location", selected: selected == nil) { choose(nil) }
                }
              }
              if let selected {
                VStack(alignment: .leading, spacing: 10) {
                  sectionTitle("THIS DAY ONLY")
                  locationRow(selected, detail: country(selected), selected: true) { choose(selected) }
                }
              }
              VStack(alignment: .leading, spacing: 10) {
                sectionTitle("ON YOUR ROUTE")
                ForEach(trip.stops) { stop in
                  let location = TripOrigin(place: stop.place, countryCode: stop.countryCode,
                    latitude: stop.latitude, longitude: stop.longitude)
                  locationRow(location, detail: country(location), selected: selected == location) {
                    choose(location)
                  }
                }
              }
            } else {
              VStack(alignment: .leading, spacing: 10) {
                sectionTitle("PLACES")
                let matches = Destination.search(query, limit: 20)
                ForEach(matches) { destination in
                  locationRow(destination.origin, detail: country(destination.origin),
                    selected: selected == destination.origin) { choose(destination.origin) }
                }
                if matches.isEmpty && search.matches.isEmpty && !search.isSearching {
                  Text("Try a city or country, or search Apple Maps for somewhere smaller.")
                    .typeface(14, relativeTo: .subheadline).foregroundStyle(Theme.secondary)
                }
                Button(action: searchMaps) {
                  Label("Search Apple Maps", systemImage: "map")
                    .typeface(15, .bold, relativeTo: .subheadline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.inset, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(PressStyle(scale: 0.98))
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || search.isSearching)
                if search.isSearching { ProgressView("Finding places…").padding(.vertical, 8) }
                if let error = search.error {
                  Text(error).typeface(13, relativeTo: .footnote).foregroundStyle(Theme.secondary)
                }
                ForEach(search.matches) { destination in
                  locationRow(destination.origin, detail: country(destination.origin),
                    selected: selected == destination.origin) { choose(destination.origin) }
                }
              }
            }
            if let error {
              Text(error).typeface(14, .semibold, relativeTo: .footnote).foregroundStyle(Theme.bad)
            }
          }
          .padding(22).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.surface)
        .navigationTitle("Day location").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") { save() }.bold().disabled(trip.role != "owner")
              .accessibilityIdentifier("day.location.save")
          }
        }
      }
    }
    .tint(Theme.accentText)
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.surface)
    .presentationCornerRadius(Theme.Radius.sheet)
    .onChange(of: query) { _, _ in search.cancel() }
    .onDisappear { search.cancel() }
  }

  private func heading(_ trip: TripSnapshot, day: TripDay) -> some View {
    let place = selected ?? trip.stops.first { $0.id == day.stopId }.map {
      TripOrigin(place: $0.place, countryCode: $0.countryCode, latitude: $0.latitude, longitude: $0.longitude)
    }
    return VStack(alignment: .leading, spacing: 9) {
      Text(CivilDate.display(day.date, format: "EEEE d MMMM").uppercased())
        .typeface(11.5, .black, tracking: 0.05, relativeTo: .caption)
        .foregroundStyle(Theme.accentText)
      HStack(spacing: 12) {
        Text(place?.countryCode.flag ?? "📍").font(.system(size: 36)).accessibilityHidden(true)
        Text(place?.place ?? "Where are you heading?")
          .typeface(29, .heavy, tracking: -0.035, relativeTo: .title, maximum: 1.4)
          .foregroundStyle(Theme.ink).contentTransition(.opacity)
      }
      Text("A day trip? Choose where you’ll be for this day.")
        .typeface(14, relativeTo: .subheadline).foregroundStyle(Theme.secondary)
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selected)
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title).typeface(10.5, .black, tracking: 0.06, relativeTo: .caption2)
      .foregroundStyle(Theme.tertiary).padding(.horizontal, 4)
  }

  private func country(_ location: TripOrigin) -> String {
    CountryMetadata.country(location.countryCode)?.name ?? location.countryCode
  }

  private func locationRow(_ location: TripOrigin, detail: String, selected: Bool,
                           action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Text(location.countryCode.flag).font(.system(size: 25)).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text(location.place).typeface(16, .heavy, relativeTo: .body).foregroundStyle(Theme.ink)
          Text(detail).typeface(12.5, .semibold, relativeTo: .caption).foregroundStyle(Theme.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 21, weight: .semibold))
          .foregroundStyle(selected ? Theme.accentText : Theme.line2)
          .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
      }
      .padding(15).frame(minHeight: 66)
      .background(selected ? Theme.accentSoft : Theme.inset, in: RoundedRectangle(cornerRadius: 17))
      .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle(scale: 0.98))
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityLabel("\(location.place), \(detail)")
  }

  private func choose(_ location: TripOrigin?) {
    Haptics.selection()
    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { selected = location }
    searching = false
  }

  private func searchMaps() {
    searching = false
    Task { await search.searchMaps(query) }
  }

  private func save() {
    do {
      try model.setDayLocation(selected, dayID: dayID, tripID: tripID)
      Haptics.success()
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}
