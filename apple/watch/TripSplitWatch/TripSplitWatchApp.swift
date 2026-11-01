import SwiftUI
import TripSplitWatchModel
import TripSplitWatchUI

@main struct TripSplitWatchApp: App {
  @State private var model: WatchModel
  @Environment(\.scenePhase) private var scenePhase

  init() {
    if ProcessInfo.processInfo.arguments.contains("--demo"), let demo = try? WatchModel.demo() {
      _model = State(initialValue: demo)
    } else {
      _model = State(initialValue: .live(baseURL: APIConfiguration.baseURL))
    }
  }

  var body: some Scene {
    WindowGroup {
      TripsRootView()
        .environment(model)
        .task(id: scenePhase) {
          guard scenePhase == .active else { return }
          model.now = Date()
          await model.refreshLocalRate()
        }
    }
  }
}
