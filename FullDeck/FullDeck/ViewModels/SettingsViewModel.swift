import Domain
import Foundation
import Observation

/// Owns the two things the learner can change: the daily reminder (FR-13) and
/// the new-word cap (FR-4).
///
/// Separate from `CreditsViewModel` on purpose: credits is failable async pack
/// I/O, this is preferences. Folding them together would make every reminder
/// test set up packs and a manifest before reaching its assertion — the same
/// argument `PurchaseViewModel` makes for staying out of
/// `LanguageSelectionViewModel`.
@MainActor
@Observable
final class SettingsViewModel {
    static let newWordsPerDayKey = "newWordsPerDay"
    /// 1000 words at 30/day is a bit over a month; at 1/day it is most of three
    /// years. Both ends are defensible, and the Stepper clamps to them.
    static let capRange = 1...30

    static let reminderOnKey = "reminderEnabled"
    static let reminderHourKey = "reminderHour"
    static let reminderMinuteKey = "reminderMinute"
    /// A picker position, never a scheduled notification — nothing is scheduled
    /// until the learner turns the toggle on.
    static let defaultReminderHour = 20
    static let defaultReminderMinute = 0

    private(set) var isReminderOn = false
    private(set) var reminderHour: Int
    private(set) var reminderMinute: Int
    /// Non-nil only when iOS will not deliver the reminder, or when scheduling
    /// failed. The two are worded differently on purpose: collapsing them would
    /// repeat D-4, where "product not found" and "store unreachable" became one
    /// string and left the setup work nothing to diagnose with.
    private(set) var permissionNote: String?

    private let defaults: UserDefaults
    private let notifications: NotificationScheduler
    private var storedCap: Int

    init(
        defaults: UserDefaults = .standard,
        notifications: NotificationScheduler = NoNotificationScheduler()
    ) {
        self.defaults = defaults
        self.notifications = notifications
        let stored = defaults.integer(forKey: Self.newWordsPerDayKey)
        // `integer(forKey:)` answers 0 for a key that was never written, which is
        // outside the range — so absent and "set to zero" are the same thing here,
        // and both mean "use the default".
        storedCap = stored == 0 ? SessionBuilder.defaultNewWordCap : Self.clamp(stored)
        isReminderOn = defaults.bool(forKey: Self.reminderOnKey)
        // `object(forKey:) as? Int` rather than `integer(forKey:)`: midnight is
        // hour 0, and `integer` cannot tell that from an absent key.
        reminderHour =
            defaults.object(forKey: Self.reminderHourKey) as? Int ?? Self.defaultReminderHour
        reminderMinute =
            defaults.object(forKey: Self.reminderMinuteKey) as? Int ?? Self.defaultReminderMinute
    }

    /// FR-13. Reconciles the learner's intent against what iOS will actually
    /// allow, so the toggle is on only when a notification will really fire.
    func setReminder(on isOn: Bool) async {
        permissionNote = nil
        guard isOn else {
            await notifications.cancelDailyReminder()
            isReminderOn = false
            defaults.set(false, forKey: Self.reminderOnKey)
            return
        }

        var status = await notifications.authorizationStatus()
        if status == .notDetermined {
            do {
                status = try await notifications.requestAuthorization()
            } catch {
                isReminderOn = false
                permissionNote = String(localized: "Couldn't turn on reminders. Try again.")
                return
            }
        }
        // iOS prompts once per install; asking again after a denial silently
        // returns denied, so a UI that keeps asking is a UI that looks broken.
        guard status == .authorized else {
            isReminderOn = false
            defaults.set(false, forKey: Self.reminderOnKey)
            permissionNote = String(
                localized: "Notifications are turned off for Full Deck in Settings.")
            return
        }

        await schedule()
    }

    /// FR-13. Changing the time while the reminder is on replaces it rather
    /// than adding a second — the identifier does that in the adapter, and the
    /// explicit cancel makes the intent testable.
    func setReminderTime(hour: Int, minute: Int) async {
        reminderHour = hour
        reminderMinute = minute
        defaults.set(hour, forKey: Self.reminderHourKey)
        defaults.set(minute, forKey: Self.reminderMinuteKey)
        guard isReminderOn else { return }
        await notifications.cancelDailyReminder()
        await schedule()
    }

    /// Called when the screen appears. Permission can be revoked in iOS
    /// Settings between visits, and a toggle still showing "on" would be a
    /// promise the app cannot keep.
    func refreshAuthorization() async {
        guard isReminderOn else { return }
        guard await notifications.authorizationStatus() != .authorized else { return }
        await notifications.cancelDailyReminder()
        isReminderOn = false
        defaults.set(false, forKey: Self.reminderOnKey)
        permissionNote = String(
            localized: "Notifications are turned off for Full Deck in Settings.")
    }

    private func schedule() async {
        do {
            try await notifications.scheduleDailyReminder(
                hour: reminderHour, minute: reminderMinute)
            isReminderOn = true
            defaults.set(true, forKey: Self.reminderOnKey)
        } catch {
            isReminderOn = false
            defaults.set(false, forKey: Self.reminderOnKey)
            permissionNote = String(localized: "Couldn't set the reminder. Try again.")
        }
    }

    /// FR-4. Clamped on write, so a hand-edited or stale defaults value cannot
    /// put the session builder outside its range.
    var newWordsPerDay: Int {
        get { storedCap }
        set {
            storedCap = Self.clamp(newValue)
            defaults.set(storedCap, forKey: Self.newWordsPerDayKey)
        }
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, capRange.lowerBound), capRange.upperBound)
    }
}
