import AppIntents
import SwiftUI
import TripSplitDesignSystem
import TripSplitWatchModel
import TripSplitWidgetModel
import WidgetKit

/// Control Centre's Quick convert (D1): opens the converter on today's pair.
struct QuickConvertControl: ControlWidget {
  static let kind = "it.tripspl.TripSplit.control.convert"

  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: Self.kind, provider: Provider()) { title in
      ControlWidgetButton(action: OpenWatchLinkIntent(.convert)) {
        Label {
          Text("Quick convert")
          Text(title).privacySensitive()
        } icon: {
          Image(systemName: "arrow.left.arrow.right")
        }
      }
      .tint(Theme.accent)
    }
    .displayName("Quick convert")
    .description("Convert prices into your home currency at a glance.")
  }

  struct Provider: ControlValueProvider {
    var previewValue: String { "Your currency" }

    func currentValue() async throws -> String {
      await MainActor.run { PhoneWidgets.shared().convertTitle } ?? "Your currency"
    }
  }
}

/// Control Centre's Log expense (D1): opens Log at the amount step for the trip under way.
struct LogExpenseControl: ControlWidget {
  static let kind = "it.tripspl.TripSplit.control.log"

  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: Self.kind, provider: Provider()) { place in
      ControlWidgetButton(action: OpenWatchLinkIntent(.log())) {
        Label {
          Text("Log expense")
          Text(place).privacySensitive()
        } icon: {
          Image(systemName: "plus")
        }
        .controlWidgetActionHint("Hold to log an expense")
      }
      .tint(Theme.accent)
    }
    .displayName("Log expense")
    .description("Log an expense on the trip you're on.")
  }

  struct Provider: ControlValueProvider {
    var previewValue: String { "Your trip" }

    func currentValue() async throws -> String {
      await MainActor.run { PhoneWidgets.shared().logPlace } ?? "Your trip"
    }
  }
}
