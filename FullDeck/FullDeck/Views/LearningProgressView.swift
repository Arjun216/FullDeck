import SwiftUI

/// Words learned out of the language's total, and nothing else (FR-10).
struct LearningProgressView: View {
    let viewModel: ProgressViewModel

    // Dynamic Type: 64pt at the default text size, scaling on the .largeTitle
    // curve — a bare .system(size:) would ignore the user's setting entirely.
    @ScaledMetric(relativeTo: .largeTitle) private var countSize: CGFloat = 64

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
                .navigationTitle("Progress")
                .task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .ready(let learned, let total):
            VStack(spacing: Spacing.sm) {
                Text("\(learned)")
                    .font(.system(size: countSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                Text("of \(total) words learned")
                    .font(.title3)
                    .foregroundStyle(Color.textSecondary)
                if viewModel.state.isComplete {
                    Text("Every word. That's the whole deck.")
                        .font(.callout)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(learned) of \(total) words learned")
        case .failed(let message):
            ErrorStateView(message: message)
        }
    }
}
