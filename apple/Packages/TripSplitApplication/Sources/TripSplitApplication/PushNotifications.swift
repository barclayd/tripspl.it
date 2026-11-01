import Foundation
import TripSplitDomain
import TripSplitSync
import UserNotifications

/// Phone side of nudges: gives the API this phone's push token for the signed-in account, so
/// travellers who owe can be nudged, and opens the trip when a nudge is tapped. Nudges reach a
/// paired watch the same way any iPhone notification does.
@MainActor public final class PushNotifications: NSObject, UNUserNotificationCenterDelegate {
  /// Matches the API's push category and the watch's long look.
  public static let nudgeCategory = "tripsplit.nudge"

  private let model: AppModel

  public init(model: AppModel) {
    self.model = model
    super.init()
  }

  /// Takes over notification taps. Call before launch finishes, so a tap that launched the app
  /// still lands.
  public func start() {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.setNotificationCategories([
      UNNotificationCategory(identifier: Self.nudgeCategory, actions: [], intentIdentifiers: [])
    ])
  }

  /// Asks to show nudges the first time, and says whether they can be shown.
  public func requestAuthorization() async -> Bool {
    let center = UNUserNotificationCenter.current()
    switch await center.notificationSettings().authorizationStatus {
    case .notDetermined:
      return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    case .authorized, .provisional: return true
    default: return false
    }
  }

  /// Hands a token from APNs to the API. Kept until sign-in when signed out.
  public func registered(_ token: Data, environment: PushDevice.Environment) async {
    let hex = token.map { String(format: "%02x", $0) }.joined()
    try? await model.sync.registerDevice(PushDevice(token: hex, environment: environment))
  }

  public nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }

  public nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    guard let tripID = response.notification.request.content.userInfo["trip"] as? String
    else { return }
    await open(tripID)
  }

  private func open(_ tripID: String) {
    guard let trip = model.store.trip(tripID) else { return }
    model.open(trip)
  }
}
