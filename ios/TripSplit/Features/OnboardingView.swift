import SwiftUI

struct OnboardingView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var query = ""
  @State private var personName = ""
  @State private var custom = false
  @State private var destinationSearch = DestinationSearch()
  @State private var searchedMapQuery: String?
  @State private var currencyDestination: Destination?
  @FocusState private var inputFocused: Bool
  @ScaledMetric(relativeTo: .subheadline) private var routeHeight = 78.0
  private let titles = [
    "Where are you off to?", "When do you leave?", "How long in each place?", "Who’s coming?",
    "What’s your home currency?", "What’s the budget?", "You’re all set.",
  ]
  private let subtitles = [
    "Choose countries or cities, then continue when your route is ready.",
    "Pick the day you set off.",
    "A little stopover or a long, slow stay?", "Everyone who’ll be splitting costs.",
    "One currency for the honest, whole-trip total.", "For the whole trip, everyone included.",
    "Next, add how you’re getting there.",
  ]
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ProgressView(value: Double(model.onboarding.step + 1), total: 7).tint(Theme.accent)
          .scaleEffect(y: 2).padding(.horizontal, 24).padding(.vertical, 12)
          .frame(maxWidth: 680).frame(maxWidth: .infinity)
        ScrollViewReader { scroll in
          ScrollView {
            VStack(alignment: .leading, spacing: 24) {
              if model.onboarding.step > 0, let trip = try? model.onboarding.makeTrip() {
                BoardingPassStack(trip: trip, cleared: model.onboarding.step == 6)
              }
              VStack(alignment: .leading, spacing: 8) {
                Text(titles[model.onboarding.step]).font(.largeTitle.weight(.heavy)).tracking(-1)
                Text(subtitles[model.onboarding.step]).font(.subheadline).foregroundStyle(
                  Theme.secondary
                ).lineSpacing(3)
              }
              step
            }.pagePadding().padding(.bottom, 20).id("onboarding-top")
          }.scrollDismissesKeyboard(.interactively)
            .onChange(of: model.onboarding.step) { _, _ in
              inputFocused = false
              scroll.scrollTo("onboarding-top", anchor: .top)
            }
        }
        footer
      }.overlay { if model.onboarding.step == 6 { Celebration() } }.background(Theme.background)
        .navigationTitle("\(min(model.onboarding.step + 1, 6)) of 6")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark") {
              model.saveOnboarding()
              dismiss()
            }
          }
        }
        .onChange(of: model.onboarding) { _, _ in model.saveOnboarding() }
        .onChange(of: query) { _, _ in
          destinationSearch.cancel()
          searchedMapQuery = nil
        }
        .onDisappear { destinationSearch.cancel() }
        .sheet(isPresented: $custom) {
          CustomDestinationSheet(isSelected: isSelected) { destination in
            addDestination(destination)
          }
        }
        .sheet(item: $currencyDestination) { destination in
          DestinationCurrencySheet(destination: destination) { currency in
            var confirmed = destination
            confirmed.currency = currency
            addDestination(confirmed)
          }
        }
    }
  }

  private var footer: some View {
    VStack(spacing: 8) {
      Text(cheer).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
        .multilineTextAlignment(.center)
      let layout =
        dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 16))
      layout {
        if model.onboarding.step == 6 {
          Button("Go to trip") { model.finishOnboarding(planTravel: false) }
            .font(.subheadline.weight(.semibold)).frame(minWidth: 78, minHeight: 50)
        } else {
          Button(action: goBack) {
            Label("Back", systemImage: "chevron.backward")
              .font(.headline).frame(minWidth: 78, minHeight: 50)
              .contentShape(Rectangle())
          }.buttonStyle(.plain).foregroundStyle(Theme.ink)
            .accessibilityIdentifier("onboarding.back")
            .disabled(model.onboarding.step == 0)
            .opacity(model.onboarding.step == 0 ? 0.4 : 1)
        }
        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        Button(action: advance) {
          HStack(spacing: 12) {
            Text(
              model.onboarding.step == 5
                ? "Create trip"
                : model.onboarding.step == 6 ? "Plan getting there" : "Continue")
            Image(systemName: model.onboarding.step == 6 ? "airplane" : "arrow.right")
          }.font(.headline).foregroundStyle(.white)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).frame(maxWidth: 320).fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("onboarding.continue")
          .disabled(!valid).opacity(valid ? 1 : 0.45)
      }
    }.frame(maxWidth: 640).padding(.horizontal, 20).padding(.vertical, 12)
      .frame(maxWidth: .infinity).background(Theme.background)
      .overlay(alignment: .top) { Rectangle().fill(Theme.inset).frame(height: 1) }
      .fixedSize(horizontal: false, vertical: true)
  }
  @ViewBuilder private var step: some View {
    switch model.onboarding.step {
    case 0:
      routeSelection
      TextField("Search country or city", text: $query)
        .textFieldStyle(.roundedBorder).focused($inputFocused)
        .accessibilityIdentifier("onboarding.search")
        .textInputAutocapitalization(.words).submitLabel(.search)
        .onSubmit { inputFocused = false }
        .accessibilityHint("Search countries and cities, or use Apple Maps for another place")
      VStack(alignment: .leading, spacing: 12) {
        Text(searchQuery.isEmpty ? "A little inspiration" : "Countries & cities")
          .font(.headline)
        if catalogueMatches.isEmpty {
          Text("No saved places match. Try Apple Maps or add another destination below.")
            .font(.subheadline).foregroundStyle(Theme.secondary)
        } else {
          LazyVGrid(columns: [.init(.adaptive(minimum: 240), spacing: 10)], spacing: 10) {
            ForEach(catalogueMatches) { destination in
              destinationRow(destination)
            }
          }
        }
      }
      if !searchQuery.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          Button(action: searchMaps) {
            Label("Search Apple Maps", systemImage: "magnifyingglass")
              .frame(minHeight: 44)
          }.disabled(destinationSearch.isSearching || model.onboarding.stops.count >= 6)
            .accessibilityIdentifier("onboarding.searchMaps")
          Text("Find a specific city or place online. Choose a result to add it.")
            .font(.footnote).foregroundStyle(Theme.secondary)
          if searchedMapQuery == searchQuery {
            if destinationSearch.isSearching {
              ProgressView("Searching Apple Maps…")
            } else if let error = destinationSearch.error {
              Text(error).font(.footnote).foregroundStyle(Theme.bad)
            } else if destinationSearch.matches.isEmpty {
              Text("No places found. Try adding the country to your search.")
                .font(.footnote).foregroundStyle(Theme.secondary)
            } else {
              LazyVGrid(columns: [.init(.adaptive(minimum: 240), spacing: 10)], spacing: 10) {
                ForEach(destinationSearch.matches) { destination in
                  destinationRow(destination)
                }
              }
            }
          }
        }
      }
      Button("Add another destination", systemImage: "mappin.and.ellipse") {
        inputFocused = false
        custom = true
      }.frame(minHeight: 44).disabled(model.onboarding.stops.count >= 6)
        .accessibilityIdentifier("onboarding.addCustom")
    case 1:
      DatePicker(
        "Departure",
        selection: Binding(
          get: { CivilDate.date(model.onboarding.startsOn) },
          set: { model.onboarding.startsOn = CivilDate.string($0) }), displayedComponents: .date
      ).datePickerStyle(.graphical).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!).padding(
        12
      ).background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
      Picker(
        "Trip time zone",
        selection: Binding(
          get: { model.onboarding.timeZone }, set: { model.onboarding.timeZone = $0 })
      ) {
        ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) {
          Text($0.replacingOccurrences(of: "_", with: " ")).tag($0)
        }
      }
      Text("Today and trip dates follow this time zone. You can change it in trip settings.").font(
        .footnote
      ).foregroundStyle(Theme.secondary)
      Text("You can also log an adventure that already happened.").font(.footnote).foregroundStyle(
        Theme.secondary)
    case 2:
      HStack(alignment: .firstTextBaseline) {
        Text("\(model.onboarding.nights + 1)").font(
          .system(size: 68, weight: .heavy, design: .default)
        ).foregroundStyle(Theme.accent).contentTransition(.numericText())
        Text("days").font(.title2.weight(.bold))
      }
      Text(
        "\(CivilDate.display(model.onboarding.startsOn)) → \(CivilDate.display(CivilDate.adding(model.onboarding.nights, to: model.onboarding.startsOn))) · \(model.onboarding.nights) nights"
      ).font(.subheadline).foregroundStyle(Theme.secondary)
      ForEach(model.onboarding.stops.indices, id: \.self) { index in
        Card(padding: 16) {
          HStack {
            Text(model.onboarding.stops[index].flag).font(.title)
            VStack(alignment: .leading, spacing: 4) {
              Text(model.onboarding.stops[index].place).font(.headline)
              Text("\(model.onboarding.stops[index].nights) nights").font(.caption).foregroundStyle(
                Theme.secondary)
            }
            Spacer()
            Stepper(
              "Nights",
              value: Binding(
                get: { model.onboarding.stops[index].nights },
                set: { model.onboarding.stops[index].nights = $0 }), in: 1...30
            ).labelsHidden().accessibilityLabel("Nights in \(model.onboarding.stops[index].place)")
          }
        }
      }
    case 3:
      HStack {
        TextField("Their name", text: $personName).textFieldStyle(.roundedBorder).focused(
          $inputFocused
        ).onSubmit(
          addPerson)
        Button("Add", systemImage: "plus", action: addPerson).labelStyle(.iconOnly).buttonStyle(
          .borderedProminent
        ).frame(minWidth: 44, minHeight: 44).disabled(
          personName.trimmingCharacters(in: .whitespaces).isEmpty
            || model.onboarding.travellers.count >= 8)
      }
      LazyVGrid(columns: [.init(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
        ForEach(Array(model.onboarding.travellers.enumerated()), id: \.element.id) {
          index, person in
          HStack(spacing: 12) {
            Circle().fill(Theme.background).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 5) {
              Text(index == 0 ? "LEAD PASSENGER" : "PASSENGER").font(
                .system(size: 7, weight: .black)
              ).tracking(1)
              Text(person.name).font(.headline)
              Text("SEAT \(index + 1)\(index % 2 == 0 ? "A" : "B")").font(
                .system(size: 8, weight: .black, design: .monospaced))
            }
            Spacer(minLength: 0)
            if index > 0 {
              Button("Remove \(person.name)", systemImage: "xmark") {
                model.onboarding.travellers.removeAll { $0.id == person.id }
              }.labelStyle(.iconOnly).font(.caption2).frame(minWidth: 44, minHeight: 44)
            }
          }.foregroundStyle(Color(hue: person.hue / 360, saturation: 0.6, brightness: 0.4)).padding(
            13
          ).background(
            Color(hue: person.hue / 360, saturation: 0.18, brightness: 0.97),
            in: RoundedRectangle(cornerRadius: 10)
          ).rotationEffect(.degrees(index % 2 == 0 ? -2 : 2))
        }
      }
    case 4:
      LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
        ForEach(["GBP", "EUR", "USD", "AUD"], id: \.self) { currency in
          Button {
            model.onboarding.currency = currency
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              Text(["GBP": "🇬🇧", "EUR": "🇪🇺", "USD": "🇺🇸", "AUD": "🇦🇺"][currency] ?? "🌍").font(
                .largeTitle)
              Text(currency).font(.title2.weight(.heavy))
              Text(Locale.current.localizedString(forCurrencyCode: currency) ?? currency).font(
                .caption
              ).foregroundStyle(Theme.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(
              Theme.surface, in: RoundedRectangle(cornerRadius: 20)
            ).overlay(
              RoundedRectangle(cornerRadius: 20).stroke(
                model.onboarding.currency == currency ? Theme.accent : .clear, lineWidth: 2.5))
          }.buttonStyle(.plain)
        }
      }
      Picker(
        "Other currency",
        selection: Binding(
          get: { model.onboarding.currency }, set: { model.onboarding.currency = $0 })
      ) { ForEach(CurrencyMetadata.codes, id: \.self) { Text($0).tag($0) } }
    case 5:
      HStack {
        Text(model.onboarding.currency).font(.title3.weight(.bold)).foregroundStyle(Theme.secondary)
        TextField(
          "2400",
          text: Binding(get: { model.onboarding.budget }, set: { model.onboarding.budget = $0 })
        ).keyboardType(.decimalPad).focused($inputFocused).font(
          .system(size: 58, weight: .bold, design: .default)
        )
        .monospacedDigit()
      }
      if let budget = try? Money.parse(model.onboarding.budget, currency: model.onboarding.currency)
      {
        Text(
          "\(Money.format(budget / Int64(max(1, (model.onboarding.nights + 1) * model.onboarding.travellers.count)), model.onboarding.currency)) per person, per day"
        ).font(.subheadline).foregroundStyle(Theme.secondary)
      }
      Slider(
        value: Binding(
          get: { Double(model.onboarding.budget) ?? 0 },
          set: { model.onboarding.budget = String(Int($0)) }),
        in:
          100...Double(
            max(1000, (model.onboarding.nights + 1) * model.onboarding.travellers.count * 240)),
        step: 50)
      HStack {
        ForEach(
          Array(zip(["Shoestring", "Comfy", "Treat us", "Go big"], [30, 70, 135, 240])), id: \.0
        ) { label, amount in
          Button(label) {
            model.onboarding.budget = String(
              amount * (model.onboarding.nights + 1) * model.onboarding.travellers.count)
          }.font(.caption.weight(.bold)).padding(10).background(Theme.inset, in: Capsule())
        }
      }
      TextField(
        "Trip name (optional)",
        text: Binding(get: { model.onboarding.name }, set: { model.onboarding.name = $0 })
      ).textFieldStyle(.roundedBorder).focused($inputFocused)
    default:
      Text(greeting).font(.system(size: 42, weight: .heavy, design: .default)).foregroundStyle(
        Theme.accent)
      Text("\(model.onboarding.tripName) is all set.").font(.title3.weight(.semibold))
      Label("Saved on this device", systemImage: "checkmark.circle.fill").foregroundStyle(
        Theme.good)
    }
  }
  private var valid: Bool {
    switch model.onboarding.step {
    case 0: !model.onboarding.stops.isEmpty
    case 5:
      (try? Money.parse(model.onboarding.budget, currency: model.onboarding.currency)) ?? 0 > 0
    default: true
    }
  }
  private var searchQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var catalogueMatches: [Destination] {
    searchQuery.isEmpty ? Destination.suggestions : Destination.search(searchQuery, limit: 40)
  }
  private var routeSelection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Your route").font(.headline)
        Spacer()
        Text("\(model.onboarding.stops.count) of 6 stops").font(.caption)
          .foregroundStyle(Theme.secondary)
      }
      ScrollView(.horizontal) {
        HStack(spacing: 10) {
          if model.onboarding.stops.isEmpty {
            Label("Choose your first stop below", systemImage: "mappin.and.ellipse")
              .font(.subheadline).foregroundStyle(Theme.secondary)
              .padding(.horizontal, 16).frame(height: routeHeight)
          }
          ForEach(Array(model.onboarding.stops.enumerated()), id: \.element.id) { index, stop in
            HStack(spacing: 0) {
              Menu {
                Button("Move earlier", systemImage: "arrow.left") { moveStop(stop.id, by: -1) }
                  .disabled(index == 0)
                Button("Move later", systemImage: "arrow.right") { moveStop(stop.id, by: 1) }
                  .disabled(index == model.onboarding.stops.count - 1)
                Button("Visit again", systemImage: "plus") { repeatStop(stop) }
                  .disabled(model.onboarding.stops.count >= 6)
              } label: {
                HStack(spacing: 8) {
                  Text(stop.flag).font(.title2)
                  VStack(alignment: .leading, spacing: 4) {
                    Text("STOP \(index + 1)").font(.caption2.weight(.bold)).tracking(1)
                    Text(stop.place).font(.subheadline.weight(.bold)).lineLimit(2)
                  }
                  Image(systemName: "arrow.up.arrow.down").font(.caption)
                }.padding(.leading, 14).padding(.trailing, 8).frame(minHeight: 44)
              }.accessibilityLabel("Stop \(index + 1), \(stop.place)")
                .accessibilityHint("Move this stop or add another visit")
                .accessibilityIdentifier("onboarding.route.\(index).menu")
              Button {
                model.onboarding.stops.removeAll { $0.id == stop.id }
              } label: {
                Image(systemName: "xmark.circle.fill").font(.body)
                  .frame(width: 44, height: 44).contentShape(Rectangle())
              }.accessibilityLabel("Remove \(stop.place)")
                .accessibilityIdentifier("onboarding.route.\(index).remove")
            }.buttonStyle(.plain).foregroundStyle(Theme.accent)
              .frame(height: routeHeight)
              .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 16))
          }
        }
      }.scrollIndicators(.hidden).frame(height: routeHeight)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
  }
  private func destinationRow(_ destination: Destination) -> some View {
    let selected = isSelected(destination)
    return Button {
      selectDestination(destination)
    } label: {
      DestinationLabel(destination: destination, selected: selected)
        .padding(13).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(
          selected ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 15))
    }.buttonStyle(.plain)
      .disabled(model.onboarding.stops.count >= 6 && !selected)
      .accessibilityLabel(
        "\(destination.city), \(destination.secondaryLabel)\(selected ? ", added to your route" : "")"
      )
      .accessibilityHint(
        selected
          ? "Use its route menu to visit again" : "Adds a stop. Continue when your route is ready"
      )
      .accessibilityAddTraits(selected ? .isSelected : [])
      .accessibilityIdentifier("onboarding.destination.\(destination.id)")
  }
  private func isSelected(_ destination: Destination) -> Bool {
    model.onboarding.stops.contains {
      $0.countryCode == destination.countryCode
        && $0.place.compare(destination.city, options: [.caseInsensitive, .diacriticInsensitive])
          == .orderedSame
        && abs($0.latitude - destination.latitude) <= 0.0001
        && abs($0.longitude - destination.longitude) <= 0.0001
    }
  }
  private func selectDestination(_ destination: Destination) {
    inputFocused = false
    guard model.onboarding.stops.count < 6, !isSelected(destination) else { return }
    if destination.requiresCurrencySelection {
      inputFocused = false
      currencyDestination = destination
    } else {
      addDestination(destination)
    }
  }
  private func addDestination(_ destination: Destination) {
    guard model.onboarding.stops.count < 6, !isSelected(destination),
      CurrencyMetadata.codes.contains(destination.currency)
    else { return }
    // Keep the list in place: selection changes only this reserved route area and the row checkmark.
    model.onboarding.stops.append(destination.stop())
  }
  private func moveStop(_ id: String, by offset: Int) {
    guard let index = model.onboarding.stops.firstIndex(where: { $0.id == id }),
      model.onboarding.stops.indices.contains(index + offset)
    else { return }
    model.onboarding.stops.swapAt(index, index + offset)
  }
  private func repeatStop(_ stop: Stop) {
    guard model.onboarding.stops.count < 6 else { return }
    var repeated = stop
    repeated.id = UUID().uuidString
    model.onboarding.stops.append(repeated)
  }
  private func searchMaps() {
    let requested = searchQuery
    guard !requested.isEmpty, !destinationSearch.isSearching,
      model.onboarding.stops.count < 6
    else { return }
    inputFocused = false
    searchedMapQuery = requested
    Task { await destinationSearch.searchMaps(requested) }
  }
  private var cheer: String {
    switch model.onboarding.step {
    case 0:
      model.onboarding.stops.isEmpty
        ? "Every adventure starts somewhere."
        : "\(model.onboarding.stops.count) stop\(model.onboarding.stops.count == 1 ? "" : "s"). Lovely choice."
    case 2:
      model.onboarding.nights < 6
        ? "Short and sweet."
        : model.onboarding.nights < 14 ? "A good long trip." : "A proper adventure."
    case 3:
      model.onboarding.travellers.count == 1
        ? "Solo trip. Respect."
        : model.onboarding.travellers.count == 2
          ? "Just the two of you." : "Party of \(model.onboarding.travellers.count)!"
    case 4: "Everything comes home to \(model.onboarding.currency)."
    case 5: "Room for memories."
    default: "Let’s make it a good one."
    }
  }
  private var greeting: String {
    [
      "PT": "Boa viagem!", "ES": "¡Buen viaje!", "FR": "Bon voyage!", "IT": "Buon viaggio!",
      "JP": "Itterasshai!",
    ][model.onboarding.stops.first?.countryCode ?? ""] ?? "Happy travels!"
  }
  private func addPerson() {
    let name = personName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty, model.onboarding.travellers.count < 8 else { return }
    let hues: [Double] = [350, 250, 75, 160, 300, 30, 200, 120]
    model.onboarding.travellers.append(
      Traveller(name: name, hue: hues[model.onboarding.travellers.count]))
    personName = ""
  }
  private func advance() {
    guard valid else { return }
    inputFocused = false
    if model.onboarding.step == 5 {
      model.perform { _ = try model.createTrip() }
    } else if model.onboarding.step == 6 {
      model.finishOnboarding(planTravel: true)
    } else {
      animate { model.onboarding.step += 1 }
    }
    model.saveOnboarding()
  }
  private func goBack() {
    guard model.onboarding.step > 0, model.onboarding.step < 6 else { return }
    inputFocused = false
    animate { model.onboarding.step -= 1 }
    model.saveOnboarding()
  }
  private func animate(_ action: () -> Void) {
    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.9), action)
  }
}

private struct DestinationLabel: View {
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

private struct DestinationCurrencyPicker: View {
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

private struct DestinationCurrencySheet: View {
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
        } footer: {
          Text("Your home currency and whole-trip budget come later.")
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
    }.tint(Theme.accent)
  }
}

private struct CustomDestinationSheet: View {
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
            "Find the real location, then choose a result below. Apple Maps needs an internet connection."
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
    }.tint(Theme.accent)
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
