import SwiftUI

/// SF Rounded at the design's point sizes, scaled with Dynamic Type from the 46mm default.
public struct WatchFont: ViewModifier {
  @ScaledMetric private var size: CGFloat
  private let weight: Font.Weight
  private let design: Font.Design

  public init(
    _ size: CGFloat, _ weight: Font.Weight, design: Font.Design = .rounded,
    relativeTo style: Font.TextStyle = .body
  ) {
    _size = ScaledMetric(wrappedValue: size, relativeTo: style)
    self.weight = weight
    self.design = design
  }

  public func body(content: Content) -> some View {
    content.font(.system(size: size, weight: weight, design: design)).monospacedDigit()
  }
}

extension View {
  /// Rounded type at a design size: 900 is `.black`, 800 `.heavy`, 700 `.bold`.
  public func watchFont(
    _ size: CGFloat, _ weight: Font.Weight = .heavy, relativeTo style: Font.TextStyle = .body
  ) -> some View {
    modifier(WatchFont(size, weight, relativeTo: style))
  }

  /// Monospaced type for the departure board and passport stamps.
  public func boardFont(
    _ size: CGFloat, _ weight: Font.Weight = .heavy, relativeTo style: Font.TextStyle = .body
  ) -> some View {
    modifier(WatchFont(size, weight, design: .monospaced, relativeTo: style))
  }

  /// Letter spacing in ems, as the design specifies it.
  public func tracking(em: CGFloat, size: CGFloat) -> some View {
    tracking(em * size)
  }
}

/// Small capitalised section label, e.g. `DEPARTURES` or `BEEN THERE`.
public struct SectionLabel: View {
  let title: String
  let symbol: String?
  let colour: Color

  public init(_ title: String, symbol: String? = nil, colour: Color) {
    self.title = title
    self.symbol = symbol
    self.colour = colour
  }

  public var body: some View {
    HStack(spacing: 5) {
      if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .heavy)) }
      Text(title.uppercased()).watchFont(10, .black).tracking(em: 0.12, size: 10)
    }
    .foregroundStyle(colour)
    .padding(.horizontal, 6)
    .padding(.top, 6)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}
