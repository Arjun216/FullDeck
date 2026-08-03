import Foundation

/// What iOS will currently allow. `.provisional` and `.ephemeral` collapse into
/// `.authorized` because a reminder can be delivered under both, and the
/// distinction is not one the learner can act on.
enum ReminderAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

/// FR-13's platform seam, owned by Presentation for the same reason
/// `PurchaseService` is: Domain's questions are about words and review
/// scheduling, and a daily notification is neither.
///
/// `authorizationStatus()` does not throw — reading `UNNotificationSettings`
/// cannot fail. The other two can.
nonisolated protocol NotificationScheduler: Sendable {
    func authorizationStatus() async -> ReminderAuthorization
    func requestAuthorization() async throws -> ReminderAuthorization
    func scheduleDailyReminder(hour: Int, minute: Int) async throws
    func cancelDailyReminder() async
}

/// The composition root's default, so `AppDependencies.make()` on its own never
/// reaches the notification centre — the rule `NoPurchasesService` set for
/// StoreKit. Integration tests and previews get this one.
struct NoNotificationScheduler: NotificationScheduler {
    func authorizationStatus() async -> ReminderAuthorization { .notDetermined }
    func requestAuthorization() async throws -> ReminderAuthorization { .denied }
    func scheduleDailyReminder(hour: Int, minute: Int) async throws {}
    func cancelDailyReminder() async {}
}
