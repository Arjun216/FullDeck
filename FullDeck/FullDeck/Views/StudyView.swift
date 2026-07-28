import Domain
import SwiftUI

/// The daily study session (FR-3, FR-5, FR-6, FR-7, FR-12). Thin: every decision
/// lives in `StudyViewModel`.
struct StudyView: View {
    // `@Bindable` isn't needed — nothing here writes back into the ViewModel;
    // `let` plus @Observable is enough for SwiftUI to track what it reads.
    let viewModel: StudyViewModel
    /// FR-11's completion screen offers another language; only `ContentView` knows
    /// how to select a tab, so it hands the action down rather than the view
    /// reaching for shared state.
    let onAddLanguage: () -> Void

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
        case .complete(let nextDue):
            completionView(nextDue)
        case .failed(let message):
            ErrorStateView(message: message)
        }
    }

    private func cardView(_ card: StudyViewModel.Card) -> some View {
        // NFR-5: at the largest accessibility Dynamic Type sizes this card's
        // content (word, buttons, grade row) can exceed the screen height —
        // a ScrollView lets it grow instead of clip, caught by the
        // accessibility audit's "may be clipped" finding.
        ScrollView {
            cardContent(card)
        }
    }

    private func cardContent(_ card: StudyViewModel.Card) -> some View {
        VStack(spacing: 24) {
            Text("\(card.index) of \(card.total)")
                .font(.footnote)
                // NFR-6: `.secondary` at `.footnote` size falls under WCAG
                // AA's 4.5:1 normal-text threshold (caught by the
                // accessibility audit); `.primary` keeps it readable.
                .foregroundStyle(.primary)
                // NFR-5: guarantees this Text its full ideal height at large
                // Dynamic Type sizes instead of being compressed/clipped by
                // the surrounding VStack (caught by the accessibility audit).
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Card \(card.index) of \(card.total)")

            VStack(spacing: 8) {
                Text(card.entry.display)
                    .font(.largeTitle)
                Text(card.entry.pos.rawValue.lowercased())
                    .font(.caption)
                    // NFR-6: same contrast issue as the index text above.
                    .foregroundStyle(.primary)
            }

            Button {
                viewModel.speakWord()
            } label: {
                Label("Hear the word", systemImage: "speaker.wave.2")
            }
            // NFR-6: default Button styling tints this system blue, which
            // fails WCAG AA contrast at this text size (caught by the
            // accessibility audit) — same issue and fix as the language row.
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityLabel("Hear the word \(card.entry.display)")

            if card.isRevealed {
                revealedContent(card)
            } else {
                Button("Reveal") { viewModel.reveal() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Shows the answer")
            }

            if viewModel.audioUnavailable {
                Text("Audio unavailable on this device.")
                    .font(.footnote)
                    // NFR-6: same contrast issue as the index text above.
                    .foregroundStyle(.primary)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func revealedContent(_ card: StudyViewModel.Card) -> some View {
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
            // NFR-6: same contrast fix as "Hear the word" above.
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityLabel("Hear the example sentence")
        }

        gradeButtons
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

    /// FR-11: the deliberate ending. The price is stated rather than hidden —
    /// concealing it would be the dark pattern. No summary statistics, no streak.
    private func completionView(_ nextDue: Date?) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("You've learned all the words in this language.")
                .font(.title2)
                .multilineTextAlignment(.center)
            if let nextDue {
                Text("Next review \(nextDue.formatted(date: .abbreviated, time: .omitted)).")
                    .font(.body)
                    // NFR-6: `.secondary` at normal (non-"large") text size
                    // falls under WCAG AA's 4.5:1 threshold.
                    .foregroundStyle(.primary)
            }
            Button("Add another language — $0.99", action: onAddLanguage)
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Opens the languages list")
        }
        .padding()
        .accessibilityElement(children: .contain)
    }
}
