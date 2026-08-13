import Foundation
import UserNotifications

/// The **only** file in the app that imports `UserNotifications` — the same
/// containment rule `StoreKitPurchaseService` follows for StoreKit.
///
/// Deliberately untested: every method is a direct passthrough, and a unit test
/// here would assert that Apple's framework was called, which is not a fact
/// about this app. The XCUITest and a manual device check are the honest
/// coverage, and known-issues.md records it rather than letting it pass as
/// covered.
nonisolated struct UNNotificationScheduler: NotificationScheduler {
    /// One constant identifier is what makes "exactly one reminder" (FR-13)
    /// true without bookkeeping: adding a request with an existing identifier
    /// replaces it.
    static let reminderIdentifier = "arjunpathak.FullDeck.dailyReminder"

    func authorizationStatus() async -> ReminderAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized, .provisional, .ephemeral: return .authorized
        default: return .denied
        }
    }

    func requestAuthorization() async throws -> ReminderAuthorization {
        let granted = try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        return granted ? .authorized : .denied
    }

    /// Split out of `scheduleDailyReminder` so it can be asserted on without a
    /// notification centre. What it builds is *this app's* contract rather than
    /// Apple's — the constant identifier is how FR-13's "exactly one reminder"
    /// holds, and `repeats: true` is how it is daily rather than once. Both are
    /// one word away from a defect that only shows up 24 hours later, on a real
    /// device, which is the worst possible place to find it (Phase 13).
    static func reminderRequest(hour: Int, minute: Int) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        // Title only. A repeating local notification cannot know the due count
        // at fire time without background refresh (out of scope, §4), so any
        // body promising ready cards is false on the days there are none.
        content.title = String(localized: "Time to study")
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return UNNotificationRequest(
            identifier: reminderIdentifier, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
    }

    func scheduleDailyReminder(hour: Int, minute: Int) async throws {
        try await UNUserNotificationCenter.current()
            .add(Self.reminderRequest(hour: hour, minute: minute))
    }

    func cancelDailyReminder() async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])
    }
}
