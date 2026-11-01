import SwiftUI
import TripSplitDomain

/// Resolved design tokens for one appearance.
///
/// Light is the design's Pop theme. Dark keeps Night's neutrals with Pop's pink accent
/// retuned for a dark surface.
package struct ThemeTokens: Sendable {
  package var background: OKLCH
  package var surface: OKLCH
  package var inset: OKLCH
  package var ink: OKLCH
  package var ink2: OKLCH
  package var ink3: OKLCH
  package var line: OKLCH
  package var line2: OKLCH
  package var accent: OKLCH
  package var accentInk: OKLCH
  package var accentSoft: OKLCH
  package var accentDeep: OKLCH
  package var accentText: OKLCH
  package var good: OKLCH
  package var goodInk: OKLCH
  package var bad: OKLCH
  package var glass: OKLCH
  package var mapVisited: OKLCH
  package var paper: OKLCH
  package var paperLine: OKLCH
  package var paperInk: OKLCH

  package static let light = ThemeTokens(
    background: OKLCH(hex: 0xF4F2EE), surface: OKLCH(hex: 0xFFFFFF), inset: OKLCH(hex: 0xECE9E3),
    ink: OKLCH(hex: 0x16120F), ink2: OKLCH(hex: 0x6F6862), ink3: OKLCH(hex: 0xA39C94),
    line: OKLCH(hex: 0x16120F, alpha: 0.07), line2: OKLCH(hex: 0x16120F, alpha: 0.14),
    accent: OKLCH(0.6, 0.23, 4), accentInk: OKLCH(hex: 0xFFFFFF),
    accentSoft: OKLCH(0.95, 0.035, 4), accentDeep: OKLCH(0.47, 0.2, 4),
    accentText: OKLCH(0.53, 0.22, 4), good: OKLCH(0.6, 0.15, 155), goodInk: OKLCH(hex: 0xFFFFFF),
    bad: OKLCH(0.55, 0.2, 25), glass: OKLCH(hex: 0xFFFFFF, alpha: 0.72),
    mapVisited: OKLCH(0.8, 0.11, 4), paper: OKLCH(hex: 0xF5EFDF),
    paperLine: OKLCH(hex: 0x785A28, alpha: 0.06), paperInk: OKLCH(hex: 0x5A4628, alpha: 0.5))

  package static let dark = ThemeTokens(
    background: OKLCH(hex: 0x0A0C0F), surface: OKLCH(hex: 0x15181D), inset: OKLCH(hex: 0x1F232A),
    ink: OKLCH(hex: 0xF3F4F6), ink2: OKLCH(hex: 0x9BA2AD), ink3: OKLCH(hex: 0x626973),
    line: OKLCH(hex: 0xFFFFFF, alpha: 0.07), line2: OKLCH(hex: 0xFFFFFF, alpha: 0.14),
    accent: OKLCH(0.62, 0.22, 4), accentInk: OKLCH(hex: 0xFFFFFF),
    accentSoft: OKLCH(0.27, 0.06, 4), accentDeep: OKLCH(0.42, 0.17, 4),
    accentText: OKLCH(0.75, 0.16, 4), good: OKLCH(0.85, 0.17, 150), goodInk: OKLCH(hex: 0x0A0C0F),
    bad: OKLCH(0.72, 0.17, 25), glass: OKLCH(hex: 0x1E2128, alpha: 0.72),
    mapVisited: OKLCH(0.7, 0.15, 4), paper: OKLCH(hex: 0x1B1D22),
    paperLine: OKLCH(hex: 0xFFFFFF, alpha: 0.025), paperInk: OKLCH(hex: 0xFFFFFF, alpha: 0.4))

  package static func resolved(_ scheme: ColorScheme) -> ThemeTokens {
    scheme == .dark ? dark : light
  }
}

public enum Theme {
  private static func token(_ path: KeyPath<ThemeTokens, OKLCH>) -> Color {
    Color(light: ThemeTokens.light[keyPath: path], dark: ThemeTokens.dark[keyPath: path])
  }

  public static let background = token(\.background)
  public static let surface = token(\.surface)
  public static let inset = token(\.inset)
  public static let ink = token(\.ink)
  public static let secondary = token(\.ink2)
  public static let tertiary = token(\.ink3)
  public static let line = token(\.line)
  public static let line2 = token(\.line2)
  public static let accent = token(\.accent)
  public static let accentInk = token(\.accentInk)
  public static let accentSoft = token(\.accentSoft)
  public static let accentDeep = token(\.accentDeep)
  public static let accentText = token(\.accentText)
  public static let good = token(\.good)
  public static let goodInk = token(\.goodInk)
  public static let bad = token(\.bad)
  public static let glass = token(\.glass)
  public static let mapVisited = token(\.mapVisited)
  public static let paper = token(\.paper)
  public static let paperLine = token(\.paperLine)
  public static let paperInk = token(\.paperInk)

  /// Translucent fills over the accent hero card.
  public static let heroChip = Color.white.opacity(0.2)
  public static let heroTrack = Color.white.opacity(0.28)
  public static let heroHatch = Color.white.opacity(0.7)

  /// The departures board keeps its own palette in both appearances.
  public static let board = Color(hex: 0x121316)
  public static let flapTop = Color(hex: 0x27282C)
  public static let flapBottom = Color(hex: 0x1F2023)
  public static let flapInk = Color(hex: 0xF3EFE6)
  public static let amber = Color(hex: 0xF7C948)
  public static let signal = Color(hex: 0x5BE49B)

  /// The printed receipt keeps its paper colours in both appearances.
  public static let receiptPaper = Color(hex: 0xFFFDF6)
  public static let receiptInk = Color(hex: 0x23201B)
  public static let receiptMuted = Color(hex: 0x7A7368)
  public static let receiptRule = Color(hex: 0xCFC8BB)

  public static let space = Color(hex: 0x04060B)
  public static let land = Color(hex: 0xF3F0E8)

  package enum Radius {
    package static let card: CGFloat = 22
    package static let hero: CGFloat = 28
    package static let sheet: CGFloat = 36
    package static let button: CGFloat = 20
    package static let key: CGFloat = 14
    package static let tile: CGFloat = 16
  }

  package enum Spacing {
    package static let screen: CGFloat = 20
    package static let section: CGFloat = 26
  }
}

// MARK: - Type

private struct ScaledFont: ViewModifier {
  @ScaledMetric private var size: CGFloat
  private let weight: Font.Weight
  private let design: Font.Design
  private let tracking: CGFloat
  private let maximum: CGFloat

  init(
    size: CGFloat, weight: Font.Weight, design: Font.Design, tracking: CGFloat,
    relativeTo style: Font.TextStyle, maximum: CGFloat
  ) {
    _size = ScaledMetric(wrappedValue: size, relativeTo: style)
    self.weight = weight
    self.design = design
    self.tracking = tracking
    self.maximum = size * maximum
  }

  func body(content: Content) -> some View {
    let resolved = min(size, maximum)
    content.font(.system(size: resolved, weight: weight, design: design)).tracking(
      resolved * tracking)
  }
}

extension View {
  /// The design's point type scale, following Dynamic Type up to `maximum` times its size.
  package func typeface(
    _ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default,
    tracking: CGFloat = 0, relativeTo style: Font.TextStyle = .body, maximum: CGFloat = 1.6
  ) -> some View {
    modifier(
      ScaledFont(
        size: size, weight: weight, design: design, tracking: tracking, relativeTo: style,
        maximum: maximum))
  }

  /// Large screen title: 32/800, -0.035em.
  package func screenTitle(_ size: CGFloat = 32) -> some View {
    typeface(size, .heavy, tracking: -0.035, relativeTo: .largeTitle, maximum: 1.3)
      .foregroundStyle(Theme.ink)
  }

  package func pagePadding() -> some View {
    self.padding(.horizontal, Theme.Spacing.screen).padding(.vertical, 12).frame(maxWidth: 680)
      .frame(maxWidth: .infinity)
  }
}

// MARK: - Building blocks

package struct Card<Content: View>: View {
  package init(
    padding: CGFloat = 20, radius: CGFloat = Theme.Radius.card,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.padding = padding
    self.radius = radius
    self.content = content()
  }
  package var padding: CGFloat
  package var radius: CGFloat
  @ViewBuilder var content: Content
  package var body: some View {
    content.padding(padding).frame(maxWidth: .infinity, alignment: .leading).background(
      Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
  }
}

/// Section heading: 13/800 uppercase, +0.04em, secondary ink.
package struct Kicker: View {
  package init(title: String) {
    self.title = title
  }
  package var title: String
  package var body: some View {
    Text(title.uppercased()).typeface(13, .heavy, tracking: 0.04, relativeTo: .footnote)
      .foregroundStyle(Theme.secondary).accessibilityAddTraits(.isHeader)
  }
}

/// Money that counts up from zero, then tweens between values (ease-out quart, 1s).
package struct MoneyText: View {
  package init(
    amount: Int64, currency: String, size: CGFloat = 50, weight: Font.Weight = .bold,
    countsUp: Bool = true
  ) {
    self.amount = amount
    self.currency = currency
    self.size = size
    self.weight = weight
    self.countsUp = countsUp
  }
  package var amount: Int64
  package var currency: String
  package var size: CGFloat
  package var weight: Font.Weight
  package var countsUp: Bool
  @State private var shown: Double?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  package var body: some View {
    CountingMoney(value: shown ?? Double(amount), currency: currency)
      .typeface(size, weight, tracking: -0.045, relativeTo: .largeTitle, maximum: 1.3)
      .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Money.format(amount, currency))
      .onAppear {
        guard countsUp, !reduceMotion, shown == nil else { return }
        shown = 0
        withAnimation(Motion.countUp) { shown = Double(amount) }
      }
      .onChange(of: amount) { _, value in
        withAnimation(reduceMotion ? nil : Motion.countUp) { shown = Double(value) }
      }
  }
}

private struct CountingMoney: View, Animatable {
  var value: Double
  let currency: String
  nonisolated var animatableData: Double {
    get { value }
    set { value = newValue }
  }
  var body: some View {
    Text(Money.format(Int64(value.rounded()), currency, compact: true))
  }
}

package struct Avatar: View {
  package init(traveller: Traveller, size: CGFloat = 34) {
    self.name = traveller.name
    self.hue = traveller.hue
    self.size = size
  }
  package init(name: String, hue: Double, size: CGFloat = 34) {
    self.name = name
    self.hue = hue
    self.size = size
  }
  package var name: String
  package var hue: Double
  package var size: CGFloat
  package var body: some View {
    let colours = AvatarPalette(hue: hue)
    Text(String(name.prefix(1)).uppercased()).font(
      .system(size: size * 0.42, weight: .heavy)
    ).foregroundStyle(colours.foreground).frame(width: size, height: size)
      .background(colours.background, in: Circle()).accessibilityLabel(name)
  }
}

/// The chunky lipped button: 58pt, accent fill and a 5pt deep accent lip that compresses
/// when pressed.
package struct LipButtonStyle: ButtonStyle {
  package enum Kind: Sendable { case primary, secondary }
  package init(_ kind: Kind = .primary, height: CGFloat = 58) {
    self.kind = kind
    self.height = height
  }
  package var kind: Kind
  package var height: CGFloat

  package func makeBody(configuration: Configuration) -> some View {
    LipButton(configuration: configuration, kind: kind, height: height)
  }
}

private struct LipButton: View {
  let configuration: ButtonStyleConfiguration
  let kind: LipButtonStyle.Kind
  let height: CGFloat
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    let pressed = configuration.isPressed && isEnabled
    let fill: Color = !isEnabled ? Theme.inset : kind == .primary ? Theme.accent : Theme.surface
    let ink: Color = !isEnabled ? Theme.tertiary : kind == .primary ? Theme.accentInk : Theme.ink
    let lip: Color = kind == .primary ? Theme.accentDeep : Theme.line2
    let shape = RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
    configuration.label.typeface(17, .heavy, relativeTo: .headline, maximum: 1.3)
      .foregroundStyle(ink).frame(maxWidth: .infinity, minHeight: height)
      .background {
        ZStack {
          if isEnabled { shape.fill(lip).offset(y: pressed ? 1 : 5) }
          shape.fill(fill)
        }
      }
      .contentShape(shape).offset(y: pressed ? 4 : 0)
      .padding(.bottom, 5)
      .animation(.easeOut(duration: 0.1), value: pressed)
  }
}

package struct PrimaryButton: View {
  package init(title: String, symbol: String? = "arrow.right", action: @escaping () -> Void) {
    self.title = title
    self.symbol = symbol
    self.action = action
  }
  package var title: String
  package var symbol: String?
  package var action: () -> Void
  package var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let symbol { Image(systemName: symbol).font(.system(size: 18, weight: .bold)) }
        Text(title)
      }
    }.buttonStyle(LipButtonStyle())
  }
}

/// A selectable capsule chip: ink when selected, inset otherwise.
package struct ChipButtonStyle: ButtonStyle {
  package init(selected: Bool) {
    self.selected = selected
  }
  package var selected: Bool
  package func makeBody(configuration: Configuration) -> some View {
    configuration.label.typeface(14, .bold, relativeTo: .subheadline, maximum: 1.3)
      .padding(.horizontal, 14).frame(minHeight: 38)
      .foregroundStyle(selected ? Theme.background : Theme.secondary)
      .background(selected ? Theme.ink : Theme.inset, in: Capsule())
      .scaleEffect(selected ? 1.04 : configuration.isPressed ? 0.96 : 1)
      .animation(Motion.bump, value: selected)
  }
}

package struct BudgetBar: View {
  package init(paid: Int64, planned: Int64, budget: Int64, currency: String, hero: Bool = false) {
    self.paid = paid
    self.planned = planned
    self.budget = budget
    self.currency = currency
    self.hero = hero
  }
  package var paid: Int64
  package var planned: Int64
  package var budget: Int64
  package var currency: String
  package var hero: Bool
  package var body: some View {
    GeometryReader { geo in
      let maxValue = CGFloat(max(budget, paid + planned, 1))
      let fill: Color = hero ? .white : Theme.accent
      HStack(spacing: 0) {
        Rectangle().fill(fill).frame(width: geo.size.width * CGFloat(max(0, paid)) / maxValue)
        Hatch(color: hero ? Theme.heroHatch : Theme.accent.opacity(0.55))
          .frame(width: geo.size.width * CGFloat(max(0, planned)) / maxValue)
        Spacer(minLength: 0)
      }
      .background(hero ? Theme.heroTrack : Theme.inset).clipShape(Capsule())
    }.frame(height: 10).accessibilityElement(children: .ignore).accessibilityLabel(
      "\(Money.format(paid, currency)) paid, \(Money.format(planned, currency)) planned, budget \(Money.format(budget, currency))"
    )
  }
}

/// Diagonal hatching for planned amounts.
package struct Hatch: View {
  package init(color: Color, spacing: CGFloat = 6, lineWidth: CGFloat = 2.2) {
    self.color = color
    self.spacing = spacing
    self.lineWidth = lineWidth
  }
  package var color: Color
  package var spacing: CGFloat
  package var lineWidth: CGFloat
  package var body: some View {
    Canvas { context, size in
      var path = Path()
      for x in stride(from: -size.height, through: size.width + size.height, by: spacing) {
        path.move(to: .init(x: x, y: size.height))
        path.addLine(to: .init(x: x + size.height, y: 0))
      }
      context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }.clipped().accessibilityHidden(true)
  }
}

/// Category glyph tile. Paid expenses are tinted; planned ones are dashed.
package struct CategoryIcon: View {
  package init(category: ExpenseCategory, paid: Bool, size: CGFloat = 44) {
    self.category = category
    self.paid = paid
    self.size = size
  }
  package var category: ExpenseCategory
  package var paid: Bool
  package var size: CGFloat
  package var body: some View {
    let style = CategoryPalette(category)
    Image(systemName: category.glyph).font(.system(size: size * 0.42, weight: .semibold))
      .foregroundStyle(paid ? style.foreground : Theme.tertiary)
      .frame(width: size, height: size)
      .background(paid ? style.background : .clear, in: Circle())
      .overlay {
        if !paid {
          Circle().strokeBorder(Theme.tertiary, style: StrokeStyle(lineWidth: 1.6, dash: [4, 3]))
        }
      }
      .accessibilityHidden(true)
  }
}

// MARK: - Platform

extension View {
  @ViewBuilder public func trailingSheet() -> some View {
    if #available(iOS 27.1, *) { self.presentationPlacement(.trailing) } else { self }
  }
  @ViewBuilder package func taskRail() -> some View {
    if #available(iOS 27.1, *) {
      self.toolbarVerticalCompressionBehavior(.prefersToolbarItems)
    } else {
      self
    }
  }
  @ViewBuilder package func readVerticalRail(_ binding: Binding<Bool>) -> some View {
    if #available(iOS 27.1, *) {
      self.background { VerticalRailReader(isVertical: binding) }
    } else {
      self
    }
  }
}

@available(iOS 27.1, *)
private struct VerticalRailReader: View {
  @Environment(\.toolbarVerticalEdge) private var edge
  @Binding var isVertical: Bool
  var body: some View {
    Color.clear.frame(width: 0, height: 0).onChange(of: edge, initial: true) { _, value in
      isVertical = value != nil
    }
  }
}
