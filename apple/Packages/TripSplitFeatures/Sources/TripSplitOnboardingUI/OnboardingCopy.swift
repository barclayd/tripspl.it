import Foundation
import TripSplitDesignSystem
import TripSplitDomain

/// The words and derived figures that react to each onboarding answer.
enum OnboardingCopy {
  /// The encouraging line above the continue button.
  static func cheer(_ draft: OnboardingDraft) -> String {
    switch draft.step {
    case 0:
      switch draft.stops.count {
      case 0: return ""
      case 1: return "\(draft.stops[0].flag) \(draft.stops[0].place). Lovely choice."
      case 2: return "Two stops. Nice route."
      case let count: return "\(count) stops. Ambitious!"
      }
    case 8:
      return draft.origin.map { "Leaving from \($0.flag) \($0.place)" } ?? ""
    case 1:
      guard draft.hasDates else {
        return draft.isPickingHome ? "Now the day you’re home" : "Tap the day you set off"
      }
      if draft.nights == 0 { return "A day trip. Easy." }
      return draft.nights >= 14
        ? "A proper adventure" : draft.nights >= 6 ? "A good long trip" : "Short and sweet"
    case 2:
      return "\(draft.nights) nights across \(draft.stops.count) places"
    case 3:
      switch draft.travellers.count {
      case 1: return "Solo trip. Respect."
      case 2: return "Just the two of you"
      case let count: return "Party of \(count)!"
      }
    case 4:
      return draft.stops.allSatisfy { $0.currency == draft.currency }
        ? "No conversion needed" : "Currency data updated daily"
    default:
      return ""
    }
  }

  /// One flag per country visited, in route order, for the confetti.
  static func flags(_ draft: OnboardingDraft) -> [String] {
    unique(draft.stops.map(\.flag))
  }

  /// "Bon voyage!" in the language of the first stop.
  static func greeting(countryCode: String?) -> String {
    Greeting.departure(countryCode: countryCode)
  }

  /// The budget per person per day in pounds, so spending bands mean the same in any currency.
  static func dailySpendGBP(_ draft: OnboardingDraft, homePerGBP: Double?) -> Double? {
    guard let homePerGBP, homePerGBP > 0, let budget = budgetMajor(draft), budget > 0 else {
      return nil
    }
    return budget / homePerGBP / Double(max(draft.travellers.count, 1)) / Double(draft.days)
  }

  /// The boarding pass's travel class, from how lavish the daily budget is.
  static func travelClass(_ draft: OnboardingDraft, homePerGBP: Double?) -> String? {
    dailySpendGBP(draft, homePerGBP: homePerGBP).map { daily in
      daily < 45 ? "ECONOMY" : daily < 95 ? "PREMIUM" : daily < 180 ? "BUSINESS" : "FIRST"
    }
  }

  /// "£76" a head each day, in the home currency, or nil before a budget is set.
  static func dailySpendPerPerson(_ draft: OnboardingDraft) -> String? {
    guard let budget = budgetMajor(draft), budget > 0 else { return nil }
    let daily = budget / Double(max(draft.travellers.count, 1)) / Double(draft.days)
    let minor = Int64(daily.rounded()) * Money.factor(draft.currency)
    return Money.format(minor, draft.currency, compact: true)
  }

  static func budgetMajor(_ draft: OnboardingDraft) -> Double? {
    guard let minor = try? Money.parse(draft.budget, currency: draft.currency) else { return nil }
    return Double(minor) / Double(Money.factor(draft.currency))
  }

  // MARK: Open Duo

  /// Each question, as the open Duo's sidebar lists them.
  static func stepTitle(_ step: Int) -> String {
    switch step {
    case 0: "Where"
    case 8: "Leaving from"
    case 1: "When"
    case 2: "How long"
    case 3: "Who"
    case 4: "Home currency"
    default: "Budget"
    }
  }

  /// Each answered step in a line, e.g. "🇵🇹 Portugal → 🇪🇸 Spain" or "7 nights · 8 days".
  static func answer(_ step: Int, _ draft: OnboardingDraft) -> String {
    switch step {
    case 0: return draft.stops.map { "\($0.flag) \($0.place)" }.joined(separator: " → ")
    case 8: return draft.origin.map { "\($0.flag) \($0.place)" } ?? ""
    case 1:
      guard draft.hasDates else { return "" }
      return "\(dateRange(draft)) · \(draft.days) day\(draft.days == 1 ? "" : "s")"
    case 2:
      return draft.stops.map { "\($0.flag) \($0.nights)" }.joined(separator: " · ")
    case 3: return draft.travellers.map(\.name).joined(separator: ", ")
    case 4: return "\(ConversionCurrency.forCurrency(draft.currency).flag) \(draft.currency)"
    case 5: return Money.typed(draft.budget, currency: draft.currency)
    default: return ""
    }
  }

  /// "18 – 25 Nov", or "28 Nov – 5 Dec" across months.
  static func dateRange(_ draft: OnboardingDraft) -> String {
    let start = draft.startsOn
    let end = draft.returnDate
    let sameMonth = start.prefix(7) == end.prefix(7)
    return "\(CivilDate.display(start, format: sameMonth ? "d" : "d MMM")) – \(CivilDate.display(end))"
  }

  /// Every country once, in route order: "Portugal & Spain".
  static func countries(_ draft: OnboardingDraft) -> String {
    let names = unique(draft.stops.map(\.countryCode)).map {
      CountryMetadata.country($0)?.name ?? $0
    }
    guard names.count > 1 else { return names.first ?? "" }
    return names.dropLast().joined(separator: ", ") + " & " + names[names.count - 1]
  }

  /// The pass as the answers stand, tinting whichever field the current step fills in. It leaves
  /// from the picked origin, or the region's leading city until there is one.
  static func tripPass(
    _ draft: OnboardingDraft, size: TripPass.Size,
    region: String? = Locale.current.region?.identifier
  ) -> TripPassContent {
    let home = draft.origin ?? Destination.home(region: region)?.origin
    let codes = unique(draft.stops.map(\.countryCode))
    let to =
      switch draft.stops.count {
      case 0: "???"
      case 1: draft.stops[0].passCode
      default: codes.joined(separator: "·")
      }
    let toName =
      switch draft.stops.count {
      case 0: "Where to?"
      case 1: draft.stops[0].place
      default: size == .full ? countries(draft) : "\(draft.stops.count) stops"
      }
    let budgetAnswered = draft.reached(5) && !draft.budget.isEmpty
    let dated = draft.reached(1) && draft.hasDates
    let highlight: BoardingPassContent.Highlight? =
      switch draft.step {
      case 0, 8: .destination
      case 1, 2: .field(1)
      case 3: .field(2)
      case 5: .field(3)
      default: nil
      }
    return TripPassContent(
      from: home?.passCode ?? "HOME", fromName: home?.place ?? "Home", to: to, toName: toName,
      placeholder: draft.stops.isEmpty,
      date: .init(dated ? dateRange(draft) : "When?", answered: dated),
      pax: .init(
        "\(draft.travellers.count)", answered: draft.reached(4) || draft.travellers.count > 1),
      budget: .init(
        budgetAnswered ? Money.typed(draft.budget, currency: draft.currency) : "Budget?",
        answered: budgetAnswered),
      flags: unique(draft.stops.map(\.flag)).joined(),
      highlight: highlight)
  }

  /// The finished trip in a line: "Portugal & Spain · 18 – 25 Nov · 3 people".
  static func summary(_ draft: OnboardingDraft) -> String {
    let people = draft.travellers.count
    return "\(countries(draft)) · \(dateRange(draft)) · \(people) \(people == 1 ? "person" : "people")"
  }

  /// Each traveller's share of the budget, in whole units: "£700".
  static func share(_ draft: OnboardingDraft) -> String? {
    guard let budget = budgetMajor(draft), budget > 0 else { return nil }
    let each = (budget / Double(max(draft.travellers.count, 1))).rounded()
    return Money.format(Int64(each) * Money.factor(draft.currency), draft.currency, compact: true)
  }

  private static func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }
}
