import AppIntents
import TripSplitWatchModel

/// Opens the watch app at a TripSplit link, e.g. from the Smart Stack card's Convert and Log
/// buttons. Compiled into the app and the widget extension so the app runs it on launch.
struct OpenWatchLinkIntent: AppIntent {
  static let title: LocalizedStringResource = "Open in TripSplit"
  static let isDiscoverable = false
  static let supportedModes: IntentModes = .foreground(.immediate)

  @Parameter(title: "Link") var link: String

  init() {}

  init(_ link: WatchLink) {
    self.link = link.url.absoluteString
  }

  @MainActor func perform() async throws -> some IntentResult {
    if let url = URL(string: link), let link = WatchLink(url: url) {
      WatchLinkInbox.shared.open(link)
    }
    return .result()
  }
}
