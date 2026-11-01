import SwiftUI

struct ConversionCurrencyPicker: View {
  @Environment(\.dismiss) private var dismiss
  let title: String
  let selection: ConversionCurrency
  let onSelect: (ConversionCurrency) -> Void
  @State private var query = ""
  private var matches: [ConversionCurrency] {
    ConversionCurrency.search(
      query, limit: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Int.max : 60)
  }
  var body: some View {
    NavigationStack {
      List {
        Section("Selected") { row(selection, selected: true) }
        Section(query.isEmpty ? "Countries & currencies" : "Matches") {
          if matches.isEmpty {
            Text("No matches yet. Try a country, city, currency code or flag emoji.")
              .foregroundStyle(Theme.secondary)
          } else {
            ForEach(matches) { currency in
              Button {
                onSelect(currency)
                dismiss()
              } label: {
                row(currency, selected: currency.id == selection.id)
              }
              .buttonStyle(.plain).contentShape(Rectangle())
              .accessibilityLabel("\(currency.title), \(currency.code), \(currency.currencyName)")
              .accessibilityAddTraits(currency.id == selection.id ? .isSelected : [])
              .accessibilityIdentifier("converter.choice.\(currency.id)")
            }
          }
        }
      }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Theme.background)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
          HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
            TextField("Country, city, currency or flag", text: $query)
              .textInputAutocapitalization(.never).autocorrectionDisabled()
              .accessibilityLabel("Search countries, cities, currencies or flags")
              .accessibilityIdentifier("converter.search")
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
  private func row(_ currency: ConversionCurrency, selected: Bool) -> some View {
    HStack(spacing: 14) {
      Text(currency.flag).font(.title).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(currency.title).font(.headline).foregroundStyle(Theme.ink)
        Text("\(currency.code) · \(currency.currencyName)").font(.caption).foregroundStyle(
          Theme.secondary)
      }
      Spacer(minLength: 8)
      if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
    }.frame(minHeight: 52).padding(.vertical, 4).contentShape(Rectangle())
  }
}
