import SwiftUI
import TripSplitAppleAdapters
import TripSplitDesignSystem
import TripSplitDomain

/// The rounded "Search cities or countries" field the place steps share.
struct PlaceSearchField: View {
  @Binding var text: String
  let focus: FocusState<Bool>.Binding
  let hint: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .bold))
        .foregroundStyle(Theme.tertiary).accessibilityHidden(true)
      TextField("Search cities or countries", text: $text)
        .typeface(16, .bold, relativeTo: .body, maximum: 1.4).foregroundStyle(Theme.ink)
        .focused(focus).textInputAutocapitalization(.words).autocorrectionDisabled()
        .submitLabel(.search).onSubmit { focus.wrappedValue = false }
        .accessibilityIdentifier("onboarding.search")
        .accessibilityHint(hint)
      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill").font(.system(size: 17))
            .foregroundStyle(Theme.tertiary).frame(width: 32, height: 44)
        }.buttonStyle(.plain).accessibilityLabel("Clear search")
      }
    }
    .padding(.horizontal, 16).frame(minHeight: 50)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.key))
  }
}

/// A place as a pill: flag and name, the country in grey beside a city, and how many times it's
/// in the route.
struct PlaceChip: View {
  let destination: Destination
  var selected = false
  var showsCountry = true
  var count = 0

  var body: some View {
    HStack(spacing: 7) {
      Text(destination.flag).font(.system(size: 20))
      Text(destination.city).typeface(14.5, .heavy, relativeTo: .subheadline, maximum: 1.4)
        .lineLimit(1)
      if showsCountry, !destination.isCountry {
        Text(destination.country).typeface(12.5, .bold, relativeTo: .caption, maximum: 1.4)
          .foregroundStyle(Theme.tertiary).lineLimit(1)
      }
      if count > 0 {
        Text("\(count)").typeface(11, .black, relativeTo: .caption2, maximum: 1.3)
          .monospacedDigit().foregroundStyle(Theme.accentInk)
          .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
          .background(Theme.accent, in: Capsule())
          .bump(on: count).transition(.scale.combined(with: .opacity))
      }
    }
    .foregroundStyle(selected ? Theme.accentText : Theme.ink)
    .padding(.top, 9).padding(.trailing, 13).padding(.bottom, 9).padding(.leading, 10)
    .background(selected ? Theme.accentSoft : Theme.surface, in: Capsule())
    .overlay { Capsule().strokeBorder(Theme.accent, lineWidth: selected ? 2 : 0) }
    .contentShape(Capsule())
  }
}

/// "Search Apple Maps for …" under the local results, and what Apple Maps found once asked.
struct MapsSearchResults<Chip: View>: View {
  let query: String
  let search: DestinationSearch
  /// Whether Apple Maps has been asked about this exact query.
  let searched: Bool
  var disabled = false
  let onSearch: () -> Void
  @ViewBuilder let chip: (Destination) -> Chip

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button(action: onSearch) {
        Label("Search Apple Maps for “\(query)”", systemImage: "map")
          .typeface(14, .heavy, relativeTo: .subheadline, maximum: 1.4)
          .foregroundStyle(Theme.accentText).lineLimit(1).frame(minHeight: 44)
      }.buttonStyle(.plain)
        .disabled(search.isSearching || disabled).opacity(disabled ? 0.4 : 1)
        .accessibilityIdentifier("onboarding.searchMaps")
      if searched {
        if search.isSearching {
          ProgressView("Searching Apple Maps…").tint(Theme.secondary)
        } else if let error = search.error {
          Text(error).typeface(13, .semibold, relativeTo: .footnote).foregroundStyle(Theme.bad)
        } else if search.matches.isEmpty {
          Text("No places found. Try adding the country to your search.")
            .typeface(13, .semibold, relativeTo: .footnote).foregroundStyle(Theme.secondary)
        } else {
          FlowLayout(spacing: 8) {
            ForEach(search.matches) { chip($0) }
          }
        }
      }
    }
  }
}
