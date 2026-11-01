import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain

/// Step 5: the currency every expense converts back into.
struct HomeCurrencyStep: View {
  @Environment(AppModel.self) private var model

  private static let featured: [(code: String, name: String, flag: String)] = [
    ("GBP", "British pound", "🇬🇧"), ("EUR", "Euro", "🇪🇺"), ("USD", "US dollar", "🇺🇸"),
    ("AUD", "Australian dollar", "🇦🇺"),
  ]

  private var draft: OnboardingDraft { model.onboarding }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      StepTitle(
        "What’s your home currency?",
        "We convert every expense back to this, so the total is always real.")
      LazyVGrid(
        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
        spacing: 12
      ) {
        ForEach(Self.featured, id: \.code) { currency in
          card(currency.code, name: currency.name, flag: currency.flag)
        }
      }
      Menu {
        Picker("Other currency", selection: Binding(get: { draft.currency }, set: choose)) {
          ForEach(CurrencyMetadata.codes, id: \.self) { code in
            Text(Locale.current.localizedString(forCurrencyCode: code).map { "\(code) · \($0)" } ?? code)
              .tag(code)
          }
        }
      } label: {
        HStack(spacing: 8) {
          Text("Other currency").typeface(15, .heavy, relativeTo: .subheadline, maximum: 1.4)
          Spacer()
          if !Self.featured.contains(where: { $0.code == draft.currency }) {
            Text(draft.currency).typeface(15, .black, relativeTo: .subheadline, maximum: 1.4)
              .foregroundStyle(Theme.accentText)
          }
          Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .bold))
            .foregroundStyle(Theme.tertiary)
        }
        .foregroundStyle(Theme.ink).padding(.horizontal, 16).frame(minHeight: 50)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.key))
      }
      .accessibilityIdentifier("onboarding.otherCurrency")
    }
  }

  private func card(_ code: String, name: String, flag: String) -> some View {
    let selected = draft.currency == code
    return Button {
      choose(code)
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        Text(flag).font(.system(size: 32)).padding(.bottom, 4).accessibilityHidden(true)
        Text(code).typeface(19, .black, relativeTo: .title3, maximum: 1.3)
          .foregroundStyle(Theme.ink)
        Text(name).typeface(13, .semibold, relativeTo: .footnote, maximum: 1.4)
          .foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
        if let rate = rateLine(for: code) {
          Text(rate).typeface(12.5, .heavy, relativeTo: .caption, maximum: 1.4)
            .foregroundStyle(Theme.accentText).lineLimit(1).minimumScaleFactor(0.8)
            .padding(.top, 2)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading).padding(14)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
      .overlay {
        RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.accent, lineWidth: selected ? 2.5 : 0)
      }
      .scaleEffect(selected ? 1.03 : 1)
      .animation(Motion.bump, value: selected)
    }
    .buttonStyle(PressStyle())
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("onboarding.currency.\(code)")
  }

  /// "€1 = £0.86" from the first stop's currency, or ¥1,000 for currencies without decimals.
  private func rateLine(for code: String) -> String? {
    guard let trip = draft.stops.first?.currency else { return nil }
    if trip == code { return "Same as your trip" }
    guard let rate = model.indicativeRate(from: trip, to: code) else { return nil }
    let units: Int64 = Money.precision(trip) == 0 ? 1000 : 1
    let converted = Double(units) * rate * Double(Money.factor(code))
    return
      "\(Money.format(units * Money.factor(trip), trip, compact: true)) = \(Money.format(Int64(converted.rounded()), code))"
  }

  private func choose(_ code: String) {
    guard draft.currency != code else { return }
    Haptics.selection()
    withAnimation(Motion.bump) {
      model.onboarding.currency = code
      model.onboarding.budget = ""
    }
  }
}

/// Step 6: the trip's total budget, typed or picked by vibe.
struct BudgetStep: View {
  let focus: FocusState<Bool>.Binding
  @Environment(AppModel.self) private var model
  @Environment(\.onboardingWide) private var wide

  private static let vibes: [(name: String, short: String, dailyGBP: Double)] = [
    ("Shoestring", "Shoestring", 30), ("Comfy", "Comfy", 70),
    ("Treat yourselves", "Treat", 135), ("Go big", "Splurge", 240),
  ]

  private var draft: OnboardingDraft { model.onboarding }
  private var homePerGBP: Double? { model.indicativeRate(from: "GBP", to: draft.currency) }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      StepTitle("What’s the budget?", "For the whole trip, everyone included.")
      if wide {
        card
        if let homePerGBP { presets(homePerGBP) }
      } else {
        compact
      }
      TextField(
        "Trip name (optional)", text: Binding(get: { draft.name }, set: { model.onboarding.name = $0 }),
        prompt: Text(draft.tripName.isEmpty ? "Trip name (optional)" : "\(draft.tripName) (optional)")
      )
      .typeface(16, .bold, relativeTo: .body, maximum: 1.4).foregroundStyle(Theme.ink)
      .focused(focus).textInputAutocapitalization(.words).submitLabel(.done)
      .padding(.vertical, 14).padding(.horizontal, 16)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.key))
      .accessibilityLabel("Trip name").accessibilityIdentifier("onboarding.tripName")
      .padding(.top, 6)
    }
    .animation(Motion.bump, value: draft.budget)
  }

  @ViewBuilder private var compact: some View {
    amount(size: 66, alignment: .center)
    Text(
      OnboardingCopy.dailySpendPerPerson(draft).map { "\($0) per person, per day" }
        ?? "Type a total, or pick a vibe"
    )
    .typeface(15, .bold, relativeTo: .subheadline, maximum: 1.4).foregroundStyle(Theme.secondary)
    .frame(maxWidth: .infinity).contentTransition(.numericText())
    if let homePerGBP {
      slider(homePerGBP)
      vibes(homePerGBP)
    }
  }

  /// The open Duo's budget: the total and the per-day figure side by side, over the slider.
  private var card: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .bottom, spacing: 12) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Total budget").typeface(13, .heavy, relativeTo: .footnote, maximum: 1.3)
            .foregroundStyle(Theme.secondary)
          amount(size: 48, alignment: .leading)
        }
        Spacer(minLength: 0)
        VStack(alignment: .trailing, spacing: 0) {
          Text(OnboardingCopy.dailySpendPerPerson(draft) ?? "—")
            .typeface(17, .heavy, relativeTo: .headline, maximum: 1.3).foregroundStyle(Theme.ink)
            .contentTransition(.numericText())
          Text("per person, per day").typeface(13, .bold, relativeTo: .footnote, maximum: 1.3)
            .foregroundStyle(Theme.secondary)
        }
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
      }
      if let homePerGBP {
        slider(homePerGBP)
        let bounds = sliderBounds(homePerGBP)
        HStack {
          Text(Money.typed("100", currency: draft.currency))
          Spacer()
          Text("Suggested \(Money.typed(String(bounds.suggested), currency: draft.currency))")
          Spacer()
          Text(Money.typed(String(bounds.upper), currency: draft.currency))
        }
        .typeface(12, .bold, relativeTo: .caption, maximum: 1.3).foregroundStyle(Theme.tertiary)
        .monospacedDigit().accessibilityHidden(true)
      }
    }
    .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 12)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
  }

  private func amount(size: CGFloat, alignment: Alignment) -> some View {
    ZStack(alignment: alignment) {
      Text(Money.typed(draft.budget.isEmpty ? "0" : draft.budget, currency: draft.currency))
        .typeface(size, .heavy, tracking: -0.04, relativeTo: .largeTitle, maximum: 1.1)
        .monospacedDigit().foregroundStyle(draft.budget.isEmpty ? Theme.tertiary : Theme.ink)
        .lineLimit(1).minimumScaleFactor(0.4)
        .contentTransition(.numericText())
        .accessibilityHidden(true)
      TextField(
        "", text: Binding(get: { draft.budget }, set: { model.onboarding.budget = sanitised($0) })
      )
      .keyboardType(.decimalPad).focused(focus)
      .foregroundStyle(.clear).tint(.clear).multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityLabel("Trip budget")
      .accessibilityValue(
        draft.budget.isEmpty ? "Empty" : Money.typed(draft.budget, currency: draft.currency))
      .accessibilityIdentifier("onboarding.budget")
    }
    .frame(maxWidth: .infinity, alignment: alignment).padding(.vertical, alignment == .center ? 6 : 0)
    .overlay(alignment: alignment == .center ? .bottom : .bottomLeading) {
      Capsule().fill(Theme.accent).frame(width: focus.wrappedValue ? 120 : 0, height: 3)
        .animation(Motion.spring, value: focus.wrappedValue)
    }
  }

  private func sliderBounds(_ homePerGBP: Double) -> (suggested: Int, upper: Int) {
    let suggested = draft.suggestedBudget(homePerGBP: homePerGBP)
    let upper = max(150, (max(Double(suggested) * 3, 1000) / 50).rounded() * 50)
    return (suggested, Int(upper))
  }

  private func slider(_ homePerGBP: Double) -> some View {
    let upper = Double(sliderBounds(homePerGBP).upper)
    return Slider(
      value: Binding(
        get: { min(max(OnboardingCopy.budgetMajor(draft) ?? 100, 100), upper) },
        set: { model.onboarding.budget = String(Int(($0 / 50).rounded()) * 50) }),
      in: 100...upper
    ) {
      Text("Budget")
    } onEditingChanged: { editing in
      if editing { focus.wrappedValue = false }
    }
    .tint(Theme.accent)
    .accessibilityValue(Money.typed(draft.budget, currency: draft.currency))
    .accessibilityIdentifier("onboarding.budgetSlider")
  }

  private func selectedVibe(_ homePerGBP: Double) -> Int? {
    OnboardingCopy.dailySpendGBP(draft, homePerGBP: homePerGBP).map { daily in
      daily < 45 ? 0 : daily < 95 ? 1 : daily < 180 ? 2 : 3
    }
  }

  /// A vibe's daily spend for everyone, for every day, rounded to 50.
  private func total(_ index: Int, _ homePerGBP: Double) -> Int {
    let total =
      Self.vibes[index].dailyGBP * homePerGBP * Double(max(draft.travellers.count, 1))
      * Double(draft.days)
    return max(50, Int((total / 50).rounded()) * 50)
  }

  private func pick(_ index: Int, _ homePerGBP: Double) {
    focus.wrappedValue = false
    Haptics.selection()
    model.onboarding.budget = String(total(index, homePerGBP))
  }

  /// The open Duo's presets, each showing the total it would set.
  private func presets(_ homePerGBP: Double) -> some View {
    let selected = selectedVibe(homePerGBP)
    return HStack(spacing: 8) {
      ForEach(Self.vibes.indices, id: \.self) { index in
        let isSelected = selected == index
        Button {
          pick(index, homePerGBP)
        } label: {
          VStack(spacing: 2) {
            Text(Self.vibes[index].short).typeface(14, .heavy, relativeTo: .subheadline, maximum: 1.3)
              .foregroundStyle(isSelected ? Theme.accentText : Theme.ink)
            Text(Money.typed(String(total(index, homePerGBP)), currency: draft.currency))
              .typeface(13, .bold, relativeTo: .footnote, maximum: 1.3).monospacedDigit()
              .foregroundStyle(isSelected ? Theme.accentText : Theme.secondary)
          }
          .lineLimit(1).minimumScaleFactor(0.8)
          .padding(.vertical, 10).padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 52)
          .background(
            isSelected ? Theme.accentSoft : Theme.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.key)
          )
          .overlay {
            if isSelected {
              RoundedRectangle(cornerRadius: Theme.Radius.key).strokeBorder(Theme.accent, lineWidth: 2)
            }
          }
        }
        .buttonStyle(PressStyle(scale: 0.95))
        .animation(Motion.bump, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("onboarding.vibe.\(index)")
      }
    }
  }

  private func vibes(_ homePerGBP: Double) -> some View {
    let selected = selectedVibe(homePerGBP)
    return HStack(spacing: 8) {
      ForEach(Self.vibes.indices, id: \.self) { index in
        let vibe = Self.vibes[index]
        let isSelected = selected == index
        Button {
          pick(index, homePerGBP)
        } label: {
          Text(vibe.name).typeface(12, .heavy, relativeTo: .caption, maximum: 1.3)
            .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
            .foregroundStyle(isSelected ? Theme.accentInk : Theme.secondary)
            .padding(.vertical, 10).padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
              isSelected ? Theme.accent : Theme.surface,
              in: RoundedRectangle(cornerRadius: Theme.Radius.key))
            .scaleEffect(isSelected ? 1.06 : 1)
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .animation(Motion.bump, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("onboarding.vibe.\(index)")
      }
    }
  }

  /// Digits with at most one decimal point and the currency's decimal places.
  private func sanitised(_ text: String) -> String {
    let precision = Money.precision(draft.currency)
    var whole = ""
    var fraction: String?
    for character in text {
      if character.isASCII, character.isNumber {
        if fraction != nil {
          if fraction!.count < precision { fraction!.append(character) }
        } else if whole.count < 9 {
          whole.append(character)
        }
      } else if character == "." || character == ",", precision > 0, fraction == nil {
        fraction = ""
      }
    }
    whole = String(whole.drop { $0 == "0" })
    guard let fraction else { return whole }
    return (whole.isEmpty ? "0" : whole) + "." + fraction
  }
}

/// Step 7: a local farewell while the finished pass bobs above.
struct BonVoyageStep: View {
  @Environment(AppModel.self) private var model
  @Environment(\.onboardingWide) private var wide

  var body: some View {
    if wide { summary } else { farewell }
  }

  /// The open Duo has the steps beside it, so this sums up the trip in a line and two chips.
  private var summary: some View {
    let draft = model.onboarding
    return VStack(spacing: 10) {
      Text(OnboardingCopy.greeting(countryCode: draft.stops.first?.countryCode))
        .typeface(52, .black, tracking: -0.04, relativeTo: .largeTitle, maximum: 1.2)
        .foregroundStyle(Theme.ink).multilineTextAlignment(.center)
        .popIn(delay: 0.1)
      Text(OnboardingCopy.summary(draft))
        .typeface(16, .bold, relativeTo: .body, maximum: 1.4)
        .foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
        .rise(delay: 0.2)
      HStack(spacing: 8) {
        if !draft.budget.isEmpty {
          chip("\(Money.typed(draft.budget, currency: draft.currency)) budget")
        }
        if let share = OnboardingCopy.share(draft), draft.travellers.count > 1 {
          chip("\(share) each")
        }
      }
      .rise(delay: 0.3)
    }
    .frame(maxWidth: .infinity).padding(.top, 4)
    .accessibilityElement(children: .combine)
  }

  private func chip(_ text: String) -> some View {
    Text(text).typeface(14, .heavy, relativeTo: .subheadline, maximum: 1.3)
      .foregroundStyle(Theme.ink).padding(.vertical, 7).padding(.horizontal, 14)
      .background(Theme.surface, in: Capsule())
  }

  private var farewell: some View {
    VStack(spacing: 12) {
      Text(OnboardingCopy.greeting(countryCode: model.onboarding.stops.first?.countryCode))
        .typeface(42, .black, tracking: -0.03, relativeTo: .largeTitle, maximum: 1.2)
        .foregroundStyle(Theme.accentText).multilineTextAlignment(.center)
        .popIn(delay: 0.1)
      Text("\(model.onboarding.tripName) is all set. Next, add how you’re getting there.")
        .typeface(16, .semibold, relativeTo: .body, maximum: 1.4)
        .foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .rise(delay: 0.25)
    }
    .frame(maxWidth: .infinity).padding(.top, 12)
    .accessibilityElement(children: .combine)
  }
}
