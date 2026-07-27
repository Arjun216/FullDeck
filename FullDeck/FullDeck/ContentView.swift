import Domain
import SwiftUI

/// Root shell: one tab per v1 screen. Owns which language is active — persisting
/// that choice across launches is Phase 9.
struct ContentView: View {
    let dependencies: AppDependencies

    @State private var selectionViewModel: LanguageSelectionViewModel

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        // `@State` on a ViewModel needs an initial value here because the
        // ViewModel depends on injected services — SwiftUI can't default it.
        _selectionViewModel = State(
            initialValue: LanguageSelectionViewModel(
                packStore: dependencies.packStore,
                entitlements: dependencies.entitlements))
    }

    var body: some View {
        TabView {
            LanguageSelectionView(viewModel: selectionViewModel)
                .tabItem { Label("Languages", systemImage: "globe") }
            studyTab
                .tabItem { Label("Study", systemImage: "rectangle.stack") }
            progressTab
                .tabItem { Label("Progress", systemImage: "chart.bar") }
        }
    }

    @ViewBuilder
    private var studyTab: some View {
        if let language = selectionViewModel.activeLanguage {
            StudyView(
                viewModel: StudyViewModel(
                    languageCode: language, packStore: dependencies.packStore,
                    reviewStore: dependencies.reviewStore,
                    scheduler: dependencies.scheduler,
                    sessionBuilder: dependencies.sessionBuilder,
                    speech: dependencies.speech, clock: dependencies.clock)
            )
            .id(language.rawValue)
        } else {
            chooseALanguage
        }
    }

    @ViewBuilder
    private var progressTab: some View {
        if let language = selectionViewModel.activeLanguage {
            LearningProgressView(
                viewModel: ProgressViewModel(
                    languageCode: language, packStore: dependencies.packStore,
                    reviewStore: dependencies.reviewStore)
            )
            .id(language.rawValue)
        } else {
            chooseALanguage
        }
    }

    private var chooseALanguage: some View {
        ContentUnavailableView(
            "Choose a language", systemImage: "globe",
            description: Text("Pick a language on the Languages tab to start."))
    }
}

#Preview {
    ContentView(dependencies: .live())
}
