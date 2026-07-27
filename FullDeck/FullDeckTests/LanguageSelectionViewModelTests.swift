import Domain
import Testing

@testable import FullDeck

private let hindiDescriptor = PackDescriptor(
    languageCode: LanguageCode("hi"), displayName: "Hindi", filename: "hi.pack.json",
    unlockedByDefault: false)

@MainActor
private func makeSelectionViewModel(
    descriptors: [PackDescriptor] = [frDescriptor(), hindiDescriptor],
    unlocked: Set<String> = []
) -> LanguageSelectionViewModel {
    LanguageSelectionViewModel(
        packStore: InMemoryPackStore(descriptors: descriptors),
        entitlements: StubEntitlementStore(unlocked: unlocked))
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
