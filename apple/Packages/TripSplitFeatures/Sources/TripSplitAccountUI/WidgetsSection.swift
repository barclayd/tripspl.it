import SwiftUI

/// Settings › Widgets: whether amounts on the Lock Screen and in StandBy hide until unlocked.
/// The app passes the choice to its widgets whenever it changes.
struct WidgetsSection: View {
  @AppStorage("widgets.hidesAmountsWhenLocked") private var hidesAmounts = false

  var body: some View {
    Section("Widgets") {
      Toggle("Hide amounts when locked", systemImage: "eye.slash", isOn: $hidesAmounts)
      Text(
        "Amounts on your Lock Screen and in StandBy stay hidden until you unlock your iPhone. Places, gauges and labels still show."
      ).font(.footnote).foregroundStyle(.secondary)
    }
  }
}
