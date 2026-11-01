import SwiftUI
import TripSplitApplication
import TripSplitCompanionHost
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitNetworking
import TripSplitPersistence
import TripSplitSync

@main struct TripSplitApp: App {
  @State private var model: AppModel?
  @State private var error: String?
  @State private var connectivity: Connectivity?
  @State private var watch: WatchCompanionHost?
  init() {
    do {
      let store = try LocalStore()
      let sync = SyncCoordinator(store: store, api: APIClient(baseURL: APIConfiguration.baseURL))
      let model = AppModel(store: store, sync: sync)
      _connectivity = State(
        initialValue: Connectivity { [weak sync] in
          Task { await sync?.syncAll() }
        })
      if ProcessInfo.processInfo.arguments.contains("--demo"), store.trips.isEmpty {
        try DemoData.install(into: store)
      }
      if ProcessInfo.processInfo.arguments.contains("--demo"), model.referenceRates == nil {
        model.cacheReferenceRates(DemoData.referenceRates())
      }
      _model = State(initialValue: model)
      _watch = State(initialValue: WatchCompanionHost(model: model))
    } catch { _error = State(initialValue: error.localizedDescription) }
  }
  var body: some Scene {
    WindowGroup {
      if let model {
        RootView().environment(model).tint(Theme.accent).foregroundStyle(Theme.ink)
          .onContinueUserActivity(CompanionActivity.newTrip) { _ in
            model.showOnboarding = true
          }
      } else {
        ContentUnavailableView(
          "Your trips couldn’t be opened", systemImage: "externaldrive.badge.exclamationmark",
          description: Text(
            error ?? "Restart the app to try again. Your stored data has not been replaced."))
      }
    }
  }
}
