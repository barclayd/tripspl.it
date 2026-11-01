import Foundation
import TripSplitDomain

/// The words and derived figures that react to each onboarding answer.
enum OnboardingCopy {
  /// The encouraging line above the continue button.
  static func cheer(
    _ draft: OnboardingDraft, today: String = CivilDate.today(timeZone: TimeZone.current.identifier)
  ) -> String {
    switch draft.step {
    case 0:
      switch draft.stops.count {
      case 0: return ""
      case 1: return "\(draft.stops[0].flag) \(draft.stops[0].place). Lovely choice."
      case 2: return "Two stops. Nice route."
      case let count: return "\(count) stops. Ambitious!"
      }
    case 1:
      let days = CivilDate.days(from: today, to: draft.startsOn)
      if days == 0 { return "Leaving today!" }
      if days > 0 { return "That’s \(days) day\(days == 1 ? "" : "s") away" }
      return "Started \(-days) day\(days == -1 ? "" : "s") ago"
    case 2:
      return draft.nights >= 14
        ? "A proper adventure" : draft.nights >= 6 ? "A good long trip" : "Short and sweet"
    case 3:
      switch draft.travellers.count {
      case 1: return "Solo trip. Respect."
      case 2: return "Just the two of you"
      case let count: return "Party of \(count)!"
      }
    case 4:
      let foreign = unique(draft.stops.map(\.currency)).filter { $0 != draft.currency }
      return foreign.isEmpty
        ? "No conversion needed"
        : "We’ll convert \(foreign.joined(separator: " & ")) into \(draft.currency)"
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
    switch countryCode {
    case "PT": "Boa viagem!"
    case "ES", "MX": "¡Buen viaje!"
    case "IT": "Buon viaggio!"
    case "GR": "Kaló taxídi!"
    case "HR": "Sretan put!"
    case "CH", "DE", "AT": "Gute Reise!"
    case "IS": "Góða ferð!"
    case "JP": "Itterasshai!"
    case "TH": "Tiao hai sanuk!"
    case "VN": "Thượng lộ bình an!"
    case "ID": "Selamat jalan!"
    case "US": "Have a great trip!"
    case "MA": "Bslama!"
    case "AU": "Have a ripper trip!"
    default: "Bon voyage!"
    }
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

  private static func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }
}
