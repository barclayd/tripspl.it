import MapKit
import SwiftUI

struct OnboardingView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var query = ""
  @State private var personName = ""
  @State private var customCity = ""
  @State private var customCountry = "GB"
  @State private var customCurrency = "GBP"
  @State private var custom = false
  @State private var customError: String?
  @State private var searching = false
  @FocusState private var inputFocused: Bool
  private let titles = [
    "Where are you off to?", "When do you leave?", "How long in each place?", "Who’s coming?",
    "What’s your home currency?", "What’s the budget?", "You’re all set.",
  ]
  private let subtitles = [
    "Add each country in the order you’ll visit.", "Pick the day you set off.",
    "A little stopover or a long, slow stay?", "Everyone who’ll be splitting costs.",
    "One currency for the honest, whole-trip total.", "For the whole trip, everyone included.",
    "Next, add how you’re getting there.",
  ]
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ProgressView(value: Double(model.onboarding.step + 1), total: 7).tint(Theme.accent)
          .scaleEffect(y: 2).padding(.horizontal, 24).padding(.vertical, 12)
        ScrollViewReader { scroll in
          ScrollView {
            VStack(alignment: .leading, spacing: 24) {
              if let trip = try? model.onboarding.makeTrip() {
                BoardingPassStack(trip: trip, cleared: model.onboarding.step == 6)
              }
              VStack(alignment: .leading, spacing: 8) {
                Text(titles[model.onboarding.step]).font(
                  .system(size: 32, weight: .heavy, design: .default)
                ).tracking(-1)
                Text(subtitles[model.onboarding.step]).font(.subheadline).foregroundStyle(
                  Theme.secondary
                ).lineSpacing(3)
              }
              step
            }.pagePadding().padding(.bottom, 20).id("onboarding-top")
          }.onChange(of: model.onboarding.step) { _, _ in
            inputFocused = false
            scroll.scrollTo("onboarding-top", anchor: .top)
          }
        }
        VStack(spacing: 12) {
          Text(cheer).font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
          PrimaryButton(
            title: model.onboarding.step == 5
              ? "Create trip" : model.onboarding.step == 6 ? "Plan getting there" : "Continue",
            symbol: model.onboarding.step == 6 ? "airplane" : "arrow.right"
          ) { advance() }.disabled(!valid).opacity(valid ? 1 : 0.45)
          if model.onboarding.step == 6 {
            Button("Go to trip") { model.finishOnboarding(planTravel: false) }.font(
              .subheadline.weight(.semibold))
          }
        }.padding(20).background(Theme.background)
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
          ToolbarItem {
            if model.onboarding.step > 0 && model.onboarding.step < 6 {
              Button("Back", systemImage: "chevron.backward") {
                animate { model.onboarding.step -= 1 }
                model.saveOnboarding()
              }
            }
          }
        }
        .onChange(of: model.onboarding) { _, _ in model.saveOnboarding() }
        .sheet(isPresented: $custom) { customStop }
    }
  }
  @ViewBuilder private var step: some View {
    switch model.onboarding.step {
    case 0:
      TextField("Search country or city", text: $query).textFieldStyle(.roundedBorder).focused(
        $inputFocused)
      if !model.onboarding.stops.isEmpty {
        ScrollView(.horizontal) {
          HStack {
            ForEach(model.onboarding.stops) { stop in
              Button {
                model.onboarding.stops.removeAll { $0.id == stop.id }
              } label: {
                Label("\(stop.flag) \(stop.place)", systemImage: "xmark.circle.fill").font(
                  .caption.weight(.bold)
                ).padding(10).background(Theme.accentSoft, in: Capsule())
              }
            }
          }
        }
      }
      LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
        ForEach(
          Destination.all.filter {
            query.isEmpty || $0.country.localizedCaseInsensitiveContains(query)
              || $0.city.localizedCaseInsensitiveContains(query)
          }
        ) { destination in
          Button {
            if model.onboarding.stops.count < 6 {
              animate { model.onboarding.stops.append(destination.stop()) }
            }
          } label: {
            HStack(spacing: 8) {
              Text(destination.flag).font(.title2)
              VStack(alignment: .leading, spacing: 2) {
                Text(destination.city).font(.subheadline.weight(.heavy))
                Text(destination.country).font(.caption2).foregroundStyle(Theme.secondary)
              }
              Spacer(minLength: 0)
            }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(
              Theme.surface, in: RoundedRectangle(cornerRadius: 15))
          }.buttonStyle(.plain)
        }
      }
      Button("Add another destination", systemImage: "mappin.and.ellipse") { custom = true }
        .disabled(model.onboarding.stops.count >= 6)
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
        ).disabled(
          personName.trimmingCharacters(in: .whitespaces).isEmpty
            || model.onboarding.travellers.count >= 8)
      }
      LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
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
              }.labelStyle(.iconOnly).font(.caption2)
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
  private func animate(_ action: () -> Void) {
    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.9), action)
  }
  private var customStop: some View {
    NavigationStack {
      Form {
        TextField("City or place", text: $customCity)
        Picker("Country", selection: $customCountry) {
          ForEach(
            Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 }.sorted(), id: \.self
          ) {
            Text("\($0.flag) \(Locale.current.localizedString(forRegionCode: $0) ?? $0)").tag($0)
          }
        }
        Picker("Currency", selection: $customCurrency) {
          ForEach(CurrencyMetadata.codes, id: \.self) { Text($0).tag($0) }
        }
        Text(
          "Find the destination with Apple Maps so your globe pin uses its real location. An internet connection is needed."
        ).font(.footnote)
        if let customError { Text(customError).foregroundStyle(Theme.bad) }
      }.navigationTitle("Another stop").toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark") { custom = false }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Find & add stop", systemImage: "checkmark") { findCustomStop() }.disabled(
            searching || customCity.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
    }
  }
  private func findCustomStop() {
    searching = true
    Task {
      defer { searching = false }
      do {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery =
          customCity + ", "
          + (Locale.current.localizedString(forRegionCode: customCountry) ?? customCountry)
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else {
          throw ServiceError(
            code: "place",
            message: "No location found. Try a nearby city or a more specific place name.")
        }
        model.onboarding.stops.append(
          .init(
            countryCode: customCountry, place: customCity.trimmingCharacters(in: .whitespaces),
            nights: 3, currency: customCurrency, latitude: item.location.coordinate.latitude,
            longitude: item.location.coordinate.longitude))
        custom = false
        customError = nil
      } catch { customError = error.localizedDescription }
    }
  }
}
