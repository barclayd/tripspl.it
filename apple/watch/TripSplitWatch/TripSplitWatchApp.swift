import SwiftUI
import TripSplitWatchModel
import TripSplitWatchUI
import WidgetKit

@main struct TripSplitWatchApp: App {
  @State private var model: WatchModel
  @Environment(\.scenePhase) private var scenePhase

  init() {
    let model: WatchModel
    if ProcessInfo.processInfo.arguments.contains("--demo"), let demo = try? WatchModel.demo() {
      model = demo
    } else {
      model = .live(baseURL: APIConfiguration.baseURL)
    }
    // Complications read what the model mirrors to the App Group, so redraw them on every change.
    model.onChange = { WidgetCenter.shared.reloadAllTimelines() }
    _model = State(initialValue: model)
  }

  var body: some Scene {
    WindowGroup {
      TripsRootView()
        .environment(model)
        .task(id: scenePhase) {
          guard scenePhase == .active else { return }
          model.now = Date()
          await model.refreshRates()
        }
    }
  }
}
