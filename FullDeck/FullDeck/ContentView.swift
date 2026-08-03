import Domain
import SwiftUI

/// Root shell: one tab per v1 screen. Which language is active is owned by
/// `LanguageSelectionViewModel` and persisted across launches there.
struct ContentView: View {
    /// Tabs need an explicit, stable tag. Each tab's content is an `if let` on
    /// `activeLanguage`, and a `_ConditionalContent` that flips branch changes the
    /// tab's *implicit* identity — which silently breaks TabView's tag-to-tab
    /// mapping and makes the last tab unreachable. The tag sits outside the
    /// conditional, so it survives the flip.
    private enum Tab: Hashable {
        case languages, study, progress
    }

    let dependencies: AppDependencies

    @State private var selectionViewModel: LanguageSelectionViewModel
    @State private var settingsViewModel: SettingsViewModel
    @State private var creditsViewModel: CreditsViewModel
    @State private var selectedTab: Tab = .languages
    // Owned here rather than rebuilt inside the tab bodies: a ViewModel
    // constructed per body evaluation is a new object on every re-render, which
    // discards whatever session the learner was in the middle of.
    @State private var studyViewModel: StudyViewModel?
    @State private var progressViewModel: ProgressViewModel?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        // `@State` on a ViewModel needs an initial value here because the
        // ViewModel depends on injected services — SwiftUI can't default it.
        _selectionViewModel = State(
            initialValue: LanguageSelectionViewModel(
                packStore: dependencies.packStore,
                entitlements: dependencies.entitlements,
                purchases: dependencies.purchases))
        // Not rebuilt per body evaluation, for the same reason as the others:
        // it owns preferences the learner is editing.
        _settingsViewModel = State(
            initialValue: SettingsViewModel(notifications: dependencies.notifications))
        _creditsViewModel = State(
            initialValue: CreditsViewModel(packStore: dependencies.packStore))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            LanguageSelectionView(
                viewModel: selectionViewModel, purchases: dependencies.purchases,
                settingsViewModel: settingsViewModel, creditsViewModel: creditsViewModel
            )
            .tabItem { Label("Languages", systemImage: "globe") }
            .tag(Tab.languages)
            studyTab
                .tabItem { Label("Study", systemImage: "rectangle.stack") }
                .tag(Tab.study)
            progressTab
                .tabItem { Label("Progress", systemImage: "chart.bar") }
                .tag(Tab.progress)
        }
        // Rebuild the two ViewModels only when the active language genuinely
        // changes — not on every re-render.
        .task(id: selectionViewModel.activeLanguage) {
            makeViewModels(for: selectionViewModel.activeLanguage)
        }
        // Assign rather than rebuild. The `.task(id:)` above rebuilds
        // StudyViewModel when the language changes, and doing that for a cap
        // edit would throw away whatever session the learner is in the middle
        // of (FR-4 takes effect from the next session, not mid-deck).
        .onChange(of: settingsViewModel.newWordsPerDay) { _, cap in
            studyViewModel?.newWordCap = cap
        }
    }

    private func makeViewModels(for language: LanguageCode?) {
        guard let language else {
            studyViewModel = nil
            progressViewModel = nil
            return
        }
        studyViewModel = StudyViewModel(
            languageCode: language, packStore: dependencies.packStore,
            reviewStore: dependencies.reviewStore,
            scheduler: dependencies.scheduler,
            sessionBuilder: dependencies.sessionBuilder,
            speech: dependencies.speech, clock: dependencies.clock,
            newWordCap: settingsViewModel.newWordsPerDay)
        progressViewModel = ProgressViewModel(
            languageCode: language, packStore: dependencies.packStore,
            reviewStore: dependencies.reviewStore, clock: dependencies.clock)
    }

    @ViewBuilder
    private var studyTab: some View {
        if let studyViewModel, let language = selectionViewModel.activeLanguage {
            StudyView(viewModel: studyViewModel, onAddLanguage: { selectedTab = .languages })
                .id(language.rawValue)
        } else {
            chooseALanguage
        }
    }

    @ViewBuilder
    private var progressTab: some View {
        if let progressViewModel, let language = selectionViewModel.activeLanguage {
            LearningProgressView(viewModel: progressViewModel)
                .id(language.rawValue)
        } else {
            chooseALanguage
        }
    }

    private var chooseALanguage: some View {
        ContentUnavailableView(
            "Choose a language", systemImage: "globe",
            description: Text("Pick a language on the Languages tab to start.")
        )
        // Not inside a NavigationStack, so it does not inherit a screen
        // background from either of the other two tabs.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
}

#Preview {
    // The preview shares the app's real wiring; if the store can't open there is
    // nothing to preview, so a failure here is a preview-only crash, not shipped.
    // swiftlint:disable:next force_try
    ContentView(dependencies: try! AppDependencies.live())
}
