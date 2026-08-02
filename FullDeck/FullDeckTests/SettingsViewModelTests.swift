import Domain
import Foundation
import Testing

@testable import FullDeck

/// A throwaway suite per call, so no test reads or writes the simulator's real
/// defaults or leaks a preference into a sibling test.
private func emptyDefaults() -> UserDefaults {
    UserDefaults(suiteName: "com.fulldeck.tests.settings.\(UUID().uuidString)")!
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
