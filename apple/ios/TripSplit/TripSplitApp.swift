import BackgroundTasks
import SwiftUI
import TripSplitApplication
import TripSplitCompanionHost
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitNetworking
import TripSplitPersistence
import TripSplitSync
import UIKit

@main struct TripSplitApp: App {
  @UIApplicationDelegateAdaptor private var delegate: PhoneAppDelegate
  @State private var model: AppModel?
  @State private var error: String?
  @State private var connectivity: Connectivity?
  @State private var watch: WatchCompanionHost?
  @State private var widgets: WidgetPublisher?
  @State private var push: PushNotifications?
  init() {
    do {
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--offline-conversion-demo") {
          _model = State(initialValue: try OfflineConversionPreview.model())
          return
        }
        if ProcessInfo.processInfo.arguments.contains("--sync-recovery-demo") {
          _model = State(initialValue: try SyncRecoveryPreview.model())
          return
        }
      #endif
      let store = try LocalStore()
      let sync = SyncCoordinator(store: store, api: APIClient(baseURL: APIConfiguration.baseURL))
      let model = AppModel(store: store, sync: sync)
      PhoneSync.model = model
      _connectivity = State(
        initialValue: Connectivity { [weak model] in
          Task {
            await model?.sync.syncAll()
            await model?.refreshReferenceRates()
          }
        })
      if ProcessInfo.processInfo.arguments.contains("--demo"), store.trips.isEmpty {
        try DemoData.install(into: store)
      }
      if ProcessInfo.processInfo.arguments.contains("--demo"), model.referenceRates == nil {
        model.cacheReferenceRates(DemoData.referenceRates())
      }
      _model = State(initialValue: model)
      _watch = State(initialValue: WatchCompanionHost(model: model))
      _widgets = State(initialValue: WidgetPublisher(model: model))
      let push = PushNotifications(model: model)
      push.start()
      _push = State(initialValue: push)
    } catch { _error = State(initialValue: error.localizedDescription) }
  }
  var body: some Scene {
    WindowGroup {
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--widget-gallery") }) {
          WidgetGallery()
        } else {
          app
        }
      #else
        app
      #endif
    }
  }

  @ViewBuilder private var app: some View {
    if let model {
      RootView().environment(model).tint(Theme.accent).foregroundStyle(Theme.ink)
        .onContinueUserActivity(CompanionActivity.newTrip) { _ in
          model.showOnboarding = true
        }
        // Once signed in, others on a trip can nudge you, so ask then and keep the token fresh.
        .task(id: model.sync.session?.user.id) {
          delegate.push = push
          guard model.sync.session != nil, let push, await push.requestAuthorization() else {
            return
          }
          UIApplication.shared.registerForRemoteNotifications()
        }
    } else {
      ContentUnavailableView(
        "Your trips couldn’t be opened", systemImage: "externaldrive.badge.exclamationmark",
        description: Text(
          error ?? "Restart the app to try again. Your stored data has not been replaced."))
    }
  }
}

/// Passes the APNs token on for nudges.
final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
  var push: PushNotifications?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: PhoneSync.identifier, using: .main) {
      task in
      MainActor.assumeIsolated { PhoneSync.run(task) }
    }
    return true
  }

  func application(
    _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data
  ) {
    #if DEBUG
      let environment = PushDevice.Environment.sandbox
    #else
      let environment = PushDevice.Environment.production
    #endif
    Task { await push?.registered(token, environment: environment) }
  }
}

/// iOS chooses the execution time; reconnect and foreground sync remain immediate.
@MainActor enum PhoneSync {
  static let identifier = "it.tripspl.TripSplit.sync"
  static weak var model: AppModel?

  static func schedule() {
    guard model?.sync.session != nil else { return }
    let request = BGProcessingTaskRequest(identifier: identifier)
    request.requiresNetworkConnectivity = true
    try? BGTaskScheduler.shared.submit(request)
  }

  static func run(_ backgroundTask: BGTask) {
    schedule()
    let work = Task { @MainActor in
      guard let model else {
        backgroundTask.setTaskCompleted(success: false)
        return
      }
      while model.sync.isSyncing && !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(100))
      }
      await model.sync.syncAll()
      if !Task.isCancelled { await model.refreshReferenceRates() }
      if !Task.isCancelled { await model.sync.syncAll() }
      model.sync.stopRetries()
      backgroundTask.setTaskCompleted(success: !Task.isCancelled && model.sync.message == nil)
    }
    backgroundTask.expirationHandler = { work.cancel() }
  }
}
