import SwiftUI
import TripSplitDesignSystem
import TripSplitWidgetModel
import WidgetKit

/// A place's flag emoji, or its country code in an outlined box where colour images don't belong
/// (Clear, Tinted and the Lock Screen desaturate them).
struct FlagMark: View {
  var place: Place
  var size: CGFloat = 15
  @Environment(\.widgetLook) private var look

  var body: some View {
    if look.showsFlags, !place.flag.isEmpty {
      Text(place.flag).font(.system(size: size)).accessibilityHidden(true)
    } else if !place.code.isEmpty {
      CodeBadge(code: place.code, size: max(11, size * 0.5))
    }
  }
}

/// "PT" in a 1.5pt outlined rounded box, 11pt heavy.
struct CodeBadge: View {
  var code: String
  var size: CGFloat = 11
  @Environment(\.widgetLook) private var look

  var body: some View {
    Text(code).font(.system(size: size, weight: .heavy, design: .rounded))
      .padding(.horizontal, size * 0.27).padding(.vertical, size * 0.05)
      .overlay {
        RoundedRectangle(cornerRadius: size * 0.36, style: .continuous)
          .strokeBorder(lineWidth: 1.5)
      }
      .foregroundStyle(look.palette.ink)
      .accessibilityHidden(true)
  }
}

/// The TripSplit plane, pointing up in a 24-unit box.
struct PlaneShape: Shape {
  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width, rect.height) / 24
    let x = rect.midX - 12 * scale
    let y = rect.midY - 12 * scale
    func p(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
      CGPoint(x: x + px * scale, y: y + py * scale)
    }
    var path = Path()
    path.move(to: p(21, 16))
    path.addLine(to: p(21, 14))
    path.addLine(to: p(13, 9))
    path.addLine(to: p(13, 3.5))
    // The nose: a half circle of radius 1.5 over the top.
    let k: CGFloat = 0.828
    path.addCurve(to: p(11.5, 2), control1: p(13, 3.5 - k), control2: p(11.5 + k, 2))
    path.addCurve(to: p(10, 3.5), control1: p(11.5 - k, 2), control2: p(10, 3.5 - k))
    path.addLine(to: p(10, 9))
    path.addLine(to: p(2, 14))
    path.addLine(to: p(2, 16))
    path.addLine(to: p(10, 13.5))
    path.addLine(to: p(10, 19))
    path.addLine(to: p(8, 20.5))
    path.addLine(to: p(8, 22))
    path.addLine(to: p(11.5, 21))
    path.addLine(to: p(15, 22))
    path.addLine(to: p(15, 20.5))
    path.addLine(to: p(13, 19))
    path.addLine(to: p(13, 13.5))
    path.closeSubpath()
    return path
  }
}

/// The plane at a size, turned to a heading in degrees (0 is up, 90 is flying right).
struct PlaneGlyph: View {
  var size: CGFloat
  var heading: Double = 90

  var body: some View {
    PlaneShape().rotation(.degrees(heading)).frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}

/// A traveller's initial on their hue, as in the app's balances.
struct InitialAvatar: View {
  var initial: String
  var hue: Double
  var size: CGFloat = 20
  @Environment(\.widgetLook) private var look

  var body: some View {
    Text(initial).font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
      .foregroundStyle(foreground).frame(width: size, height: size)
      .background(background, in: Circle())
      .accessibilityHidden(true)
  }

  private var background: Color {
    guard look.mode == .fullColor else { return look.palette.track }
    return Color(look.dark || look.standBy ? OKLCH(0.42, 0.1, hue) : OKLCH(0.87, 0.08, hue))
  }

  private var foreground: Color {
    guard look.mode == .fullColor else { return look.palette.ink }
    return Color(look.dark || look.standBy ? OKLCH(0.94, 0.05, hue) : OKLCH(0.36, 0.13, hue))
  }
}

/// The design's two widget buttons: a 40pt capsule with a symbol and a word.
struct CapsuleLabel: View {
  enum Kind { case secondary, primary }

  var title: String
  var symbol: String
  var kind: Kind
  @Environment(\.widgetLook) private var look

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: symbol).font(.system(size: kind == .primary ? 14 : 15, weight: .bold))
      Text(title).font(.system(size: 14, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
    }
    .foregroundStyle(kind == .primary ? look.palette.onAccent : look.palette.ink)
    .frame(maxWidth: .infinity).frame(height: 40)
    .background {
      Capsule().fill(kind == .primary ? look.palette.accent : look.palette.secondaryButton)
        .widgetAccentable(kind == .primary)
    }
  }
}

/// "€1 = £0.86": 11 bold accent text on accent soft, only shown abroad.
struct RateChip: View {
  var text: String
  @Environment(\.widgetLook) private var look

  var body: some View {
    Text(text).font(.system(size: 11, weight: .bold)).monospacedDigit()
      .foregroundStyle(look.palette.accentText).lineLimit(1)
      .padding(.vertical, 3).padding(.horizontal, 7)
      .background(look.palette.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
