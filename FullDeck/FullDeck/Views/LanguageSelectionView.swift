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
            }
            // A List paints its own background over the one set on the
            // NavigationStack content; hiding it lets the warm base show.
            .scrollContentBackground(.hidden)
        case .failed(let message):
            ErrorStateView(message: message)
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
        // Deliberately NOT .disabled(). SwiftUI dims a disabled row, which took the
        // locked language's name to 3.33:1 against the warm background — under the
        // 4.5:1 AA floor, and caught by the audit. FR-1 is enforced where it belongs,
        // in `select()`, which refuses a locked pack; the lock icon and the "locked"
        // accessibility label carry the state. Phase 11 needs this row tappable
        // anyway, to open the purchase sheet.
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
