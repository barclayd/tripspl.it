import SwiftUI
import TripSplitDesignSystem
import WidgetKit

/// How a widget is being drawn: in full colour on the Home Screen, with its background removed in
/// StandBy, tinted or clear (accented), or monochrome on the Lock Screen (vibrant).
public struct WidgetLook: Hashable, Sendable {
  public enum Mode: Hashable, Sendable {
    case fullColor, accented, vibrant
  }

  public var mode: Mode
  public var dark: Bool
  /// StandBy and CarPlay: no container background, figures scaled up.
  public var standBy: Bool
  /// Always-On: the Lock Screen's reduced-luminance greys.
  public var dimmed: Bool
  /// Settings › Hide amounts when locked: amounts are redacted until Face ID unlocks.
  public var hidesAmounts: Bool

  public init(
    mode: Mode = .fullColor, dark: Bool = false, standBy: Bool = false, dimmed: Bool = false,
    hidesAmounts: Bool = false
  ) {
    self.mode = mode
    self.dark = dark
    self.standBy = standBy
    self.dimmed = dimmed
    self.hidesAmounts = hidesAmounts
  }

  /// Flags are full-colour images, so the tinted and Lock Screen looks use the country code.
  public var showsFlags: Bool { mode == .fullColor }

  public var palette: WidgetPalette {
    switch mode {
    case .vibrant: dimmed ? .alwaysOn : .lock
    case .accented: .accented
    case .fullColor: standBy ? .standBy : dark ? .dark : .light
    }
  }
}

/// The design's widget tokens, resolved for one look.
public struct WidgetPalette: Sendable {
  public var background: Color
  public var ink: Color
  public var ink2: Color
  public var ink3: Color
  public var track: Color
  public var accent: Color
  public var accentText: Color
  public var accentSoft: Color
  public var good: Color
  public var bad: Color
  public var secondaryButton: Color
  /// Text on the accent fill.
  public var onAccent: Color

  static let light = WidgetPalette(
    background: Color(hex: 0xFFFFFF), ink: Color(hex: 0x16120F), ink2: Color(hex: 0x6F6862),
    ink3: Color(hex: 0xA39C94), track: Color(hex: 0xECE9E3), accent: Color(hex: 0xE5266B),
    accentText: Color(hex: 0xC3195A), accentSoft: Color(hex: 0xFCE9EE), good: Color(hex: 0x2E9B60),
    bad: Color(hex: 0xD2372C), secondaryButton: Color(hex: 0xF1EEE9), onAccent: .white)

  static let dark = WidgetPalette(
    background: Color(hex: 0x1C1A19), ink: Color(hex: 0xF6F2EE), ink2: Color(hex: 0xABA49E),
    ink3: Color(hex: 0x6F6862), track: Color(hex: 0x34302D), accent: Color(hex: 0xF04583),
    accentText: Color(hex: 0xF5609A), accentSoft: Color(hex: 0x3B1B28), good: Color(hex: 0x4CD38A),
    bad: Color(hex: 0xFF6A5C), secondaryButton: Color(hex: 0x2C2927), onAccent: .white)

  static let standBy = WidgetPalette(
    background: .black, ink: Color(hex: 0xFFFFFF), ink2: Color(hex: 0xA8A8AD),
    ink3: Color(hex: 0x6E6E73), track: Color(hex: 0x2C2C2E), accent: Color(hex: 0xF04583),
    accentText: Color(hex: 0xF5609A), accentSoft: Color(hex: 0x3B1B28), good: Color(hex: 0x4CD38A),
    bad: Color(hex: 0xFF6A5C), secondaryButton: Color(hex: 0x2C2927), onAccent: .white)

  /// Clear and Tinted: the system recolours everything, so only brightness separates layers.
  static let accented = WidgetPalette(
    background: .clear, ink: .white, ink2: .white.opacity(0.62), ink3: .white.opacity(0.4),
    track: .white.opacity(0.22), accent: .white, accentText: .white,
    accentSoft: .white.opacity(0.18), good: .white, bad: .white,
    secondaryButton: .white.opacity(0.16), onAccent: .black)

  static let lock = WidgetPalette(
    background: .clear, ink: Color(hex: 0xFFFFFF), ink2: Color(hex: 0xC7C7CC),
    ink3: Color(hex: 0x8E8E93), track: Color(hex: 0x5C5C61), accent: Color(hex: 0xFFFFFF),
    accentText: Color(hex: 0xFFFFFF), accentSoft: Color(hex: 0x5C5C61),
    good: Color(hex: 0xFFFFFF), bad: Color(hex: 0xFFFFFF), secondaryButton: Color(hex: 0x5C5C61),
    onAccent: .black)

  static let alwaysOn = WidgetPalette(
    background: .clear, ink: Color(hex: 0x9A9AA0), ink2: Color(hex: 0x6E6E73),
    ink3: Color(hex: 0x6E6E73), track: Color(hex: 0x333336), accent: Color(hex: 0x9A9AA0),
    accentText: Color(hex: 0x9A9AA0), accentSoft: Color(hex: 0x333336),
    good: Color(hex: 0x9A9AA0), bad: Color(hex: 0x9A9AA0), secondaryButton: Color(hex: 0x333336),
    onAccent: .black)
}

extension EnvironmentValues {
  /// Set by `widgetLook()` from the system's rendering environment.
  @Entry public var widgetLook = WidgetLook()
  /// Forces a look, for the in-app gallery and previews.
  @Entry public var widgetLookOverride: WidgetLook? = nil
}

/// Reads WidgetKit's rendering environment into a `WidgetLook` for the views below.
struct WidgetLookReader: ViewModifier {
  var hidesAmounts: Bool
  @Environment(\.colorScheme) private var scheme
  @Environment(\.widgetRenderingMode) private var renderingMode
  @Environment(\.showsWidgetContainerBackground) private var showsBackground
  @Environment(\.isLuminanceReduced) private var luminanceReduced
  @Environment(\.widgetLookOverride) private var override

  func body(content: Content) -> some View {
    content.environment(\.widgetLook, override ?? resolved)
  }

  private var resolved: WidgetLook {
    let mode: WidgetLook.Mode =
      switch renderingMode {
      case .accented: .accented
      case .vibrant: .vibrant
      default: .fullColor
      }
    return WidgetLook(
      mode: mode, dark: scheme == .dark, standBy: mode == .fullColor && !showsBackground,
      dimmed: luminanceReduced, hidesAmounts: hidesAmounts)
  }
}

extension View {
  /// Resolves the widget's look and paints its container background.
  public func widgetLook(hidesAmounts: Bool = false, background: Color? = nil) -> some View {
    modifier(WidgetContainer(background: background)).modifier(
      WidgetLookReader(hidesAmounts: hidesAmounts))
  }

  /// An amount that the system redacts while the phone is locked, when the user asked for it.
  func amount(_ look: WidgetLook) -> some View {
    privacySensitive(look.hidesAmounts)
  }

  /// Widget type: the system face at a point size, not scaled by Dynamic Type.
  func type(
    _ size: CGFloat, _ weight: Font.Weight = .semibold, design: Font.Design = .default
  ) -> some View {
    font(.system(size: size, weight: weight, design: design))
  }

  /// A figure: bold rounded with tabular digits, tracked in a little, shrinking rather than
  /// truncating.
  func figure(_ size: CGFloat, weight: Font.Weight = .bold, tracking: CGFloat = -0.01) -> some View
  {
    font(.system(size: size, weight: weight, design: .rounded)).monospacedDigit()
      .tracking(size * tracking).lineLimit(1).minimumScaleFactor(0.5)
      .contentTransition(.numericText())
  }
}

private struct WidgetContainer: ViewModifier {
  var background: Color?
  @Environment(\.widgetLook) private var look

  func body(content: Content) -> some View {
    content.containerBackground(for: .widget) { background ?? look.palette.background }
  }
}
