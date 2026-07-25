import SwiftUI

/// Lists the available language packs with their locked/unlocked state.
/// Placeholder for Phase 4 — the real pack list, loading, and lock check are
/// wired up in Phase 8 (presentation) and Phase 11 (StoreKit).
struct LanguageSelectionView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Languages",
                systemImage: "globe",
                description: Text("Choose a language to learn. Wired up in Phase 8.")
            )
            .navigationTitle("Languages")
        }
    }
}

#Preview {
    LanguageSelectionView()
}
