import SwiftUI
import TripSplitDesignSystem
import TripSplitDomain

/// A till receipt prints out of a slot after a new expense saves, stamped paid or planned.
struct ReceiptView: View {
  var expense: Expense
  var trip: TripSnapshot
  var finish: () -> Void
  @State private var printed = false
  @State private var finished = false
  @State private var paperHeight: CGFloat = 1000
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 0) {
      Text(expense.status == .paid ? "Printing your receipt…" : "Printing your plan…")
        .typeface(15, .heavy, relativeTo: .subheadline, maximum: 1.4)
        .foregroundStyle(Theme.secondary)
        .opacity(printed ? 1 : 0)
        .padding(.bottom, 18)
      slot.zIndex(1)
      paper
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { paperHeight = $0 }
        .offset(y: printed ? 0 : -paperHeight * 1.01)
        .frame(width: 268)
        .clipped()
        .padding(.top, -8)
      Text("Tap to close")
        .typeface(12.5, .bold, relativeTo: .caption, maximum: 1.4)
        .foregroundStyle(Theme.tertiary)
        .opacity(printed ? 1 : 0)
        .animation(.easeOut(duration: 0.3).delay(reduceMotion ? 0 : 1.4), value: printed)
        .padding(.top, 22)
    }
    .padding(.horizontal, 18)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .onTapGesture { close() }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
    .accessibilityHint("Closes the receipt")
    .accessibilityAction { close() }
    .task {
      withAnimation(reduceMotion ? nil : Motion.receipt.delay(0.15)) { printed = true }
      try? await Task.sleep(for: .seconds(2.6))
      close()
    }
  }

  private func close() {
    guard !finished else { return }
    finished = true
    finish()
  }

  private var slot: some View {
    Capsule()
      .fill(Theme.ink)
      .frame(width: 296, height: 16)
      .overlay(alignment: .bottom) {
        Capsule().fill(.black.opacity(0.6)).frame(height: 5)
          .padding(.horizontal, 12).padding(.bottom, 3)
      }
      .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
      .accessibilityHidden(true)
  }

  // MARK: - Paper

  private var paper: some View {
    let home = expense.homeMinor(in: trip.homeCurrency)
    let local = Money.minor(expense.amountMinor) ?? 0
    let total = home.map { Money.format($0, trip.homeCurrency) } ?? Money.format(local, expense.currency)
    let count = expense.splitWith.count
    return VStack(spacing: 0) {
      VStack(spacing: 4) {
        Text("TRIPSPLIT")
          .typeface(14, .heavy, design: .monospaced, tracking: 0.24, maximum: 1.3)
          .foregroundStyle(Theme.receiptInk)
        Text(whereLine).foregroundStyle(Theme.receiptMuted)
        Text(dateLine).foregroundStyle(Theme.receiptMuted)
      }
      .typeface(11, .semibold, design: .monospaced, maximum: 1.3)
      .multilineTextAlignment(.center)
      rule
      VStack(spacing: 7) {
        line(expense.title.uppercased(), Money.format(local, expense.currency))
        if expense.currency != trip.homeCurrency {
          line("IN \(trip.homeCurrency)", home.map { Money.format($0, trip.homeCurrency) } ?? "PENDING")
        }
        line(expense.status == .paid ? "PAID BY" : "PAYING", trip.displayName(expense.paidBy).uppercased())
        line(
          "SPLIT",
          count == 1 ? "JUST \(trip.displayName(expense.splitWith[0]).uppercased())" : "\(count) WAYS")
        if count > 1, let home, let each = Money.split(home, among: expense.splitWith).values.max() {
          line("EACH", Money.format(each, trip.homeCurrency))
        }
      }
      rule
      HStack(alignment: .firstTextBaseline) {
        Text("TOTAL").typeface(12.5, .heavy, design: .monospaced, tracking: 0.14, maximum: 1.3)
        Spacer(minLength: 8)
        Text(total).typeface(20, .heavy, design: .monospaced, maximum: 1.3).monospacedDigit()
      }
      .foregroundStyle(Theme.receiptInk)
      Barcode(key: expense.id, length: 150)
        .frame(width: 150, height: 26)
        .foregroundStyle(Theme.receiptInk)
        .padding(.top, 18)
    }
    .typeface(12.5, .semibold, design: .monospaced, maximum: 1.3)
    .padding(.top, 28).padding(.horizontal, 20).padding(.bottom, 32)
    .frame(width: 268)
    .background(Theme.receiptPaper, in: ZigzagBottom())
    .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
    .overlay(alignment: .topTrailing) { stamp.padding(.top, 70).padding(.trailing, 14) }
    .environment(\.colorScheme, .light)
    .accessibilityElement(children: .combine)
  }

  private func line(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(label).foregroundStyle(Theme.receiptMuted).lineLimit(1)
      Spacer(minLength: 4)
      Text(value).foregroundStyle(Theme.receiptInk).monospacedDigit().lineLimit(1)
    }
  }

  private var rule: some View {
    Line()
      .stroke(Theme.receiptRule, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
      .frame(height: 1.5)
      .padding(.vertical, 14)
      .accessibilityHidden(true)
  }

  private var stamp: some View {
    let paid = expense.status == .paid
    let colour = paid ? OKLCH(0.55, 0.15, 150).color : OKLCH(0.5, 0.16, 255).color
    return Stamp(delay: reduceMotion ? 0 : 1.2) {
      Text(paid ? "PAID" : "PLANNED")
        .typeface(17, .black, tracking: 0.12, maximum: 1.2)
        .foregroundStyle(colour)
        .padding(.vertical, 4).padding(.horizontal, 10)
        .overlay {
          RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(colour, lineWidth: 3)
        }
    }
    .accessibilityLabel(paid ? "Paid" : "Planned")
  }

  // MARK: - Header lines

  /// "LISBON · DAY 3", "GETTING THERE" or the leg's own title.
  private var whereLine: String {
    switch expense.attachment.kind {
    case .day:
      let place = trip.stop(for: expense.attachment)?.place.uppercased() ?? trip.name.uppercased()
      return "\(place) · \(trip.shortTitle(for: expense.attachment).uppercased())"
    case .leg:
      switch trip.legs.first(where: { $0.id == expense.attachment.id })?.kind {
      case .outbound: return "GETTING THERE"
      case .return: return "GETTING HOME"
      default: return trip.shortTitle(for: expense.attachment).uppercased()
      }
    }
  }

  /// "SAT 1 NOV 2026 · 14:32", the attached day's date with the time it was added.
  private var dateLine: String {
    let date =
      expense.attachment.kind == .day
      ? trip.days.first { $0.id == expense.attachment.id }?.date
      : trip.legs.first { $0.id == expense.attachment.id }?.date
    let day = date.map { CivilDate.display($0, format: "EEE d MMM yyyy") } ?? ""
    let time = Date.now.formatted(date: .omitted, time: .shortened)
    return "\(day) · \(time)".uppercased()
  }
}

/// A receipt's torn edge: straight sides and top with a row of 14×9 teeth along the bottom.
struct ZigzagBottom: Shape {
  var tooth: CGSize = .init(width: 14, height: 9)

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let base = rect.maxY - tooth.height
    path.move(to: .init(x: rect.minX, y: rect.minY))
    path.addLine(to: .init(x: rect.maxX, y: rect.minY))
    path.addLine(to: .init(x: rect.maxX, y: base))
    let teeth = max(1, Int((rect.width / tooth.width).rounded()))
    let step = rect.width / CGFloat(teeth)
    for index in stride(from: teeth, to: 0, by: -1) {
      let right = rect.minX + CGFloat(index) * step
      path.addLine(to: .init(x: right - step / 2, y: rect.maxY))
      path.addLine(to: .init(x: right - step, y: base))
    }
    path.closeSubpath()
    return path
  }
}

private struct Line: Shape {
  func path(in rect: CGRect) -> Path {
    Path { $0.move(to: .init(x: rect.minX, y: rect.midY)); $0.addLine(to: .init(x: rect.maxX, y: rect.midY)) }
  }
}
