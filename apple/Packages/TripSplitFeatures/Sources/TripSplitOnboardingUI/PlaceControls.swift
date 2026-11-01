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
/// in the route. A spinner stands in for the flag while Maps looks the place up.
struct PlaceChip: View {
  let flag: String
  let name: String
  var context: String?
  var selected = false
  var count = 0
  var busy = false

  init(
    destination: Destination, selected: Bool = false, showsCountry: Bool = true, count: Int = 0
  ) {
    flag = destination.flag
    name = destination.city
    context = showsCountry && !destination.isCountry ? destination.country : nil
    self.selected = selected
    self.count = count
  }

  init(suggestion: PlaceSuggestion, busy: Bool) {
    flag = suggestion.flag
    name = suggestion.title
    context = suggestion.context
    self.busy = busy
  }

  var body: some View {
    HStack(spacing: 7) {
      ZStack {
        Text(flag).font(.system(size: 20)).opacity(busy ? 0 : 1)
        if busy { ProgressView().controlSize(.small).tint(Theme.secondary) }
      }
      Text(name).typeface(14.5, .heavy, relativeTo: .subheadline, maximum: 1.4)
        .lineLimit(1)
      if let context {
        Text(context).typeface(12.5, .bold, relativeTo: .caption, maximum: 1.4)
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

/// The catalogue's matches for a search, then what Apple Maps suggests for anywhere else. A
/// suggestion becomes an ordinary chip once it has been looked up.
struct PlaceResults<Chip: View>: View {
  let results: [Destination]
  let completer: PlaceCompleter
  /// What tapping a suggestion does, for VoiceOver.
  let hint: String
  var disabled = false
  @ViewBuilder let chip: (Destination) -> Chip
  let onSuggestion: (PlaceSuggestion) -> Void

  var body: some View {
    let suggested = completer.suggestions(beyond: results)
    VStack(alignment: .leading, spacing: 12) {
      if results.isEmpty, suggested.isEmpty {
        if completer.isPending {
          ProgressView("Searching Apple Maps…").tint(Theme.secondary)
            .typeface(14, .semibold, relativeTo: .subheadline).foregroundStyle(Theme.secondary)
        } else {
          Text("No matching countries or cities.")
            .typeface(14, .semibold, relativeTo: .subheadline).foregroundStyle(Theme.secondary)
        }
      } else {
        FlowLayout(spacing: 8) {
          ForEach(results) { chip($0) }
          ForEach(suggested) { suggestion in
            if let place = completer.resolved[suggestion.id] {
              chip(place)
            } else {
              suggestionChip(suggestion)
            }
          }
        }
      }
      if let error = completer.error {
        Text(error).typeface(13, .semibold, relativeTo: .footnote).foregroundStyle(Theme.bad)
      }
    }
  }

  private func suggestionChip(_ suggestion: PlaceSuggestion) -> some View {
    let busy = completer.resolving == suggestion.id
    return Button {
      onSuggestion(suggestion)
    } label: {
      PlaceChip(suggestion: suggestion, busy: busy).opacity(disabled ? 0.45 : 1)
    }
    .buttonStyle(PressStyle(scale: 0.93))
    .transition(.scale(scale: 0.8).combined(with: .opacity))
    .accessibilityLabel(
      [suggestion.title, suggestion.context].compactMap { $0 }.joined(separator: ", ")
    )
    .accessibilityValue(busy ? "Looking it up" : "")
    .accessibilityHint(hint)
    .accessibilityIdentifier("onboarding.suggestion.\(suggestion.title)")
  }
}
