import Foundation
import UserNotifications

/// Keeps the watch's scheduled notifications in step with its trips and settings. Notices are
/// worked out on the watch, so they still arrive when the phone is out of reach.
@MainActor public final class WatchNotifications {
  public static let shared = WatchNotifications()

  private var scheduled: [WatchNotice]?
  private var pending: Task<Void, Never>?

  public init() {}

  /// Each kind of notice with its buttons. The categories also pick the custom long looks.
  public static var categories: Set<UNNotificationCategory> {
    Set(
      WatchNotice.Kind.allCases.map { kind in
        UNNotificationCategory(
          identifier: kind.category,
          actions: WatchNotice.Action.actions(for: kind).map {
            UNNotificationAction(identifier: $0.rawValue, title: $0.title, options: .foreground)
          },
          intentIdentifiers: [])
      })
  }

  public func register() {
    UNUserNotificationCenter.current().setNotificationCategories(Self.categories)
  }

  /// Asks once there's something to notify about, then schedules.
  public func requestAuthorization(_ model: WatchModel) async {
    guard !model.notices.isEmpty else { return }
    let center = UNUserNotificationCenter.current()
    guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
    _ = try? await center.requestAuthorization(options: [.alert, .sound])
    scheduled = nil
    reschedule(model)
  }

  /// Replaces the pending notices with the model's, shortly after the last change.
  public func reschedule(_ model: WatchModel) {
    pending?.cancel()
    pending = Task {
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      await apply(model.notices)
    }
  }

  private func apply(_ notices: [WatchNotice]) async {
    guard notices != scheduled else { return }
    let center = UNUserNotificationCenter.current()
    let kept = Set(notices.map(\.id))
    let stale = await center.pendingNotificationRequests().map(\.identifier)
      .filter { Self.isNotice($0) && !kept.contains($0) }
    center.removePendingNotificationRequests(withIdentifiers: stale)
    for notice in notices {
      // Adding with the same identifier replaces the pending one, with its latest figures.
      try? await center.add(Self.request(notice))
    }
    scheduled = notices
  }

  private static func isNotice(_ id: String) -> Bool {
    id.hasPrefix("landed.") || id.hasPrefix("wrap.")
  }

  static func request(_ notice: WatchNotice) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = notice.title
    content.body = notice.body
    content.categoryIdentifier = notice.kind.category
    content.threadIdentifier = notice.tripID
    content.userInfo = notice.userInfo
    content.sound = .default
    // An interval rather than a calendar date, so the time stays the stop's local time even
    // if the watch's own time zone changes before it fires.
    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: max(1, notice.fireDate.timeIntervalSinceNow), repeats: false)
    return UNNotificationRequest(identifier: notice.id, content: content, trigger: trigger)
  }
}
