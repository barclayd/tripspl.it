import SwiftUI
import TripSplitWatchModel
import TripSplitWatchUI
import WatchKit
import WidgetKit

@main struct TripSplitWatchApp: App {
  @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
  @State private var model: WatchModel
  @Environment(\.scenePhase) private var scenePhase

  init() {
    let model: WatchModel
    if ProcessInfo.processInfo.arguments.contains("--demo"), let demo = try? WatchModel.demo() {
      model = demo
    } else {
      model = .live(baseURL: APIConfiguration.baseURL)
    }
    // Complications read what the model mirrors to the App Group, so redraw them on every change,
    // and the notices are worked out from the same trips.
    model.onChange = { [weak model] in
      WidgetCenter.shared.reloadAllTimelines()
      if let model { WatchNotifications.shared.reschedule(model) }
    }
    _model = State(initialValue: model)
  }

  var body: some Scene {
    WindowGroup {
      TripsRootView()
        .environment(model)
        .task(id: scenePhase) {
          guard scenePhase == .active else { return }
          model.now = Date()
          WatchNotifications.shared.reschedule(model)
          await WatchNotifications.shared.requestAuthorization(model)
          await model.refreshRates()
        }
    }
    WKNotificationScene(controller: NoticeController.self, category: WatchNotice.Kind.landed.category)
    WKNotificationScene(
      controller: NoticeController.self, category: WatchNotice.Kind.eveningWrap.category)
    WKNotificationScene(controller: NoticeController.self, category: WatchNotice.Kind.nudge.category)
  }
}
