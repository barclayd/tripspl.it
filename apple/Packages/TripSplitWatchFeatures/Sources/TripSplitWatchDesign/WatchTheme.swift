import SwiftUI
import TripSplitDomain

/// Colour tokens from the watch design handoff. True black canvas, one pink accent,
/// amber for departures, and the warm paper of the passport page.
public enum WatchTheme {
  public static let background = Color.black
  public static let card = Color(hex: 0x1F1D20)
  public static let card2 = Color(hex: 0x2A2729)
  public static let ink2 = Color(hex: 0xABA49E)
  public static let ink3 = Color(hex: 0x7A746E)
  public static let accent = Color(hex: 0xE5266B)
  public static let accentText = Color(hex: 0xF04583)
  public static let tint = Color(hex: 0x3A1222)
  public static let good = Color(hex: 0x4CD38A)
  public static let bad = Color(hex: 0xFF6A5C)
  public static let amber = Color(hex: 0xF7C948)

  public static let board = Color(hex: 0x121316)
  public static let boardEdge = Color(hex: 0x232428)
  public static let flapTop = Color(hex: 0x27282C)
  public static let flapBottom = Color(hex: 0x1F2023)
  public static let flapInk = Color(hex: 0xF3EFE6)

  public static let paper = Color(hex: 0xF5EFDF)
  public static let paperRule = Color(red: 120 / 255, green: 90 / 255, blue: 40 / 255)
    .opacity(0.09)
  public static let stampInks = [Color(hex: 0x5546A8), Color(hex: 0xB8322A), Color(hex: 0xC3195A)]
}

extension Color {
  public init(hex: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255, opacity: opacity)
  }

  /// A CSS `oklch()` colour, gamut-clipped to sRGB. Hue is in degrees.
  public init(oklch lightness: Double, _ chroma: Double, _ hue: Double) {
    let radians = hue * .pi / 180
    let a = chroma * cos(radians)
    let b = chroma * sin(radians)
    let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
    let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
    let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
    func gamma(_ value: Double) -> Double {
      let clipped = min(1, max(0, value))
      return clipped <= 0.0031308 ? 12.92 * clipped : 1.055 * pow(clipped, 1 / 2.4) - 0.055
    }
    self.init(
      .sRGB,
      red: gamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
      green: gamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
      blue: gamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
  }
}

extension ExpenseCategory {
  /// Hue in degrees for the watch's category tiles.
  public var watchHue: Double {
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

  public var tileBackground: Color { Color(oklch: 0.34, 0.08, watchHue) }
  public var tileGlyph: Color { Color(oklch: 0.85, 0.12, watchHue) }
}

extension Traveller {
  /// The traveller's avatar colour. The signed-in traveller is always the accent.
  public func colour(isYou: Bool) -> Color {
    isYou ? WatchTheme.accentText : Color(oklch: 0.72, 0.15, hue)
  }
}
