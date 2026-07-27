import Domain
import SwiftUI

/// Lists the bundled packs with lock state (FR-1, FR-2, FR-14).
struct LanguageSelectionView: View {
    let viewModel: LanguageSelectionViewModel

    var body: some View {
        NavigationStack {
            content
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
            List(options) { option in
                Button {
                    viewModel.select(option)
                } label: {
                    HStack {
                        Text(option.descriptor.displayName)
                        Spacer()
                        if !option.isUnlocked {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                        } else if isActive(option) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(!option.isUnlocked)
                .accessibilityLabel(accessibilityLabel(for: option))
            }
        case .failed(let message):
            ErrorStateView(message: message)
        }
    }

    private func isActive(_ option: LanguageSelectionViewModel.Option) -> Bool {
        viewModel.activeLanguage == option.descriptor.languageCode
    }

    private func accessibilityLabel(
        for option: LanguageSelectionViewModel.Option
    ) -> String {
        guard option.isUnlocked else {
            return "\(option.descriptor.displayName), locked"
        }
        return isActive(option)
            ? "\(option.descriptor.displayName), active language"
            : option.descriptor.displayName
    }
}
