import SwiftUI

/// Root shell: one tab per v1 screen. Placeholder navigation for Phase 4 — the
/// composition root that injects real ViewModels arrives in Phase 8/9.
struct ContentView: View {
    var body: some View {
        TabView {
            LanguageSelectionView()
                .tabItem { Label("Languages", systemImage: "globe") }
            StudyView()
                .tabItem { Label("Study", systemImage: "rectangle.stack") }
            LearningProgressView()
                .tabItem { Label("Progress", systemImage: "chart.bar") }
        }
    }
}

#Preview {
    ContentView()
}
