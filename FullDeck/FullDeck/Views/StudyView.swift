import Domain
import Foundation
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
                // The screen base (spec Decision 2). maxWidth/maxHeight makes the
                // background fill the tab even when `content` is a small
                // ProgressView or ContentUnavailableView.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
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
        VStack(spacing: Spacing.lg) {
            Text("\(card.index) of \(card.total)")
                .font(.footnote)
                // NFR-6: `.secondary` at `.footnote` size falls under WCAG
                // AA's 4.5:1 normal-text threshold (caught by the
                // accessibility audit). `Color.textPrimary` (#1C1917 on
                // #FFFBEB) is 16.87:1.
                .foregroundStyle(Color.textPrimary)
                // NFR-5: guarantees this Text its full ideal height at large
                // Dynamic Type sizes instead of being compressed/clipped by
                // the surrounding VStack (caught by the accessibility audit).
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Card \(card.index) of \(card.total)")

            VStack(spacing: Spacing.sm) {
                Text(card.entry.display)
                    .font(.largeTitle)
                    .foregroundStyle(Color.textPrimary)
                Text(card.entry.pos.rawValue.lowercased())
                    .font(.caption)
                    // NFR-6: same contrast issue as the index text above.
                    .foregroundStyle(Color.textPrimary)
            }

            Button {
                viewModel.speakWord()
            } label: {
                Label("Hear the word", systemImage: "speaker.wave.2")
            }
            // NFR-6: default Button styling tints this with the accent, which
            // fails WCAG AA contrast at this text size (caught by the
            // accessibility audit) — same issue and fix as the language row.
            // #D97706 is 3.07:1 on the background: a fill/large-text colour,
            // not a body-text one.
            .buttonStyle(.plain)
            .foregroundStyle(Color.textPrimary)
            .accessibilityLabel("Hear the word \(card.entry.display)")

            if card.isRevealed {
                revealedContent(card)
            } else {
                Button("Reveal") { viewModel.reveal() }
                    .buttonStyle(.borderedProminent)
                    // NFR-6: `.borderedProminent` puts a white label on the
                    // accent fill. White on AccentColor (#D97706) is 3.19:1,
                    // under WCAG AA's 4.5:1 for normal text; on AccentFill
                    // (#B45309) it is 5.02:1.
                    .tint(Color.accentFill)
                    .accessibilityHint("Shows the answer")
            }

            if viewModel.audioUnavailable {
                Text("Audio unavailable on this device.")
                    .font(.footnote)
                    // NFR-6: same contrast issue as the index text above.
                    .foregroundStyle(Color.textPrimary)
            }
        }
        // Two paddings, two jobs: the inner one is the card's own gutter, the
        // outer one the margin between the card and the screen edge.
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Spacing.md, style: .continuous)
                .fill(Color.appSurface)
                .stroke(Color.appSeparator, lineWidth: 1)
        )
        .padding(Spacing.md)
    }

    @ViewBuilder
    private func revealedContent(_ card: StudyViewModel.Card) -> some View {
        VStack(spacing: Spacing.md) {
            if let gloss = card.entry.gloss {
                Text(gloss)
                    .font(.title3)
                    .foregroundStyle(Color.textPrimary)
            }
            Text(card.entry.example)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textPrimary)
            Button {
                viewModel.speakSentence()
            } label: {
                Label("Hear the sentence", systemImage: "speaker.wave.2")
            }
            // NFR-6: same contrast fix as "Hear the word" above.
            .buttonStyle(.plain)
            .foregroundStyle(Color.textPrimary)
            .accessibilityLabel("Hear the example sentence")
        }

        gradeButtons
    }

    private var gradeButtons: some View {
        HStack(spacing: Spacing.md) {
            ForEach(Grade.allCases, id: \.self) { grade in
                Button(label(for: grade)) {
                    Task { await viewModel.grade(grade) }
                }
                .buttonStyle(.bordered)
                // NFR-6: `.bordered` tints its label with the accent over a
                // light grey fill, under WCAG AA's 4.5:1 for normal text.
                // Same issue and fix as "Hear the word" above. The
                // audit only started catching it here once the redundant
                // `.accessibilityLabel` came off: that override made the
                // Button one opaque element and hid its label text from the
                // contrast check.
                .foregroundStyle(Color.textPrimary)
            }
        }
    }

    /// No `.accessibilityLabel` override: with four terse grades the "Grade this
    /// word …" prefix disambiguated, but "Grade this word Let's try this again"
    /// reads worse than the button's own text. A `Button` with a text label
    /// already exposes that text to VoiceOver.
    private func label(for grade: Grade) -> String {
        switch grade {
        case .forgot: String(localized: "Let's try this again")
        case .recalled: String(localized: "Knew it!")
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
        VStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.seal")
                .font(.largeTitle)
                .foregroundStyle(Color.textSecondary)
            Text("You've learned all the words in this language.")
                .font(.title2)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textPrimary)
            if let nextDue {
                Text("Next review \(nextDue.formatted(date: .abbreviated, time: .omitted)).")
                    .font(.body)
                    // NFR-6: `.secondary` at normal (non-"large") text size
                    // falls under WCAG AA's 4.5:1 threshold.
                    .foregroundStyle(Color.textPrimary)
            }
            Button("Add another language — $0.99", action: onAddLanguage)
                .buttonStyle(.borderedProminent)
                // NFR-6: same white-on-accent issue as the Reveal button.
                .tint(Color.accentFill)
                .accessibilityHint("Opens the languages list")
        }
        .padding()
        .accessibilityElement(children: .contain)
    }
}
