import SwiftUI
import UIKit

/// A colour in OKLCH, the space the design tokens are authored in.
///
/// Conversion targets Display P3 and reduces chroma until the colour fits, matching how a
/// browser renders the design's `oklch()` values on a wide-gamut screen.
package struct OKLCH: Hashable, Sendable {
  package var l: Double
  package var c: Double
  package var h: Double
  package var alpha: Double

  package init(_ l: Double, _ c: Double, _ h: Double, alpha: Double = 1) {
    self.l = l
    self.c = c
    self.h = h
    self.alpha = alpha
  }

  /// Creates the OKLCH equivalent of an sRGB hex value.
  package init(hex: UInt32, alpha: Double = 1) {
    let rgb = [(hex >> 16) & 255, (hex >> 8) & 255, hex & 255].map {
      Self.linear(Double($0) / 255)
    }
    let l = cbrt(0.4122214708 * rgb[0] + 0.5363325363 * rgb[1] + 0.0514459929 * rgb[2])
    let m = cbrt(0.2119034982 * rgb[0] + 0.6806995451 * rgb[1] + 0.1073969566 * rgb[2])
    let s = cbrt(0.0883024619 * rgb[0] + 0.2817188376 * rgb[1] + 0.6299787005 * rgb[2])
    let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    let b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    let hue = atan2(b, a) * 180 / .pi
    self.init(lightness, hypot(a, b), hue < 0 ? hue + 360 : hue, alpha: alpha)
  }

  package func adjusting(lightness delta: Double) -> OKLCH {
    OKLCH(min(1, max(0, l + delta)), c, h, alpha: alpha)
  }

  package func opacity(_ value: Double) -> OKLCH { OKLCH(l, c, h, alpha: value) }

  /// `color-mix(in oklch, self amount, other)`, interpolating hue along the shorter arc.
  package func mixed(into other: OKLCH, amount: Double) -> OKLCH {
    let p = min(1, max(0, amount))
    let selfHue = c < 0.0001 ? other.h : h
    let otherHue = other.c < 0.0001 ? selfHue : other.h
    var delta = selfHue - otherHue
    if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
    var hue = otherHue + delta * p
    if hue < 0 { hue += 360 } else if hue >= 360 { hue -= 360 }
    return OKLCH(
      other.l + (l - other.l) * p, other.c + (c - other.c) * p, hue,
      alpha: other.alpha + (alpha - other.alpha) * p)
  }

  /// Gamma-encoded Display P3 components, gamut mapped by chroma reduction.
  package var displayP3: (red: Double, green: Double, blue: Double) {
    var chroma = c
    var p3 = Self.linearP3(l, chroma, h)
    if !Self.inGamut(p3) {
      var low = 0.0
      var high = chroma
      for _ in 0..<24 {
        chroma = (low + high) / 2
        if Self.inGamut(Self.linearP3(l, chroma, h)) { low = chroma } else { high = chroma }
      }
      p3 = Self.linearP3(l, low, h)
    }
    return (Self.encode(p3.0), Self.encode(p3.1), Self.encode(p3.2))
  }

  package var uiColor: UIColor {
    let p3 = displayP3
    return UIColor(displayP3Red: p3.red, green: p3.green, blue: p3.blue, alpha: alpha)
  }

  package var color: Color {
    let p3 = displayP3
    return Color(.displayP3, red: p3.red, green: p3.green, blue: p3.blue, opacity: alpha)
  }

  private static func linearP3(_ l: Double, _ c: Double, _ h: Double) -> (Double, Double, Double) {
    let radians = h * .pi / 180
    let a = c * cos(radians)
    let b = c * sin(radians)
    let lp = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
    let mp = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
    let sp = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
    let r = 4.0767416621 * lp - 3.3077115913 * mp + 0.2309699292 * sp
    let g = -1.2684380046 * lp + 2.6097574011 * mp - 0.3413193965 * sp
    let bl = -0.0041960863 * lp - 0.7034186147 * mp + 1.7076147010 * sp
    return (
      0.8224621 * r + 0.1775380 * g,
      0.0331941 * r + 0.9668058 * g,
      0.0170827 * r + 0.0723974 * g + 0.9105199 * bl
    )
  }

  private static func inGamut(_ v: (Double, Double, Double)) -> Bool {
    let range = -0.0001...1.0001
    return range.contains(v.0) && range.contains(v.1) && range.contains(v.2)
  }

  private static func encode(_ v: Double) -> Double {
    let x = min(1, max(0, v))
    return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
  }

  private static func linear(_ v: Double) -> Double {
    v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
  }
}

extension Color {
  package init(hex: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
      blue: Double(hex & 255) / 255, opacity: opacity)
  }

  package init(_ value: OKLCH) { self = value.color }

  /// A colour that resolves per appearance.
  package init(light: OKLCH, dark: OKLCH) {
    self.init(
      uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? dark.uiColor : light.uiColor
      })
  }

  package static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(light: OKLCH(hex: light), dark: OKLCH(hex: dark))
  }
}
