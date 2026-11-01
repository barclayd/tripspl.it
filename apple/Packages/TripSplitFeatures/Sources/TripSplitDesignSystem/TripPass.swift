import SwiftUI

/// What the new-trip pass shows while a trip is being planned: the whole route on one pass.
package struct TripPassContent: Hashable, Sendable {
  /// A field's value, dimmed until its step has been answered.
  package struct Value: Hashable, Sendable {
    package init(_ text: String, answered: Bool) {
      self.text = text
      self.answered = answered
    }
    package var text: String
    package var answered: Bool
  }

  package init(
    from: String, fromName: String, to: String, toName: String, placeholder: Bool,
    date: Value, pax: Value, budget: Value, flags: String,
    highlight: BoardingPassContent.Highlight? = nil
  ) {
    self.from = from
    self.fromName = fromName
    self.to = to
    self.toName = toName
    self.placeholder = placeholder
    self.date = date
    self.pax = pax
    self.budget = budget
    self.flags = flags
    self.highlight = highlight
  }

  package var from: String
  package var fromName: String
  package var to: String
  package var toName: String
  /// No destination yet: the TO code is dimmed.
  package var placeholder: Bool
  package var date: Value
  package var pax: Value
  package var budget: Value
  package var flags: String
  /// `.field(1)` date, `.field(2)` pax, `.field(3)` budget.
  package var highlight: BoardingPassContent.Highlight?
}

/// The new-trip pass on the open Duo: a compact sidebar pass with the budget in its stub, or a
/// full-width pass with a "BOARDING PASS" stub and all three fields.
package struct TripPass: View {
  package enum Size: Sendable { case sidebar, full }

  package init(_ content: TripPassContent, size: Size, cleared: Bool = false) {
    self.content = content
    self.size = size
    self.cleared = cleared
  }

  package var content: TripPassContent
  package var size: Size
  package var cleared: Bool

  private var full: Bool { size == .full }
  private var stubWidth: CGFloat { full ? 120 : 64 }
  private var label: CGFloat { full ? 10 : 8.5 }
  private var value: CGFloat { full ? 16 : 13.5 }
  private var palette: PassPalette { PassPalette(flag: "") }

  package var body: some View {
    VStack(spacing: 0) {
      header
      HStack(spacing: 0) {
        HStack(alignment: .top, spacing: full ? 14 : 9) {
          Barcode(key: content.to + content.date.text, length: 160, axis: .vertical)
            .foregroundStyle(Theme.ink).opacity(0.85).frame(width: full ? 16 : 11)
            .clipShape(RoundedRectangle(cornerRadius: 2))
          VStack(alignment: .leading, spacing: full ? 12 : 8) {
            route
            fields
          }
        }
        .padding(
          full
            ? EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 16)
            : EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        stub
      }
      .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(Theme.ink)
    .background(palette.body)
    .clipShape(PassShape(stub: stubWidth))
    .compositingGroup()
    .shadow(color: .black.opacity(0.12), radius: 7, y: 8)
    .overlay(alignment: .topTrailing) {
      if cleared {
        Stamp(delay: 0.35) {
          Text("CLEARED").font(.system(size: 15, weight: .black, design: .monospaced))
            .tracking(1.8).foregroundStyle(Theme.accentText)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Theme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accentText, lineWidth: 3))
        }
        .padding(.trailing, stubWidth + 16).padding(.top, full ? 52 : 44)
        .allowsHitTesting(false)
        .accessibilityLabel("Cleared")
      }
    }
    .animation(.easeOut(duration: 0.3), value: content.highlight)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }

  private var accessibilityText: String {
    var parts = ["New trip", "\(content.fromName) to \(content.toName)"]
    if content.date.answered { parts.append("Dates \(content.date.text)") }
    if content.pax.answered { parts.append("\(content.pax.text) travelling") }
    if content.budget.answered { parts.append("Budget \(content.budget.text)") }
    return parts.joined(separator: ", ")
  }

  private var header: some View {
    HStack(spacing: 0) {
      HStack(spacing: 6) {
        Image(systemName: "airplane").font(.system(size: full ? 14 : 11.5, weight: .bold))
        Text("NEW TRIP").font(.system(size: full ? 12 : 10.5, weight: .black))
          .tracking(full ? 1.44 : 1.26).lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 14)
      Text(full ? "BOARDING PASS" : "PASS")
        .font(.system(size: full ? 11 : 9.5, weight: .black)).tracking(full ? 0.66 : 1.33)
        .lineLimit(1).minimumScaleFactor(0.8)
        .frame(width: stubWidth, height: full ? 36 : 28)
        .overlay(alignment: .leading) { DashedRule(color: .white.opacity(0.55)) }
    }
    .foregroundStyle(.white)
    .frame(height: full ? 36 : 28)
    .background(palette.band)
  }

  private var route: some View {
    HStack(alignment: .top, spacing: 6) {
      airport("FROM", content.from, content.fromName, colour: palette.text)
        .layoutPriority(1)
      ZStack(alignment: .top) {
        Arc().stroke(Theme.secondary, style: .init(lineWidth: 1.4, dash: [3.5, 3]))
        Image(systemName: "airplane").font(.system(size: full ? 19 : 14, weight: .bold))
          .foregroundStyle(palette.plane).padding(.top, full ? 6 : 5)
      }
      .frame(minWidth: 24, maxWidth: .infinity).frame(height: full ? 46 : 36).padding(.top, 6)
      airport(
        "TO", content.to, content.toName,
        colour: content.placeholder ? Theme.tertiary : palette.text, trailing: true
      )
      .padding(.horizontal, 6).padding(.bottom, 2)
      .background(
        content.highlight == .destination ? palette.highlight : .clear,
        in: RoundedRectangle(cornerRadius: 10)
      )
      .padding(.horizontal, -6)
      .layoutPriority(1)
    }
  }

  private func airport(
    _ title: String, _ code: String, _ name: String, colour: Color, trailing: Bool = false
  ) -> some View {
    VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
      Text(title).font(.system(size: label, weight: .black)).tracking(label * 0.12)
        .foregroundStyle(palette.text)
      Text(code).font(.system(size: full ? 34 : 20, weight: .black)).foregroundStyle(colour)
        .lineLimit(1).minimumScaleFactor(0.6)
      Text(name).font(.system(size: full ? 14 : 11.5, weight: .heavy)).lineLimit(1)
        .minimumScaleFactor(0.8)
    }
  }

  /// Spread edge to edge with even gaps between, each field centred on its label.
  private var fields: some View {
    HStack(spacing: 0) {
      field("DATE", content.date, index: 1)
      Spacer(minLength: 14)
      field("PAX", content.pax, index: 2)
      if full {
        Spacer(minLength: 14)
        field("BUDGET", content.budget, index: 3)
      }
    }
  }

  private func field(_ title: String, _ field: TripPassContent.Value, index: Int) -> some View {
    VStack(spacing: 0) {
      Text(title).font(.system(size: label, weight: .black)).tracking(label * 0.12)
        .foregroundStyle(palette.text)
      Text(field.text).font(.system(size: value, weight: .black)).lineLimit(1)
        .minimumScaleFactor(0.75)
        .foregroundStyle(field.answered ? Theme.ink : Theme.tertiary)
        .contentTransition(.numericText())
    }
    .padding(.horizontal, 6).padding(.vertical, 3)
    .background(
      content.highlight == .field(index) ? palette.highlight : .clear,
      in: RoundedRectangle(cornerRadius: 8)
    )
    .padding(.horizontal, -6)
  }

  private var stub: some View {
    VStack(spacing: 6) {
      Text(content.flags.isEmpty ? "?" : content.flags)
        .font(.system(size: full ? 28 : 20)).tracking(1).lineLimit(1).minimumScaleFactor(0.5)
      Spacer(minLength: 0)
      if full {
        VStack(spacing: 0) {
          Text("GATE").font(.system(size: 10, weight: .black)).tracking(1.2)
            .foregroundStyle(palette.text)
          Text("01").font(.system(size: 20, weight: .black))
        }
      } else {
        VStack(spacing: 0) {
          Text("BUDGET").font(.system(size: 8.5, weight: .black)).tracking(1)
            .foregroundStyle(palette.text)
          Text(content.budget.text).font(.system(size: 14, weight: .black)).lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(content.budget.answered ? Theme.ink : Theme.tertiary)
            .contentTransition(.numericText())
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(
          content.highlight == .field(3) ? palette.highlight : .clear,
          in: RoundedRectangle(cornerRadius: 8))
      }
      Spacer(minLength: 0)
      Barcode(key: content.flags + content.to, length: full ? 96 : 50, axis: .horizontal)
        .foregroundStyle(Theme.ink).opacity(0.85)
        .frame(width: full ? 96 : 50, height: full ? 24 : 16)
    }
    .padding(.vertical, full ? 14 : 10).padding(.horizontal, full ? 10 : 6)
    .frame(width: stubWidth)
    .frame(maxHeight: .infinity)
    .overlay(alignment: .leading) { DashedRule(color: Theme.line2) }
  }
}
