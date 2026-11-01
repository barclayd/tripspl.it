import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitPersistence
import TripSplitSync

package struct DestinationTimeZoneSelection: Identifiable {
  package init(id: String) {
    self.id = id
  }
  package let id: String
}

package enum TimeZonePresentation {
  package static func city(_ identifier: String) -> String {
    String(identifier.split(separator: "/").last ?? Substring(identifier))
      .replacingOccurrences(of: "_", with: " ")
  }
  package static func offset(_ identifier: String, at date: Date) -> String {
    guard let zone = TimeZone(identifier: identifier) else { return "" }
    let seconds = zone.secondsFromGMT(for: date)
    guard seconds != 0 else { return "UTC" }
    let hours = abs(seconds) / 3600
    let minutes = abs(seconds) % 3600 / 60
    return "UTC\(seconds < 0 ? "−" : "+")\(String(format: "%02d:%02d", hours, minutes))"
  }
}

package struct DestinationTimeZoneRow: View {
  package init(place: String, identifier: String? = nil, date: Date = Date()) {
    self.place = place
    self.identifier = identifier
    self.date = date
  }
  package let place: String
  package let identifier: String?
  package var date = Date()
  package var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "globe").font(.title3).foregroundStyle(Theme.accent)
        .frame(width: 40, height: 40).background(Theme.accentSoft, in: Circle())
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(place).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
        if let identifier {
          Text(
            "\(TimeZonePresentation.city(identifier)) · \(TimeZonePresentation.offset(identifier, at: date))"
          )
          .font(.caption).foregroundStyle(Theme.secondary)
        } else {
          Text("Choose time zone").font(.caption).foregroundStyle(Theme.accent)
        }
      }
      Spacer(minLength: 8)
      Image(systemName: "chevron.right").font(.caption.weight(.semibold))
        .foregroundStyle(Theme.secondary).accessibilityHidden(true)
    }.frame(minHeight: 44).contentShape(Rectangle())
      .accessibilityElement(children: .combine).accessibilityHint("Change destination time zone")
  }
}

package struct TimeZonePicker: View {
  package init(
    selection: Binding<String>, allowedIdentifiers: [String], title: String = "Time zone",
    referenceDate: Date = Date()
  ) {
    self._selection = selection
    self.allowedIdentifiers = allowedIdentifiers
    self.title = title
    self.referenceDate = referenceDate
  }
  @Environment(\.dismiss) private var dismiss
  @Binding var selection: String
  package let allowedIdentifiers: [String]
  package var title = "Time zone"
  package var referenceDate = Date()
  @State private var query = ""
  private var identifiers: [String] {
    // A few uninhabited territories have no assigned zone. Allow an explicit choice there.
    let available =
      allowedIdentifiers.isEmpty ? TimeZone.knownTimeZoneIdentifiers : allowedIdentifiers
    return Array(Set(available)).filter { TimeZone(identifier: $0) != nil }.sorted {
      let comparison = TimeZonePresentation.city($0).localizedStandardCompare(
        TimeZonePresentation.city($1))
      return comparison == .orderedSame ? $0 < $1 : comparison == .orderedAscending
    }
  }
  private var matches: [String] {
    let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !search.isEmpty else { return identifiers }
    return identifiers.filter { identifier in
      let zone = TimeZone(identifier: identifier)
      return [
        identifier.replacingOccurrences(of: "_", with: " "),
        TimeZonePresentation.offset(identifier, at: referenceDate),
        zone?.localizedName(for: .generic, locale: .current) ?? "",
        zone?.abbreviation(for: referenceDate) ?? "",
      ]
      .contains { $0.range(of: search, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
  }
  package var body: some View {
    NavigationStack {
      List {
        if matches.isEmpty {
          Text(identifiers.isEmpty ? "No time zones available." : "No matching time zones.")
            .foregroundStyle(Theme.secondary)
        }
        ForEach(matches, id: \.self) { identifier in
          Button {
            selection = identifier
            dismiss()
          } label: {
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 4) {
                Text(TimeZonePresentation.city(identifier)).font(.headline).foregroundStyle(
                  Theme.ink)
                Text(TimeZonePresentation.offset(identifier, at: referenceDate))
                  .font(.caption).foregroundStyle(Theme.secondary)
              }
              Spacer(minLength: 8)
              if selection == identifier {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
              }
            }.frame(minHeight: 52).contentShape(Rectangle())
          }.buttonStyle(.plain)
            .accessibilityAddTraits(selection == identifier ? .isSelected : [])
            .accessibilityIdentifier("timezone.choice.\(identifier)")
        }
      }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Theme.background)
        .scrollDismissesKeyboard(.interactively).scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .top, spacing: 0) {
          HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
            TextField("Search time zones", text: $query)
              .textInputAutocapitalization(.never).autocorrectionDisabled()
              .accessibilityIdentifier("timezone.search")
            if !query.isEmpty {
              Button {
                query = ""
              } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondary)
                  .frame(width: 44, height: 44)
              }.accessibilityLabel("Clear search")
            }
          }.padding(.leading, 14).padding(.trailing, query.isEmpty ? 14 : 0)
            .frame(minHeight: 48).background(Theme.inset, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20).padding(.vertical, 12).background(Theme.background)
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", systemImage: "xmark") { dismiss() }
          }
        }
    }.tint(Theme.accent)
  }
}
