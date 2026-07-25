import SwiftUI

/// The daily study/review session: one card at a time, active recall, then a
/// self-grade fed back to the scheduler. Placeholder for Phase 4 — the card
/// flow and speech land in Phase 8 against the tested domain engine.
struct StudyView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Study",
                systemImage: "rectangle.stack",
                description: Text("Your daily review session. Wired up in Phase 8.")
            )
            .navigationTitle("Study")
        }
    }
}

#Preview {
    StudyView()
}
