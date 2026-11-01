import SwiftUI

@main struct TripSplitApp: App {
  @State private var model: AppModel?
  @State private var error: String?
  init() {
    do {
      let store = try LocalStore()
      let model = AppModel(store: store)
      if ProcessInfo.processInfo.arguments.contains("--demo"), store.trips.isEmpty {
        try DemoData.install(into: store)
      }
      _model = State(initialValue: model)
    } catch { _error = State(initialValue: error.localizedDescription) }
  }
  var body: some Scene {
    WindowGroup {
      if let model {
        RootView().environment(model).tint(Theme.accent).foregroundStyle(Theme.ink)
      } else {
        ContentUnavailableView(
          "Your trips couldn’t be opened", systemImage: "externaldrive.badge.exclamationmark",
          description: Text(
            error ?? "Restart the app to try again. Your stored data has not been replaced."))
      }
    }
  }
}
