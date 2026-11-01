import SwiftUI
import TripSplitDomain

extension Color {
  package init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
      blue: Double(hex & 255) / 255)
  }
  package static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(
      uiColor: UIColor { traits in
        UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
      })
  }
}
public enum Theme {
  public static let background = Color.adaptive(0xF4F2EE, 0x141216)
  public static let surface = Color.adaptive(0xFFFFFF, 0x221F25)
  public static let inset = Color.adaptive(0xECE9E3, 0x302B33)
  public static let ink = Color.adaptive(0x16120F, 0xF5EFF1)
  public static let secondary = Color.adaptive(0x6F6862, 0xB8ADB4)
  public static let accent = Color(hex: 0xE5266B)
  public static let accentSoft = Color.adaptive(0xFCE9EE, 0x472134)
  public static let good = Color.adaptive(0x298853, 0x76D59C)
  public static let bad = Color.adaptive(0xC8372D, 0xFF8E80)
  public static let board = Color(hex: 0x121316)
  public static let amber = Color(hex: 0xF7C948)
}
package struct Card<Content: View>: View {
  package init(padding: CGFloat = 20, @ViewBuilder content: @escaping () -> Content) {
    self.padding = padding
    self.content = content()
  }
  package var padding: CGFloat = 20
  @ViewBuilder var content: Content
  package var body: some View {
    content.padding(padding).frame(maxWidth: .infinity, alignment: .leading).background(
      Theme.surface, in: RoundedRectangle(cornerRadius: 22))
  }
}
package struct Kicker: View {
  package init(title: String) {
    self.title = title
  }
  package var title: String
  package var body: some View {
    Text(title.uppercased()).font(.system(.caption, design: .default, weight: .heavy)).tracking(1.2)
      .foregroundStyle(Theme.secondary)
  }
}
package struct MoneyText: View {
  package init(amount: Int64, currency: String, size: CGFloat = 48) {
    self.amount = amount
    self.currency = currency
    self.size = size
  }
  package var amount: Int64
  package var currency: String
  package var size: CGFloat = 48
  @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1
  package var body: some View {
    Text(Money.format(amount, currency, compact: true)).font(
      .system(size: size * min(scale, 1.5), weight: .bold, design: .default)
    ).tracking(-size * 0.04).monospacedDigit().contentTransition(.numericText()).minimumScaleFactor(
      0.5
    ).lineLimit(1)
  }
}
package struct Avatar: View {
  package init(traveller: Traveller, size: CGFloat = 34) {
    self.traveller = traveller
    self.size = size
  }
  package var traveller: Traveller
  package var size: CGFloat = 34
  package var body: some View {
    Text(String(traveller.name.prefix(1)).uppercased()).font(
      .system(size: size * 0.40, weight: .heavy, design: .default)
    ).foregroundStyle(Color(hue: traveller.hue / 360, saturation: 0.65, brightness: 0.45)).frame(
      width: size, height: size
    ).background(Color(hue: traveller.hue / 360, saturation: 0.20, brightness: 0.98), in: Circle())
      .accessibilityLabel(traveller.name)
  }
}
package struct PrimaryButton: View {
  package init(title: String, symbol: String = "arrow.right", action: @escaping () -> Void) {
    self.title = title
    self.symbol = symbol
    self.action = action
  }
  package var title: String
  package var symbol = "arrow.right"
  package var action: () -> Void
  package var body: some View {
    Button(action: action) {
      Label(title, systemImage: symbol).font(.headline).frame(maxWidth: .infinity).padding(
        .vertical, 18)
    }.buttonStyle(.plain).foregroundStyle(.white).background {
      RoundedRectangle(cornerRadius: 18).fill(Theme.accent).shadow(
        color: Color(hex: 0xA60E4A), radius: 0, y: 4)
    }
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
  package var hero = false
  package var body: some View {
    GeometryReader { geo in
      let maxValue = max(budget, paid + planned, 1)
      HStack(spacing: 2) {
        Rectangle().fill(hero ? .white : Theme.accent).frame(
          width: max(0, geo.size.width * CGFloat(paid) / CGFloat(maxValue)))
        Rectangle().fill((hero ? Color.white : Theme.accent).opacity(0.35)).overlay {
          Canvas { context, size in
            for x in stride(from: -10.0, through: size.width + 10, by: 7) {
              var p = Path()
              p.move(to: .init(x: x, y: size.height))
              p.addLine(to: .init(x: x + 10, y: 0))
              context.stroke(
                p, with: .color((hero ? Color.white : Theme.accent).opacity(0.5)), lineWidth: 2)
            }
          }
        }.frame(width: max(0, geo.size.width * CGFloat(planned) / CGFloat(maxValue)))
        Spacer(minLength: 0)
      }.background((hero ? Color.white : Theme.ink).opacity(0.1)).clipShape(Capsule())
    }.frame(height: 10).accessibilityElement(children: .ignore).accessibilityLabel(
      "\(Money.format(paid, currency)) paid, \(Money.format(planned, currency)) planned, budget \(Money.format(budget, currency))"
    )
  }
}
package struct FlapText: View {
  package init(
    value: String, count: Int = 10, size: CGFloat = 15, color: Color = Color(hex: 0xF3EFE6)
  ) {
    self.value = value
    self.count = count
    self.size = size
    self.color = color
  }
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var revealed = false
  package var value: String
  package var count = 10
  package var size: CGFloat = 15
  package var color: Color = Color(hex: 0xF3EFE6)
  package var body: some View {
    HStack(spacing: 2) {
      ForEach(
        Array(
          (String(value.uppercased().prefix(count)).padding(
            toLength: count, withPad: " ", startingAt: 0)).enumerated()), id: \.offset
      ) { index, char in
        Text(String(char)).font(.system(size: size, weight: .bold, design: .monospaced))
          .foregroundStyle(color).frame(width: size * 0.70, height: size * 1.50).background {
            VStack(spacing: 1) {
              Color(hex: 0x27282C)
              Color(hex: 0x1F2023)
            }
          }.clipShape(RoundedRectangle(cornerRadius: 2))
      }
    }.accessibilityElement(children: .ignore).accessibilityLabel(value).onAppear { revealed = true }
  }
}
package struct CategoryIcon: View {
  package init(category: ExpenseCategory, paid: Bool) {
    self.category = category
    self.paid = paid
  }
  package var category: ExpenseCategory
  package var paid: Bool
  package var body: some View {
    Image(systemName: category.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(
      paid ? Color(hue: category.hue, saturation: 0.6, brightness: 0.55) : Theme.secondary
    ).frame(width: 44, height: 44)
      .background(
        paid ? Color(hue: category.hue, saturation: 0.12, brightness: 0.98) : Color.clear,
        in: Circle()
      )
      .overlay {
        if !paid {
          Circle().strokeBorder(
            Theme.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if paid {
          Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(
            .white
          ).frame(width: 17, height: 17).background(Theme.good, in: Circle()).overlay(
            Circle().stroke(Theme.surface, lineWidth: 2))
        }
      }
  }
}
extension View {
  package func pagePadding() -> some View {
    self.padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: 680).frame(
      maxWidth: .infinity)
  }
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
}

@available(iOS 27.1, *)
private struct VerticalRailReader: View {
  @Environment(\.toolbarVerticalEdge) private var edge
  @Binding var isVertical: Bool
  package var body: some View {
    Color.clear.frame(width: 0, height: 0).onChange(of: edge, initial: true) { _, value in
      isVertical = value != nil
    }
  }
}
extension View {
  @ViewBuilder package func readVerticalRail(_ binding: Binding<Bool>) -> some View {
    if #available(iOS 27.1, *) {
      self.background { VerticalRailReader(isVertical: binding) }
    } else {
      self
    }
  }
}
