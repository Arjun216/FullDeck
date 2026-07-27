import SwiftUI

/// Words learned out of the language's total, and nothing else (FR-10).
struct LearningProgressView: View {
    let viewModel: ProgressViewModel

    var body: some View {
        NavigationStack {
            content
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
            VStack(spacing: 8) {
                Text("\(learned)")
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                Text("of \(total) words learned")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(learned) of \(total) words learned")
        case .failed(let message):
            ContentUnavailableView(
                "Something went wrong", systemImage: "exclamationmark.triangle",
                description: Text(message))
        }
    }
}
