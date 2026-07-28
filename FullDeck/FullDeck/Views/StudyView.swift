import Domain
import SwiftUI

/// The daily study session (FR-3, FR-5, FR-6, FR-7, FR-12). Thin: every decision
/// lives in `StudyViewModel`.
struct StudyView: View {
    // `@Bindable` isn't needed — nothing here writes back into the ViewModel;
    // `let` plus @Observable is enough for SwiftUI to track what it reads.
    let viewModel: StudyViewModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Study")
                .task { await viewModel.start() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .card(let card):
            cardView(card)
        case .caughtUp(let nextDue):
            caughtUpView(nextDue)
        case .complete:
            // Placeholder so the switch compiles for Task 3's ViewModel tests;
            // Task 5 replaces this with the real completion screen.
            ProgressView()
        case .failed(let message):
            ErrorStateView(message: message)
        }
    }

    private func cardView(_ card: StudyViewModel.Card) -> some View {
        VStack(spacing: 24) {
            Text("\(card.index) of \(card.total)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Card \(card.index) of \(card.total)")

            VStack(spacing: 8) {
                Text(card.entry.display)
                    .font(.largeTitle)
                Text(card.entry.pos.rawValue.lowercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.speakWord()
            } label: {
                Label("Hear the word", systemImage: "speaker.wave.2")
            }
            .accessibilityLabel("Hear the word \(card.entry.display)")

            if card.isRevealed {
                VStack(spacing: 12) {
                    if let gloss = card.entry.gloss {
                        Text(gloss).font(.title3)
                    }
                    Text(card.entry.example)
                        .font(.body)
                        .multilineTextAlignment(.center)
                    Button {
                        viewModel.speakSentence()
                    } label: {
                        Label("Hear the sentence", systemImage: "speaker.wave.2")
                    }
                    .accessibilityLabel("Hear the example sentence")
                }

                gradeButtons
            } else {
                Button("Reveal") { viewModel.reveal() }
                    .buttonStyle(.borderedProminent)
            }

            if viewModel.audioUnavailable {
                Text("Audio unavailable on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var gradeButtons: some View {
        HStack(spacing: 12) {
            ForEach(Grade.allCases, id: \.self) { grade in
                Button(label(for: grade)) {
                    Task { await viewModel.grade(grade) }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Grade this word \(label(for: grade))")
            }
        }
    }

    private func label(for grade: Grade) -> String {
        switch grade {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }

    private func caughtUpView(_ nextDue: Date?) -> some View {
        ContentUnavailableView {
            Label("You're caught up", systemImage: "checkmark.circle")
        } description: {
            if let nextDue {
                Text("Next review \(nextDue.formatted(date: .abbreviated, time: .omitted)).")
            } else {
                Text("Nothing is due right now.")
            }
        }
    }
}
