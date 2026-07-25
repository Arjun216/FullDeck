import SwiftUI

/// Shows words learned out of 1000 for the current language — and nothing else.
/// Placeholder for Phase 4. (Named LearningProgressView, not ProgressView, to
/// avoid colliding with SwiftUI's built-in ProgressView.) Real counts arrive in
/// Phase 8/9 from the domain StatsService.
struct LearningProgressView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Progress",
                systemImage: "chart.bar",
                description: Text("Words learned out of 1000. Wired up in Phase 8/9.")
            )
            .navigationTitle("Progress")
        }
    }
}

#Preview {
    LearningProgressView()
}
