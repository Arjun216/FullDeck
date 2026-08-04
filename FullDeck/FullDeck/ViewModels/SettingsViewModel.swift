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
    /// Why that note is showing. The string alone left the view unable to tell
    /// the two off-states apart, so it offered "Open Settings" for a transient
    /// scheduling failure as well — D-4's mistake in a second place. The typed
    /// cause is what the view branches on; the string is only ever displayed.
    enum NoteCause: Equatable {
        /// iOS will not deliver. Only a trip to Settings changes this.
        case permissionDenied
        /// Asking or scheduling failed. Retrying is the fix; Settings is not.
        case temporaryFailure
    }
    private(set) var noteCause: NoteCause?

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

    /// The view spawns one `Task` per binding write, and a `.hourAndMinute`
    /// `DatePicker` writes continuously as the wheel turns. Nothing orders those
    /// Tasks, so two overlapping writes could interleave their cancel/schedule
    /// pairs across the awaits below — scheduling the time the learner scrolled
    /// *past*, or leaving the toggle on with nothing scheduled, which is the one
    /// invariant this type exists to hold. Every entry point queues here instead.
    private var inFlight: Task<Void, Never>?

    private func serialized(_ work: @escaping @MainActor () async -> Void) async {
        let previous = inFlight
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        inFlight = task
        await task.value
    }

    /// FR-13. Reconciles the learner's intent against what iOS will actually
    /// allow, so the toggle is on only when a notification will really fire.
    func setReminder(on isOn: Bool) async {
        await serialized { await self.applyReminder(on: isOn) }
    }

    private func applyReminder(on isOn: Bool) async {
        permissionNote = nil
        noteCause = nil
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
                note(.temporaryFailure, String(localized: "Couldn't turn on reminders. Try again."))
                return
            }
        }
        // iOS prompts once per install; asking again after a denial silently
        // returns denied, so a UI that keeps asking is a UI that looks broken.
        guard status == .authorized else {
            isReminderOn = false
            defaults.set(false, forKey: Self.reminderOnKey)
            note(
                .permissionDenied,
                String(localized: "Notifications are turned off for Full Deck in Settings."))
            return
        }

        await schedule()
    }

    /// FR-13. Changing the time while the reminder is on replaces it rather
    /// than adding a second — the identifier does that in the adapter, and the
    /// explicit cancel makes the intent testable.
    func setReminderTime(hour: Int, minute: Int) async {
        await serialized { await self.applyReminderTime(hour: hour, minute: minute) }
    }

    private func applyReminderTime(hour: Int, minute: Int) async {
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
        await serialized { await self.reconcileAuthorization() }
    }

    private func reconcileAuthorization() async {
        guard isReminderOn else { return }
        guard await notifications.authorizationStatus() != .authorized else { return }
        await notifications.cancelDailyReminder()
        isReminderOn = false
        defaults.set(false, forKey: Self.reminderOnKey)
        note(
            .permissionDenied,
            String(localized: "Notifications are turned off for Full Deck in Settings."))
    }

    /// `DatePicker` binds to a `Date`, while this type stores hour/minute so no
    /// test ever needs the wall clock (`scripts/determinism-check.sh`). The day
    /// is arbitrary and never read — only the time components are.
    var reminderDate: Date {
        Calendar.current.date(
            from: DateComponents(
                year: 2000, month: 1, day: 1, hour: reminderHour, minute: reminderMinute))
            ?? Date(timeIntervalSince1970: 0)
    }

    func setReminderTime(from date: Date) async {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        await setReminderTime(
            hour: components.hour ?? reminderHour, minute: components.minute ?? reminderMinute)
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
            note(.temporaryFailure, String(localized: "Couldn't set the reminder. Try again."))
        }
    }

    private func note(_ cause: NoteCause, _ message: String) {
        noteCause = cause
        permissionNote = message
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
