import SwiftUI
import TripSplitAppleAdapters
import TripSplitDesignSystem
import TripSplitDomain

struct DestinationLabel: View {
  let destination: Destination
  var selected = false
  var body: some View {
    HStack(spacing: 10) {
      Text(destination.flag).font(.title2).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(destination.city).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
        Text(destination.secondaryLabel)
          .font(.caption).foregroundStyle(Theme.secondary)
      }
      Spacer(minLength: 4)
      Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
        .foregroundStyle(selected ? Theme.accent : Theme.secondary).accessibilityHidden(true)
    }
  }
}

struct DestinationCurrencyPicker: View {
  let countryCode: String
  @Binding var currency: String
  private var currencies: [String] { CountryMetadata.country(countryCode)?.currencies ?? [] }
  var body: some View {
    if currencies.count == 1, let code = currencies.first {
      LabeledContent("Currency", value: currencyLabel(code))
    } else {
      if currencies.isEmpty {
        Text(
          "This destination has no national currency. Choose the travel currency you’ll use for costs here."
        )
        .font(.footnote).foregroundStyle(Theme.secondary)
      }
      Picker(currencies.isEmpty ? "Travel currency" : "Currency", selection: $currency) {
        Text("Choose a currency").tag("")
        ForEach(currencies.isEmpty ? CurrencyMetadata.codes : currencies, id: \.self) { code in
          Text(currencyLabel(code)).tag(code)
        }
      }
    }
  }
  private func currencyLabel(_ code: String) -> String {
    "\(code) · \(Locale.current.localizedString(forCurrencyCode: code) ?? code)"
  }
}

struct DestinationCurrencySheet: View {
  @Environment(\.dismiss) private var dismiss
  let destination: Destination
  let onConfirm: (String) -> Void
  @State private var currency = ""
  var body: some View {
    NavigationStack {
      Form {
        Section {
          Label("\(destination.flag) \(destination.city)", systemImage: "mappin.and.ellipse")
          DestinationCurrencyPicker(countryCode: destination.countryCode, currency: $currency)
            .accessibilityIdentifier("onboarding.travelCurrency")
        }
        Section {
          Button("Add to route", systemImage: "plus") {
            guard CurrencyMetadata.codes.contains(currency) else { return }
            onConfirm(currency)
            dismiss()
          }.disabled(!CurrencyMetadata.codes.contains(currency)).frame(minHeight: 44)
            .accessibilityIdentifier("onboarding.confirmCurrency")
        }
      }.navigationTitle("Choose a currency").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", systemImage: "xmark") { dismiss() }
          }
        }
        .onAppear {
          currency = CountryMetadata.country(destination.countryCode)?.defaultCurrency ?? ""
        }
    }.tint(Theme.accent).scrollBounceBehavior(.basedOnSize)
  }
}

struct CustomDestinationSheet: View {
  @Environment(\.dismiss) private var dismiss
  let isSelected: (Destination) -> Bool
  let onSelect: (Destination) -> Void
  @State private var city = ""
  @State private var countryCode = "GB"
  @State private var currency = "GBP"
  @State private var search = DestinationSearch()
  @State private var hasSearched = false
  @State private var adding = false
  @FocusState private var cityFocused: Bool
  private var country: CountryMetadata.Country? { CountryMetadata.country(countryCode) }
  private var matches: [Destination] { search.matches.filter { $0.countryCode == countryCode } }
  private var currencyIsValid: Bool {
    let allowed = country?.currencies ?? []
    return allowed.isEmpty ? CurrencyMetadata.codes.contains(currency) : allowed.contains(currency)
  }
  var body: some View {
    NavigationStack {
      Form {
        Section("Destination") {
          TextField("City or place", text: $city).focused($cityFocused)
            .textInputAutocapitalization(.words).submitLabel(.search).onSubmit(searchMaps)
            .accessibilityIdentifier("onboarding.custom.search")
          Picker("Country", selection: $countryCode) {
            ForEach(CountryMetadata.all, id: \.code) { country in
              Text("\(country.code.flag) \(country.name)").tag(country.code)
            }
          }.accessibilityIdentifier("onboarding.custom.country")
          DestinationCurrencyPicker(countryCode: countryCode, currency: $currency)
            .accessibilityIdentifier("onboarding.custom.currency")
        }
        Section {
          Button(action: searchMaps) {
            Label("Search Apple Maps", systemImage: "magnifyingglass").frame(minHeight: 44)
          }.disabled(
            city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || search.isSearching
          )
          .accessibilityIdentifier("onboarding.custom.searchMaps")
        } footer: {
          Text(
            "Requires an internet connection."
          )
        }
        if hasSearched {
          Section("Choose a place") {
            if search.isSearching {
              ProgressView("Searching Apple Maps…")
            } else if let error = search.error {
              Text(error).foregroundStyle(Theme.bad)
            } else if matches.isEmpty {
              Text(
                "No places found in \(country?.name ?? countryCode). Try a nearby city or a more specific name."
              )
              .foregroundStyle(Theme.secondary)
            } else {
              ForEach(matches) { destination in
                Button {
                  guard currencyIsValid, !adding, !isSelected(destination) else { return }
                  adding = true
                  var confirmed = destination
                  confirmed.currency = currency
                  onSelect(confirmed)
                  dismiss()
                } label: {
                  DestinationLabel(destination: destination, selected: isSelected(destination))
                    .frame(minHeight: 56)
                }.disabled(!currencyIsValid || adding || isSelected(destination))
                  .accessibilityIdentifier("onboarding.custom.destination.\(destination.id)")
                  .accessibilityHint(
                    isSelected(destination)
                      ? "Already in your route" : "Add this place to your route")
              }
              if !currencyIsValid {
                Text("Choose a travel currency above before adding this stop.")
                  .font(.footnote).foregroundStyle(Theme.secondary)
              }
            }
          }
        }
      }.navigationTitle("Another destination").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", systemImage: "xmark") { dismiss() }
          }
        }
        .onChange(of: countryCode) { _, _ in
          let allowed = country?.currencies ?? []
          if !allowed.contains(currency) { currency = country?.defaultCurrency ?? "" }
          invalidateSearch()
        }
        .onChange(of: city) { _, _ in invalidateSearch() }
        .onDisappear { search.cancel() }
    }.tint(Theme.accent).scrollBounceBehavior(.basedOnSize)
  }
  private func invalidateSearch() {
    search.cancel()
    hasSearched = false
  }
  private func searchMaps() {
    let place = city.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !place.isEmpty, !search.isSearching else { return }
    cityFocused = false
    hasSearched = true
    let requested = "\(place), \(country?.name ?? countryCode)"
    Task { await search.searchMaps(requested) }
  }
}
