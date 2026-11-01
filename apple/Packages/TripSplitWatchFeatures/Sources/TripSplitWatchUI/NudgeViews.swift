import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign
import TripSplitWatchModel
import WatchKit

/// The accent "Nudge Tom" on E2 and H5. Once they've had today's nudge it greys out, as the
/// server only lets one through per person per trip day.
struct NudgeButton: View {
  let name: String
  let nudged: Bool
  var height: CGFloat = 38
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(nudged ? "Nudged today" : "Nudge \(name)")
        .watchFont(15, .black)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .contentTransition(.opacity)
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
    .buttonStyle(.plain)
    .foregroundStyle(nudged ? WatchTheme.ink2 : .white)
    .background(nudged ? WatchTheme.card2 : WatchTheme.accent, in: .capsule)
    .contentShape(.capsule)
    .disabled(nudged)
    .accessibilityLabel(nudged ? "\(name) was nudged today" : "Nudge \(name)")
  }
}

/// E3 · Nudged. The avatar wobbles with a two-tap haptic, then Done goes back. With Reduce
/// Motion it fades in still.
struct NudgedView: View {
  let pages: TripPages
  let travellerID: String
  /// What they owe you, e.g. "£66".
  let amount: String
  let done: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var wobble = 0

  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)
      PersonAvatar(pages: pages, id: travellerID, size: 64)
        .keyframeAnimator(initialValue: 0.0, trigger: wobble) { content, angle in
          content.rotationEffect(.degrees(angle), anchor: UnitPoint(x: 0.5, y: 0.9))
        } keyframes: { _ in
          // Swings out and settles: ±14° decaying over about 0.7s.
          KeyframeTrack {
            CubicKeyframe(-14, duration: 0.144)
            CubicKeyframe(12, duration: 0.144)
            CubicKeyframe(-9, duration: 0.144)
            CubicKeyframe(6, duration: 0.144)
            CubicKeyframe(0, duration: 0.144)
          }
        }
      Text("Nudge sent")
        .watchFont(17, .black)
        .padding(.top, 12)
      Text("\(pages.name(travellerID)) gets a buzz with a link to pay you \(amount).")
        .watchFont(12, .bold)
        .foregroundStyle(WatchTheme.ink2)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 3)
      Spacer(minLength: 8)
      Button(action: done) {
        Text("Done")
          .watchFont(15, .black)
          .frame(maxWidth: .infinity)
          .frame(height: 38)
      }
      .buttonStyle(.plain)
      .background(WatchTheme.card2, in: .capsule)
      .contentShape(.capsule)
      .handGestureShortcut(.primaryAction)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .contain)
    .task {
      if !reduceMotion { wobble += 1 }
      // The two-tap: a notification haptic, then another as the avatar swings back.
      WKInterfaceDevice.current().play(.notification)
      try? await Task.sleep(for: .milliseconds(290))
      guard !Task.isCancelled else { return }
      WKInterfaceDevice.current().play(.notification)
    }
  }
}

extension TripPages {
  /// What this person owes you, rounded for display, if anything.
  func owedToYou(by id: String) -> String? {
    guard id != you,
      let settlement = settlements.first(where: { $0.from == id && $0.to == you })
    else { return nil }
    return WatchCurrency.whole(settlement.amount, currency)
  }
}
