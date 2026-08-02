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
    notifications: FakeNotificationScheduler = FakeNotificationScheduler(),
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
    #expect(viewModel.permissionNote != nil)
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
    #expect(viewModel.permissionNote != nil)
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
    #expect(viewModel.permissionNote != nil)
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
    #expect(viewModel.permissionNote != nil)
}
