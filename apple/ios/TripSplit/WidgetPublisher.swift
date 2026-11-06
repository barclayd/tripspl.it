import Foundation
import TripSplitApplication
import TripSplitCompanion
import TripSplitDomain
import TripSplitWidgetModel
import WidgetKit

/// Keeps the Home and Lock Screen widgets current: whenever trips, spending or the reference
/// rates change, writes them to the App Group and asks WidgetKit to redraw.
@MainActor final class WidgetPublisher {
  /// Settings › Widgets › Hide amounts when locked.
  static let hidesAmountsKey = "widgets.hidesAmountsWhenLocked"

  private let model: AppModel
  private let mirror: CompanionMirror
  private var scheduled: Task<Void, Never>?
  private var observer: NSObjectProtocol?

  init(model: AppModel, mirror: CompanionMirror = .shared()) {
    self.model = model
    self.mirror = mirror
    publish()
    observe()
    // The privacy toggle lives in UserDefaults, outside the model.
    observer = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.settingsChanged() }
    }
  }

  private var hidesAmounts: Bool { UserDefaults.standard.bool(forKey: Self.hidesAmountsKey) }
  private var publishedHidesAmounts: Bool?

  func publish() {
    let rates = model.referenceRates
    let previous = mirror.read([String: FXTable].self, key: "tables")
    let settings = WidgetSnapshot.settings(in: mirror)
    // Stamp the rates only when they change, so "Rates from 2 hr ago" stays honest.
    let fresh = rates != nil && (previous?[rates!.base] != rates || settings.ratesFetchedAt == nil)
    do {
      try WidgetSnapshot.write(
        trips: model.store.trips, rates: rates, ratesFetchedAt: fresh ? Date() : nil,
        hidesAmountsWhenLocked: hidesAmounts, to: mirror)
      publishedHidesAmounts = hidesAmounts
      WidgetCenter.shared.reloadAllTimelines()
    } catch {
      // Widgets keep their last snapshot; the next change tries again.
    }
  }

  private func settingsChanged() {
    guard publishedHidesAmounts != hidesAmounts else { return }
    schedule()
  }

  private func schedule() {
    scheduled?.cancel()
    scheduled = Task {
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      publish()
    }
  }

  private func observe() {
    withObservationTracking {
      _ = model.store.trips
      _ = model.referenceRates
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        self.schedule()
        self.observe()
      }
    }
  }
}
