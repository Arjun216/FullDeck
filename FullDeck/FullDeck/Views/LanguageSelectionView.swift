import Domain
import Foundation
import SwiftUI

/// Lists the bundled packs with lock state (FR-1, FR-2, FR-14).
struct LanguageSelectionView: View {
    let viewModel: LanguageSelectionViewModel
    let purchases: PurchaseService

    /// `Option` is already `Identifiable`, so it doubles as the sheet's item.
    @State private var purchasing: LanguageSelectionViewModel.Option?

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
                .navigationTitle("Languages")
        }
        // Both presentations hang off the NavigationStack, not off `content`.
        // `content` is a @ViewBuilder switch, so every `load()` — which sets
        // `.loading` before `.ready` — swaps its branch and rebuilds that
        // subtree, taking any sheet attached to it down with it. The sheet
        // never appeared at all until it moved up here.
        .sheet(item: $purchasing) { option in
            PurchaseSheet(
                viewModel: PurchaseViewModel(
                    languageCode: option.descriptor.languageCode,
                    displayName: option.descriptor.displayName,
                    purchases: purchases),
                onUnlocked: { Task { await viewModel.load() } })
        }
        .alert(
            "Restore Purchases",
            isPresented: Binding(
                get: { viewModel.restoreMessage != nil },
                set: { if !$0 { viewModel.clearRestoreMessage() } })
        ) {
            Button("OK") { viewModel.clearRestoreMessage() }
        } message: {
            Text(viewModel.restoreMessage ?? "")
        }
        .task { await viewModel.load() }
        .task {
            // The launch entitlement refresh is async and can land after
            // `load()` has already run — without this, a language the learner
            // paid for keeps its padlock until they navigate away and back.
            // Also delivers a late Ask-to-Buy approval and a revocation.
            for await _ in purchases.entitlementChanges {
                await viewModel.load()
            }
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
                restoreRow
            }
            // A List paints its own background over the one set on the
            // NavigationStack content; hiding it lets the warm base show.
            .scrollContentBackground(.hidden)
        case .failed(let message):
            ErrorStateView(message: message)
        }
    }

    /// FR-15. A row rather than a toolbar item, which is where spec Decision 5
    /// put it: iOS 26 renders toolbar titles at a fixed size, and the audit
    /// fails them with "user will not be able to change the font size of this
    /// SwiftUI.AccessibilityNode" — reproduced with a bare `Button("...")` and
    /// again with an explicit `.font(.body)`. Decision 5's actual reason was
    /// that the Languages screen is the only place a learner would look for
    /// this; a row satisfies that, and the audit stays unfiltered.
    private var restoreRow: some View {
        Button {
            Task { await viewModel.restore() }
        } label: {
            Text("Restore Purchases")
                .foregroundStyle(Color.textPrimary)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.appBackground)
    }

    private func languageRow(_ option: LanguageSelectionViewModel.Option) -> some View {
        Button {
            // A presentation branch, so it lives here rather than in the view
            // model: `select()` already refuses a locked pack (FR-1), and this
            // decides what the tap *shows* instead.
            if option.isUnlocked {
                viewModel.select(option)
            } else {
                purchasing = option
            }
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
        // The label is an HStack whose only opaque parts are the name and the
        // trailing glyph; the gap between them has no content to hit-test
        // against, so taps there fall through. Harmless on the active row,
        // which reacts anyway — but a locked row shows a padlock and no
        // checkmark, leaving most of its width dead.
        .contentShape(Rectangle())
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
