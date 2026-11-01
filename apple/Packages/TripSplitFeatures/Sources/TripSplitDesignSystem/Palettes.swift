import SwiftUI
import TripSplitDomain

/// Traveller avatar colours from a hue in degrees.
package struct AvatarPalette {
  /// Hues assigned to travellers in order, starting with you.
  package static let hues: [Double] = [350, 250, 75, 160, 300, 30, 200, 120, 330]

  package static func hue(at index: Int) -> Double { hues[index % hues.count] }

  package init(hue: Double) {
    background = Color(light: OKLCH(0.87, 0.08, hue), dark: OKLCH(0.42, 0.1, hue))
    foreground = Color(light: OKLCH(0.36, 0.13, hue), dark: OKLCH(0.94, 0.05, hue))
  }
  package let background: Color
  package let foreground: Color
}

/// Spending groups used by the category breakdown bar.
package enum SpendGroup: String, CaseIterable, Sendable {
  case travel, stay, food, fun, shop, other

  package var title: String {
    switch self {
    case .travel: "Travel"
    case .stay: "Stays"
    case .food: "Food & drink"
    case .fun: "Things to do"
    case .shop: "Shopping"
    case .other: "Other"
    }
  }

  package var hue: Double {
    switch self {
    case .travel: 250
    case .stay: 300
    case .food: 55
    case .fun: 190
    case .shop: 345
    case .other: 20
    }
  }

  package var color: Color { OKLCH(0.72, 0.14, hue).color }
}

extension ExpenseCategory {
  /// Categories offered for a day.
  package static let dayCategories: [ExpenseCategory] = [
    .food, .coffee, .stay, .activity, .transport, .shopping, .other,
  ]
  /// Categories offered for a travel leg.
  package static let travelCategories: [ExpenseCategory] = [
    .flight, .train, .taxi, .transport, .other,
  ]

  /// Hue in degrees, as authored in the design.
  package var degreeHue: Double {
    switch self {
    case .food: 45
    case .coffee: 65
    case .stay: 300
    case .activity: 195
    case .transport: 255
    case .shopping: 345
    case .flight: 235
    case .train: 160
    case .taxi: 90
    case .other: 20
    }
  }

  package var group: SpendGroup {
    switch self {
    case .food, .coffee: .food
    case .stay: .stay
    case .activity: .fun
    case .transport, .flight, .train, .taxi: .travel
    case .shopping: .shop
    case .other: .other
    }
  }

  /// SF Symbol closest to the design's outline glyph.
  package var glyph: String {
    switch self {
    case .food: "fork.knife"
    case .coffee: "cup.and.saucer"
    case .stay: "bed.double"
    case .activity: "ticket"
    case .transport: "bus"
    case .shopping: "bag"
    case .flight: "airplane"
    case .train: "tram"
    case .taxi: "car"
    case .other: "plus"
    }
  }
}

/// Category tile colours.
package struct CategoryPalette {
  package init(_ category: ExpenseCategory) {
    let h = category.degreeHue
    background = Color(light: OKLCH(0.94, 0.045, h), dark: OKLCH(0.31, 0.06, h))
    foreground = Color(light: OKLCH(0.46, 0.13, h), dark: OKLCH(0.86, 0.11, h))
  }
  package let background: Color
  package let foreground: Color
}

/// Boarding pass colours drawn from a destination's flag.
///
/// `band` is the header, `text` the accent text, `stripe` the band's inner stripe, `plane` the
/// route glyph, `body` the tinted card and `highlight` the field highlight.
package struct PassPalette {
  package let band: Color
  package let text: Color
  package let stripe: Color
  package let plane: Color
  package let body: Color
  package let highlight: Color

  private static let r = OKLCH(0.56, 0.21, 27)
  private static let g = OKLCH(0.52, 0.15, 152)
  private static let b = OKLCH(0.5, 0.17, 262)
  private static let y = OKLCH(0.84, 0.17, 92)
  private static let k = OKLCH(0.3, 0.01, 60)
  private static let w = OKLCH(0.7, 0.05, 250)
  private static let o = OKLCH(0.66, 0.19, 50)

  /// Predominant, secondary and tertiary flag colours by ISO country code.
  private static let flags: [String: [OKLCH]] = [
    "PT": [r, g, y], "ES": [r, y, r], "FR": [b, r, w], "IT": [g, r, w], "GR": [b, w, b],
    "HR": [r, b, w], "NL": [o, b, r], "DE": [k, y, r], "CH": [r, w, r], "IS": [b, r, w],
    "MA": [r, g, g], "JP": [r, w, r], "TH": [b, r, w], "VN": [r, y, y], "ID": [r, w, r],
    "US": [b, r, w], "MX": [g, r, g], "AU": [b, r, w], "GB": [b, r, w], "IE": [g, o, w],
    "BR": [g, y, b], "IN": [o, g, b], "ZA": [g, y, r], "CA": [r, w, r], "NZ": [b, r, w],
    "TR": [r, w, r], "KR": [b, r, k], "AT": [r, w, r], "SE": [b, y, y], "NO": [r, b, w],
    "DK": [r, w, r],
  ]

  /// Accepts a flag emoji or an ISO country code.
  package init(flag: String) {
    let code = Self.countryCode(flag)
    guard let colours = Self.flags[code] else {
      band = Theme.accent
      text = Theme.accentText
      stripe = Theme.accentDeep
      plane = Theme.accent
      body = Color(
        light: ThemeTokens.light.accent.mixed(into: ThemeTokens.light.surface, amount: 0.05),
        dark: ThemeTokens.dark.accent.mixed(into: ThemeTokens.dark.surface, amount: 0.05))
      highlight = Theme.accentSoft
      return
    }
    let (a, b, c) = (colours[0], colours[1], colours[2])
    let bandColour = a.l > 0.6 ? OKLCH(0.6, a.c, a.h) : a
    let tint = b.c >= 0.1 && b.l <= 0.8 ? b : a
    band = bandColour.color
    stripe = b.adjusting(lightness: b.l > 0.8 ? 0 : 0.02).color
    plane = c.adjusting(lightness: c.l > 0.8 ? -0.1 : 0).color
    let chroma = min(max(tint.c, 0.04), 0.2)
    text = Color(
      light: OKLCH(ThemeTokens.light.accentText.l, chroma, tint.h),
      dark: OKLCH(ThemeTokens.dark.accentText.l, chroma, tint.h))
    let wash = b.c < 0.06 ? 0.06 : 0.09
    body = Color(
      light: b.mixed(into: ThemeTokens.light.surface, amount: wash),
      dark: b.mixed(into: ThemeTokens.dark.surface, amount: wash))
    highlight = Color(
      light: tint.mixed(into: ThemeTokens.light.surface, amount: 0.22),
      dark: tint.mixed(into: ThemeTokens.dark.surface, amount: 0.22))
  }

  private static func countryCode(_ flag: String) -> String {
    let scalars = flag.unicodeScalars.filter { (0x1F1E6...0x1F1FF).contains($0.value) }
    guard scalars.count == 2 else { return flag.uppercased() }
    return String(
      String.UnicodeScalarView(scalars.compactMap { UnicodeScalar($0.value - 127397) }))
  }
}
