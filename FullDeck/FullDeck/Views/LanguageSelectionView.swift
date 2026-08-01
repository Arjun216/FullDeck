import Domain
import Foundation
import SwiftUI

/// Lists the bundled packs with lock state (FR-1, FR-2, FR-14).
struct LanguageSelectionView: View {
    let viewModel: LanguageSelectionViewModel

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
                .navigationTitle("Languages")
                .task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .ready(let options):
            List {
                ForEach(options) { option in
                    languageRow(option)
                }
                comingSoonSection
            }
            // A List paints its own background over the one set on the
            // NavigationStack content; hiding it lets the warm base show.
            .scrollContentBackground(.hidden)
        case .failed(let message):
            ErrorStateView(message: message)
        }
    }

    /// Languages that are announced but not yet built.
    ///
    /// Deliberately *not* a `manifest.json` entry: `availablePacks()` returns packs
    /// that exist, and an entry with no pack file would push "a pack that isn't
    /// there" into `PackDescriptor`, the loader and the validator. This is
    /// presentation copy. Delete it when the Hindi pack lands (Phase 12).
    private static let comingSoon = ["हिन्दी"]

    @ViewBuilder
    private var comingSoonSection: some View {
        Section {
            ForEach(Self.comingSoon, id: \.self) { name in
                HStack {
                    Text(name)
                    Spacer()
                    Text("Coming soon")
                        .font(.footnote)
                }
                // One element, so VoiceOver reads "हिन्दी, coming soon" rather
                // than stopping on each half separately.
                .accessibilityElement(children: .combine)
                .foregroundStyle(Color.textSecondary)
                .listRowBackground(Color.appBackground)
            }
        }
    }

    private func languageRow(_ option: LanguageSelectionViewModel.Option) -> some View {
        Button {
            viewModel.select(option)
        } label: {
            HStack {
                // Default Button styling tints this with the accent, which
                // fails WCAG AA contrast at body text size (caught by the
                // audit) — the checkmark already carries the "selected"
                // signal, so this text doesn't need to borrow the accent
                // color too.
                Text(option.descriptor.displayName)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if !option.isUnlocked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Color.textSecondary)
                } else if isActive(option) {
                    // Left untinted on purpose: it picks up the warm
                    // AccentColor, which is the intent, and as a glyph
                    // it's a graphical object held to 3:1, not 4.5:1.
                    Image(systemName: "checkmark")
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!option.isUnlocked)
        .accessibilityLabel(accessibilityLabel(for: option))
        // Rows are opaque by default and would punch system-grey holes
        // in the warm background.
        .listRowBackground(Color.appBackground)
    }

    private func isActive(_ option: LanguageSelectionViewModel.Option) -> Bool {
        viewModel.activeLanguage == option.descriptor.languageCode
    }

    private func accessibilityLabel(
        for option: LanguageSelectionViewModel.Option
    ) -> String {
        guard option.isUnlocked else {
            return String(localized: "\(option.descriptor.displayName), locked")
        }
        return isActive(option)
            ? String(localized: "\(option.descriptor.displayName), active language")
            : option.descriptor.displayName
    }
}
