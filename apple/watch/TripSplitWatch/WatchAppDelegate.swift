import SwiftUI
import TripSplitWatchModel
import TripSplitWatchUI
import UserNotifications
import WatchKit

/// Registers the notice categories and routes their buttons into the app.
final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
  func applicationDidFinishLaunching() {
    UNUserNotificationCenter.current().delegate = self
    WatchNotifications.shared.register()
  }

  /// Still shows a notice that fires while TripSplit is open, e.g. the evening wrap.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    let content = response.notification.request.content
    guard let kind = WatchNotice.Kind(category: content.categoryIdentifier),
      let link = WatchNotice.link(
        kind: kind, action: response.actionIdentifier, userInfo: content.userInfo)
    else { return }
    await MainActor.run { WatchLinkInbox.shared.open(link) }
  }
}

/// The long look for a TripSplit notice, set in the app's own type.
final class NoticeController: WKUserNotificationHostingController<NoticeView> {
  private var notice = NoticeView(title: "", body: "")

  override var body: NoticeView { notice }

  override func didReceive(_ notification: UNNotification) {
    let content = notification.request.content
    notice = NoticeView(
      title: content.title, body: content.body, lead: content.userInfo["lead"] as? String)
  }
}
