import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign

/// Shown until the phone shares a trip. The button hands off to the iPhone's new trip flow.
struct NoTripsView: View {
  @State private var handingOff = false

  var body: some View {
    ScrollView {
      VStack(spacing: 6) {
        Image(systemName: "airplane")
          .font(.system(size: 26, weight: .bold))
          .rotationEffect(.degrees(-90))
          .foregroundStyle(WatchTheme.accentText)
          .frame(width: 54, height: 54)
          .background(WatchTheme.tint, in: .circle)
          .accessibilityHidden(true)
        Text("No trips yet")
          .watchFont(17, .black)
          .padding(.top, 2)
        Text("Plan one in TripSplit on your iPhone. It'll show up here.")
          .watchFont(13, .bold)
          .foregroundStyle(WatchTheme.ink2)
          .multilineTextAlignment(.center)
        Button {
          handingOff = true
        } label: {
          Label(handingOff ? "Check your iPhone" : "Open on iPhone", systemImage: "iphone")
            .watchFont(15, .heavy)
        }
        .buttonStyle(.capsule)
        .padding(.top, 6)
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 9)
    }
    .userActivity(CompanionActivity.newTrip, isActive: handingOff) { activity in
      activity.title = String(localized: "New trip")
      activity.isEligibleForHandoff = true
    }
  }
}
