import Domain
import Foundation
import Testing

@testable import FullDeck

/// A throwaway suite per call, so no test reads or writes the simulator's real
/// defaults or leaks a preference into a sibling test.
private func emptyDefaults() -> UserDefaults {
    UserDefaults(suiteName: "com.fulldeck.tests.settings.\(UUID().uuidString)")!
}

@MainActor
private func makeSettingsViewModel(
    notifications: NotificationScheduler = FakeNotificationScheduler(),
    defaults: UserDefaults = emptyDefaults()
) -> SettingsViewModel {
    SettingsViewModel(defaults: defaults, notifications: notifications)
}

@Test("FR-13 reminders are off by default")
@MainActor
func reminderIsOffByDefault() {
    #expect(!makeSettingsViewModel().isReminderOn)
}

@Test("FR-4 the new-word cap defaults to 10 and persists")
@MainActor
func capDefaultsAndPersists() {
    let defaults = emptyDefaults()
    let viewModel = SettingsViewModel(defaults: defaults)
    #expect(viewModel.newWordsPerDay == 10)

    viewModel.newWordsPerDay = 25

    // A fresh ViewModel over the same defaults is what a relaunch looks like.
    #expect(SettingsViewModel(defaults: defaults).newWordsPerDay == 25)
}

@Test("FR-4 the new-word cap clamps to its range")
@MainActor
func capClampsToItsRange() {
    let viewModel = SettingsViewModel(defaults: emptyDefaults())

    viewModel.newWordsPerDay = 999
    #expect(viewModel.newWordsPerDay == SettingsViewModel.capRange.upperBound)

    viewModel.newWordsPerDay = -5
    #expect(viewModel.newWordsPerDay == SettingsViewModel.capRange.lowerBound)
}

@Test("FR-13 enabling requests permission and schedules exactly one reminder")
@MainActor
func enablingSchedulesOneReminder() async {
    let notifications = FakeNotificationScheduler()
    notifications.promptResult = .authorized
    let viewModel = makeSettingsViewModel(notifications: notifications)

    await viewModel.setReminder(on: true)

    #expect(viewModel.isReminderOn)
    #expect(viewModel.permissionNote == nil)
    #expect(notifications.promptCount == 1)
    #expect(notifications.scheduled.count == 1)
    #expect(notifications.scheduled.first?.hour == SettingsViewModel.defaultReminderHour)
}

@Test("FR-13 a denied prompt reverts the toggle and explains")
@MainActor
func deniedPromptRevertsTheToggle() async {
    let notifications = FakeNotificationScheduler()
    notifications.promptResult = .denied
    let viewModel = makeSettingsViewModel(notifications: notifications)

    await viewModel.setReminder(on: true)

    #expect(!viewModel.isReminderOn)
    #expect(viewModel.noteCause == .permissionDenied)
    #expect(notifications.scheduled.isEmpty)
}

@Test("FR-13 enabling when already denied does not prompt again")
@MainActor
func alreadyDeniedDoesNotPromptAgain() async {
    let notifications = FakeNotificationScheduler()
    notifications.statusToReturn = .denied
    let viewModel = makeSettingsViewModel(notifications: notifications)

    await viewModel.setReminder(on: true)

    #expect(notifications.promptCount == 0)
    #expect(!viewModel.isReminderOn)
    #expect(viewModel.noteCause == .permissionDenied)
}

@Test("FR-13 disabling cancels the scheduled reminder")
@MainActor
func disablingCancels() async {
    let notifications = FakeNotificationScheduler()
    let viewModel = makeSettingsViewModel(notifications: notifications)
    await viewModel.setReminder(on: true)

    await viewModel.setReminder(on: false)

    #expect(!viewModel.isReminderOn)
    #expect(notifications.cancelCount == 1)
}

@Test("FR-13 changing the time reschedules rather than adding a second")
@MainActor
func changingTimeReschedules() async {
    let notifications = FakeNotificationScheduler()
    let viewModel = makeSettingsViewModel(notifications: notifications)
    await viewModel.setReminder(on: true)

    await viewModel.setReminderTime(hour: 7, minute: 30)

    #expect(notifications.cancelCount == 1)
    #expect(notifications.scheduled.count == 2)
    #expect(notifications.scheduled.last?.hour == 7)
    #expect(notifications.scheduled.last?.minute == 30)
}

/// Suspends inside `cancelDailyReminder()` until the test releases it, so a
/// second write is guaranteed to arrive while the first is still in flight —
/// the `GatedPackStore` trick from the language-selection suite, applied to the
/// one hazard a `DatePicker` creates by writing continuously as the wheel turns.
/// `@unchecked Sendable` for the same reason `FakeNotificationScheduler` is: the
/// protocol is nonisolated, and every call here comes from the one ViewModel.
private final class GatedNotificationScheduler: NotificationScheduler, @unchecked Sendable {
    enum Operation: Equatable {
        case cancel
        case schedule(hour: Int)
    }

    private(set) var log: [Operation] = []
    private var gateArmed = false
    private var gateHit = false
    private var gate: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?

    func armGate() { gateArmed = true }

    /// Returns once the gated call has actually suspended. No sleeps, and it
    /// works whichever of the two gets there first.
    func waitUntilGated() async {
        if gateHit { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        gate?.resume()
        gate = nil
    }

    func authorizationStatus() async -> ReminderAuthorization { .authorized }
    func requestAuthorization() async throws -> ReminderAuthorization { .authorized }

    func scheduleDailyReminder(hour: Int, minute: Int) async throws {
        log.append(.schedule(hour: hour))
    }

    func cancelDailyReminder() async {
        log.append(.cancel)
        guard gateArmed else { return }
        gateArmed = false
        await withCheckedContinuation { continuation in
            gate = continuation
            gateHit = true
            arrival?.resume()
            arrival = nil
        }
    }
}

@Test("FR-13 overlapping reminder writes are applied in order, never interleaved")
@MainActor
func overlappingRemindersAreSerialized() async {
    let notifications = GatedNotificationScheduler()
    let viewModel = makeSettingsViewModel(notifications: notifications)
    await viewModel.setReminder(on: true)

    notifications.armGate()
    let first = Task { await viewModel.setReminderTime(hour: 7, minute: 0) }
    await notifications.waitUntilGated()
    let second = Task { await viewModel.setReminderTime(hour: 8, minute: 0) }
    // Every chance to reach the scheduler while the first write is stuck:
    // unordered, that is exactly what a spun wheel does, and the reminder ends
    // up at 7 — the time the learner just scrolled past.
    for _ in 0..<5 { await Task.yield() }
    notifications.release()
    _ = await first.result
    _ = await second.result

    #expect(
        notifications.log == [
            .schedule(hour: SettingsViewModel.defaultReminderHour),
            .cancel, .schedule(hour: 7), .cancel, .schedule(hour: 8),
        ])
}

@Test("FR-13 permission revoked outside the app turns the toggle off on next appearance")
@MainActor
func revokedPermissionReconcilesOnAppearance() async {
    let notifications = FakeNotificationScheduler()
    let viewModel = makeSettingsViewModel(notifications: notifications)
    await viewModel.setReminder(on: true)
    #expect(viewModel.isReminderOn)

    // The learner turns notifications off in iOS Settings and comes back.
    notifications.statusToReturn = .denied
    await viewModel.refreshAuthorization()

    #expect(!viewModel.isReminderOn)
    #expect(viewModel.noteCause == .permissionDenied)
    #expect(notifications.cancelCount == 1)
}

@Test("NFR-10 a scheduling failure surfaces as a message, not a crash")
@MainActor
func schedulingFailureIsReported() async {
    let notifications = FakeNotificationScheduler()
    notifications.scheduleError = FakeStoreError()
    let viewModel = makeSettingsViewModel(notifications: notifications)

    await viewModel.setReminder(on: true)

    #expect(!viewModel.isReminderOn)
    // Not `!= nil`: the whole point of the cause is that a retryable failure and
    // a permanent denial stay apart, and only a typed assertion can catch them
    // collapsing back into one.
    #expect(viewModel.noteCause == .temporaryFailure)
    #expect(viewModel.permissionNote != nil)
}

@Test("NFR-10 a failed permission request surfaces as retryable, not as a denial")
@MainActor
func failedRequestIsRetryable() async {
    let notifications = FakeNotificationScheduler()
    notifications.requestError = FakeStoreError()
    let viewModel = makeSettingsViewModel(notifications: notifications)

    await viewModel.setReminder(on: true)

    #expect(!viewModel.isReminderOn)
    #expect(viewModel.noteCause == .temporaryFailure)
}
