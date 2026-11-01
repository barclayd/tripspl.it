import SwiftUI

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
      blue: Double(hex & 255) / 255)
  }
  static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(
      uiColor: UIColor { traits in
        UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
      })
  }
}
enum Theme {
  static let background = Color.adaptive(0xF4F2EE, 0x141216)
  static let surface = Color.adaptive(0xFFFFFF, 0x221F25)
  static let inset = Color.adaptive(0xECE9E3, 0x302B33)
  static let ink = Color.adaptive(0x16120F, 0xF5EFF1)
  static let secondary = Color.adaptive(0x6F6862, 0xB8ADB4)
  static let accent = Color(hex: 0xE5266B)
  static let accentSoft = Color.adaptive(0xFCE9EE, 0x472134)
  static let good = Color.adaptive(0x298853, 0x76D59C)
  static let bad = Color.adaptive(0xC8372D, 0xFF8E80)
  static let board = Color(hex: 0x121316)
  static let amber = Color(hex: 0xF7C948)
}
struct Card<Content: View>: View {
  var padding: CGFloat = 20
  @ViewBuilder var content: Content
  var body: some View {
    content.padding(padding).frame(maxWidth: .infinity, alignment: .leading).background(
      Theme.surface, in: RoundedRectangle(cornerRadius: 22))
  }
}
struct Kicker: View {
  var title: String
  var body: some View {
    Text(title.uppercased()).font(.system(.caption, design: .default, weight: .heavy)).tracking(1.2)
      .foregroundStyle(Theme.secondary)
  }
}
struct MoneyText: View {
  var amount: Int64
  var currency: String
  var size: CGFloat = 48
  @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1
  var body: some View {
    Text(Money.format(amount, currency, compact: true)).font(
      .system(size: size * min(scale, 1.5), weight: .bold, design: .default)
    ).tracking(-size * 0.04).monospacedDigit().contentTransition(.numericText()).minimumScaleFactor(
      0.5
    ).lineLimit(1)
  }
}
struct Avatar: View {
  var traveller: Traveller
  var size: CGFloat = 34
  var body: some View {
    Text(String(traveller.name.prefix(1)).uppercased()).font(
      .system(size: size * 0.40, weight: .heavy, design: .default)
    ).foregroundStyle(Color(hue: traveller.hue / 360, saturation: 0.65, brightness: 0.45)).frame(
      width: size, height: size
    ).background(Color(hue: traveller.hue / 360, saturation: 0.20, brightness: 0.98), in: Circle())
      .accessibilityLabel(traveller.name)
  }
}
struct PrimaryButton: View {
  var title: String
  var symbol = "arrow.right"
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      Label(title, systemImage: symbol).font(.headline).frame(maxWidth: .infinity).padding(
        .vertical, 18)
    }.buttonStyle(.plain).foregroundStyle(.white).background {
      RoundedRectangle(cornerRadius: 18).fill(Theme.accent).shadow(
        color: Color(hex: 0xA60E4A), radius: 0, y: 4)
    }
  }
}
struct BudgetBar: View {
  var paid: Int64
  var planned: Int64
  var budget: Int64
  var currency: String
  var hero = false
  var body: some View {
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
struct FlapText: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var revealed = false
  var value: String
  var count = 10
  var size: CGFloat = 15
  var color: Color = Color(hex: 0xF3EFE6)
  var body: some View {
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
struct CategoryIcon: View {
  var category: ExpenseCategory
  var paid: Bool
  var body: some View {
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
  func pagePadding() -> some View {
    self.padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: 680).frame(
      maxWidth: .infinity)
  }
  @ViewBuilder func trailingSheet() -> some View {
    if #available(iOS 27.1, *) { self.presentationPlacement(.trailing) } else { self }
  }
  @ViewBuilder func taskRail() -> some View {
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
  var body: some View {
    Color.clear.frame(width: 0, height: 0).onChange(of: edge, initial: true) { _, value in
      isVertical = value != nil
    }
  }
}
extension View {
  @ViewBuilder func readVerticalRail(_ binding: Binding<Bool>) -> some View {
    if #available(iOS 27.1, *) {
      self.background { VerticalRailReader(isVertical: binding) }
    } else {
      self
    }
  }
}
