import Domain
import Foundation
import Testing

@testable import FullDeck

private let hindiDescriptor = PackDescriptor(
    languageCode: LanguageCode("hi"), displayName: "Hindi", filename: "hi.pack.json",
    unlockedByDefault: false)

/// A throwaway suite so a test never reads or writes the simulator's real
/// defaults, and never leaks its persisted active language into a sibling test.
/// A fresh, uniquely-named suite per call rather than one shared name — tests in
/// this file run in the same process, and `select()` now persists to whatever
/// `UserDefaults` it's given.
private func emptyDefaults() -> UserDefaults {
    let suite = "com.fulldeck.tests.languageSelection.\(UUID().uuidString)"
    return UserDefaults(suiteName: suite)!
}

@MainActor
private func makeSelectionViewModel(
    descriptors: [PackDescriptor] = [frDescriptor(), hindiDescriptor],
    unlocked: Set<String> = [],
    defaults: UserDefaults = emptyDefaults(),
    errorOverride: PackLoadError? = nil
) -> LanguageSelectionViewModel {
    LanguageSelectionViewModel(
        packStore: InMemoryPackStore(descriptors: descriptors, errorOverride: errorOverride),
        entitlements: StubEntitlementStore(unlocked: unlocked), defaults: defaults)
}

@Test("FR-1 the selection screen lists every available pack")
@MainActor
func listsEveryAvailablePack() async {
    let viewModel = makeSelectionViewModel()

    await viewModel.load()

    guard case .ready(let options) = viewModel.state else {
        Issue.record("expected options, got \(viewModel.state)")
        return
    }
    #expect(options.map(\.descriptor.displayName) == ["French", "Hindi"])
}

@Test("FR-2 the launch language is unlocked without a purchase")
@MainActor
func launchLanguageIsUnlocked() async {
    let viewModel = makeSelectionViewModel()

    await viewModel.load()

    guard case .ready(let options) = viewModel.state else {
        Issue.record("expected options, got \(viewModel.state)")
        return
    }
    #expect(options[0].isUnlocked)
    #expect(!options[1].isUnlocked)
}

@Test("FR-14 a purchased language shows as unlocked")
@MainActor
func purchasedLanguageIsUnlocked() async {
    let viewModel = makeSelectionViewModel(unlocked: ["hi"])

    await viewModel.load()

    guard case .ready(let options) = viewModel.state else {
        Issue.record("expected options, got \(viewModel.state)")
        return
    }
    #expect(options[1].isUnlocked)
}

@Test("FR-1 selecting an unlocked pack makes it the active language")
@MainActor
func selectingUnlockedPackActivatesIt() async {
    let viewModel = makeSelectionViewModel()
    await viewModel.load()
    guard case .ready(let options) = viewModel.state else {
        Issue.record("expected options, got \(viewModel.state)")
        return
    }

    viewModel.select(options[0])

    #expect(viewModel.activeLanguage == LanguageCode("fr"))
}

@Test("FR-1 selecting a locked pack does not make it active")
@MainActor
func selectingLockedPackDoesNothing() async {
    let viewModel = makeSelectionViewModel()
    await viewModel.load()
    guard case .ready(let options) = viewModel.state else {
        Issue.record("expected options, got \(viewModel.state)")
        return
    }

    viewModel.select(options[1])

    #expect(viewModel.activeLanguage == nil)
}

@Test("FR-9 the active language is restored on the next launch")
@MainActor
func activeLanguageIsRestoredOnNextLaunch() async {
    let defaults = emptyDefaults()
    let packStore = InMemoryPackStore(descriptors: [frDescriptor()])

    let first = LanguageSelectionViewModel(
        packStore: packStore, entitlements: StubEntitlementStore(), defaults: defaults)
    await first.load()
    guard case .ready(let options) = first.state, let option = options.first else {
        Issue.record("expected a ready state with one option")
        return
    }
    first.select(option)

    let second = LanguageSelectionViewModel(
        packStore: packStore, entitlements: StubEntitlementStore(), defaults: defaults)
    await second.load()

    #expect(second.activeLanguage == LanguageCode("fr"))
}

@Test("FR-9 a persisted language that is no longer available is not restored")
@MainActor
func unavailablePersistedLanguageIsNotRestored() async {
    let defaults = emptyDefaults()
    defaults.set("hi", forKey: "activeLanguageCode")
    let viewModel = LanguageSelectionViewModel(
        packStore: InMemoryPackStore(descriptors: [frDescriptor()]),
        entitlements: StubEntitlementStore(), defaults: defaults)

    await viewModel.load()

    #expect(viewModel.activeLanguage == nil)
}

@Test("NFR-10 a schema-version mismatch surfaces the update message")
@MainActor
func selectionSchemaVersionMismatchSurfacesUpdateMessage() async {
    let viewModel = makeSelectionViewModel(
        errorOverride: .unsupportedSchemaVersion(found: 99, maxSupported: 1))

    await viewModel.load()

    #expect(viewModel.state == .failed("This language needs an app update."))
}
