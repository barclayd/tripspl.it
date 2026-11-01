import SwiftUI
import TripSplitWatchDesign
import TripSplitWatchModel
import WidgetKit

/// Complication colours, on top of the app's palette.
enum Ink {
  static let well = Color(hex: 0x141214)
  static let track = Color(hex: 0x2A2729)
  static let stub = Color(hex: 0x3A3639)
  static let rule = Color(hex: 0x4A4447)
  static let logText = Color(hex: 0xC3195A)

  static func level(_ level: WatchGlance.Level) -> Color {
    switch level {
    case .good: WatchTheme.good
    case .low: WatchTheme.amber
    case .out: WatchTheme.bad
    }
  }
}

extension Font {
  /// Complication type: SF Rounded at a fixed size, with digits that don't jiggle as they change.
  static func glance(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
    .system(size: size, weight: weight, design: .rounded).monospacedDigit()
  }
}

/// How a complication is being drawn right now: tinted faces swap colour for the system tint and
/// draw flags in its shades; with privacy on, Always On hides amounts and dims fills.
struct GlanceLook {
  var accented: Bool
  var hidden: Bool
  /// In the Smart Stack, where the system draws the container.
  var stacked: Bool

  func amount(_ text: String, _ glance: WatchGlance) -> String {
    hidden ? glance.masked : text
  }
}

private struct GlanceLookReader<Content: View>: View {
  let glance: WatchGlance
  @ViewBuilder let content: @MainActor (GlanceLook) -> Content
  @Environment(\.widgetRenderingMode) private var mode
  @Environment(\.isLuminanceReduced) private var dimmed
  @Environment(\.showsWidgetContainerBackground) private var stacked

  var body: some View {
    content(
      .init(
        accented: mode == .accented, hidden: glance.hidesAmounts && dimmed, stacked: stacked))
  }
}

extension WatchGlance {
  /// Reads the rendering mode and Always On state for a complication's body.
  @MainActor func look<Content: View>(
    @ViewBuilder _ content: @escaping @MainActor (GlanceLook) -> Content
  ) -> some View {
    GlanceLookReader(glance: self, content: content)
  }
}

/// A flag. A tinted face fills a text emoji with the tint, so there it's drawn as an image the
/// system can desaturate and tint instead; the two-letter country code stands in without a flag.
struct FlagMark: View {
  let place: WatchGlance.Place
  let size: CGFloat
  @Environment(\.widgetRenderingMode) private var mode
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    if place.flag.isEmpty {
      code
    } else if mode != .accented {
      Text(place.flag).font(.system(size: size))
    } else if let image = tintable {
      image.widgetAccentedRenderingMode(.accentedDesaturated)
    } else {
      code
    }
  }

  private var code: some View {
    Text(place.code)
      .font(.glance(size * 0.62, .heavy))
      .widgetAccentable()
  }

  private var tintable: Image? {
    let renderer = ImageRenderer(content: Text(place.flag).font(.system(size: size)))
    renderer.scale = displayScale
    return renderer.cgImage.map { Image(decorative: $0, scale: displayScale) }
  }
}

/// A circular complication laid out on the design's 50-unit grid, scaled to the slot.
struct Dial<Content: View>: View {
  @ViewBuilder let content: (CGFloat) -> Content

  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      ZStack {
        Well()
        content(side / 50)
      }
      .frame(width: side, height: side)
      .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
    }
  }
}

/// The dark disc behind a complication, or the system's backdrop on a tinted face.
struct Well: View {
  @Environment(\.widgetRenderingMode) private var mode

  var body: some View {
    if mode == .fullColor {
      Circle().fill(Ink.well)
    } else {
      AccessoryWidgetBackground().clipShape(.circle)
    }
  }
}

extension View {
  /// Places a view by its centre on the 50-unit grid.
  func at(_ x: CGFloat, _ y: CGFloat, _ scale: CGFloat) -> some View {
    position(x: x * scale, y: y * scale)
  }
}
