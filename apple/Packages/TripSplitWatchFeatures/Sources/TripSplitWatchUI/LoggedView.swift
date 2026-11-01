import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign
import TripSplitWatchModel

/// F5 · Logged. The receipt prints out of a slot, then a tick and "Logged" before the sheet closes.
/// Saved without the phone, it hands over to H4 instead of closing.
struct LoggedView: View {
  let receipt: LogExpense.Receipt
  let savedOffline: Bool
  let rateNote: String?
  let done: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var printed = false
  @State private var ticked = false
  @State private var showingOffline = false

  var body: some View {
    Group {
      if showingOffline {
        SavedOfflineView(rateNote: rateNote, done: done)
          .transition(.opacity)
      } else {
        printing.transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.black)
    .sensoryFeedback(.success, trigger: ticked)
    .task {
      if reduceMotion {
        withAnimation(.easeInOut(duration: 0.3)) { printed = true }
      } else {
        withAnimation(.easeOut(duration: 1.4)) { printed = true }
      }
      try? await Task.sleep(for: .milliseconds(reduceMotion ? 300 : 700))
      withAnimation(.spring(duration: 0.35, bounce: 0.45)) { ticked = true }
      try? await Task.sleep(for: .milliseconds(reduceMotion ? 1900 : 2300))
      guard !Task.isCancelled else { return }
      if savedOffline {
        withAnimation(.easeInOut(duration: 0.3)) { showingOffline = true }
      } else {
        done()
      }
    }
  }

  private var printing: some View {
    VStack(spacing: 0) {
      Capsule()
        .fill(WatchTheme.card2)
        .frame(height: 6)
        .padding(.horizontal, 2)
        .zIndex(1)
      ReceiptView(receipt: receipt)
        .padding(.horizontal, 14)
        // Out of the slot: the paper starts tucked above it and slides down into view.
        .visualEffect { content, proxy in
          content.offset(y: printed || reduceMotion ? 0 : -proxy.size.height)
        }
        .opacity(reduceMotion && !printed ? 0 : 1)
        .clipped()
        .padding(.top, -2)
      Spacer(minLength: 4)
      HStack(spacing: 8) {
        Image(systemName: "checkmark")
          .font(.system(size: 15, weight: .black))
          .foregroundStyle(.black)
          .frame(width: 30, height: 30)
          .background(WatchTheme.good, in: .circle)
        Text("Logged").watchFont(22, .black)
      }
      .scaleEffect(ticked ? 1 : 0.6)
      .opacity(ticked ? 1 : 0)
      .padding(.bottom, 6)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Logged")
    }
    .padding(.horizontal, 10)
    .ignoresSafeArea(edges: .bottom)
  }
}

/// The printed receipt: where and when, what it was, who shares it and each share.
struct ReceiptView: View {
  let receipt: LogExpense.Receipt

  private static let ink = Color(hex: 0x23201B)
  private static let muted = Color(hex: 0x7A7368)
  private static let dash = Color(hex: 0xCFC8BB)

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(receipt.heading.uppercased())
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .tracking(1)
        .foregroundStyle(Self.muted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
      rule
      HStack(alignment: .firstTextBaseline) {
        Text(receipt.category.uppercased())
        Spacer(minLength: 4)
        Text(receipt.amount)
      }
      .font(.system(size: 13, weight: .heavy, design: .monospaced))
      if let home = receipt.home {
        Text(home)
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .foregroundStyle(Self.muted)
          .frame(maxWidth: .infinity, alignment: .trailing)
          .padding(.top, -4)
      }
      rule
      VStack(alignment: .leading, spacing: 1) {
        Text(receipt.people.count > 1 ? "SPLIT \(receipt.people.count) WAYS" : "JUST YOU")
        if receipt.people.count > 1 {
          Text(receipt.people.joined(separator: " · ").uppercased())
        }
      }
      .font(.system(size: 9, weight: .semibold, design: .monospaced))
      if let each = receipt.each {
        rule
        HStack(alignment: .firstTextBaseline) {
          Text("EACH")
          Spacer(minLength: 4)
          Text(each)
        }
        .font(.system(size: 13, weight: .heavy, design: .monospaced))
      }
    }
    .lineLimit(2)
    .minimumScaleFactor(0.7)
    .foregroundStyle(Self.ink)
    .padding(.horizontal, 10)
    .padding(.top, 9)
    .padding(.bottom, 16)
    .background(Color(hex: 0xFFFDF6), in: ZigZagEdge(tooth: 6))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
  }

  private var rule: some View {
    Line()
      .stroke(Self.dash, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
      .frame(height: 1)
  }

  private var label: String {
    var parts = [receipt.heading, "\(receipt.category) \(receipt.amount)"]
    if let home = receipt.home { parts.append("about \(home)") }
    if let each = receipt.each {
      parts.append("split \(receipt.people.count) ways, \(each) each")
    }
    return parts.joined(separator: ", ")
  }
}

/// A rectangle whose bottom edge is torn into teeth, like till paper.
struct ZigZagEdge: Shape {
  let tooth: CGFloat

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let count = max(Int((rect.width / (tooth * 2)).rounded()), 1)
    let width = rect.width / CGFloat(count)
    path.move(to: .init(x: rect.minX, y: rect.minY))
    path.addLine(to: .init(x: rect.maxX, y: rect.minY))
    path.addLine(to: .init(x: rect.maxX, y: rect.maxY))
    for index in (0..<count).reversed() {
      let x = rect.minX + CGFloat(index) * width
      path.addLine(to: .init(x: x + width / 2, y: rect.maxY - tooth))
      path.addLine(to: .init(x: x, y: rect.maxY))
    }
    path.closeSubpath()
    return path
  }
}

struct Line: Shape {
  func path(in rect: CGRect) -> Path {
    Path { $0.move(to: .init(x: rect.minX, y: rect.midY)); $0.addLine(to: .init(x: rect.maxX, y: rect.midY)) }
  }
}

/// H4 · Saved offline. Logging never waits for the phone; it syncs when the phone or Wi-Fi is back.
struct SavedOfflineView: View {
  let rateNote: String?
  let done: () -> Void

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        Image(systemName: "icloud.slash")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(WatchTheme.amber)
          .frame(width: 52, height: 52)
          .background(Color(hex: 0x2A2412), in: .circle)
          .accessibilityHidden(true)
        Text("Saved on your watch")
          .watchFont(17, .black)
          .multilineTextAlignment(.center)
          .padding(.top, 10)
        Text(["Syncs when your iPhone or Wi‑Fi is back.", rateNote].compactMap { $0 }.joined(separator: " "))
          .watchFont(13, .bold)
          .foregroundStyle(WatchTheme.ink2)
          .multilineTextAlignment(.center)
          .padding(.top, 4)
        Button(action: done) {
          Text("OK").watchFont(16, .black)
        }
        .buttonStyle(CapsuleButtonStyle(fill: .white.opacity(0.17)))
        .padding(.top, 14)
      }
      .padding(.horizontal, 4)
    }
  }
}
