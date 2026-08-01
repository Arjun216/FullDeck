import Domain
import SwiftUI

/// The purchase surface (FR-14, spec Decision 5). A dedicated sheet rather than
/// an inline buy button: the extra room is what lets the app say what $0.99
/// actually buys.
///
/// No confirm-then-buy alert. StoreKit's own sheet already carries the price, the
/// terms and a biometric confirmation; a second one is friction dressed as
/// courtesy.
struct PurchaseSheet: View {
    let viewModel: PurchaseViewModel
    let onUnlocked: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Text(viewModel.displayName)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("All 1000 words. One payment, yours for good.")
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                Spacer()
                stateContent
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        // NFR-6: the default toolbar tint is AccentColor
                        // (#D97706), 3.07:1 on the background — a fill colour,
                        // not a body-text one. Same fix as the Study screen.
                        .foregroundStyle(Color.textPrimary)
                }
            }
            .task { await viewModel.loadProduct() }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .idle, .loadingProduct, .purchasing:
            ProgressView()
        case .ready(let price):
            buyButton(price)
        case .purchased:
            // The sheet's job is done; the row behind it unlocks.
            Text("Unlocked.")
                .foregroundStyle(Color.textPrimary)
                .task {
                    onUnlocked()
                    dismiss()
                }
        case .pending:
            message("This purchase is waiting for approval.")
        case .failed(let text):
            VStack(spacing: Spacing.md) {
                message(text)
                if let price = viewModel.lastKnownPrice {
                    buyButton(price)
                }
            }
        case .unavailable(let text):
            message(text)
        }
    }

    private func buyButton(_ price: String) -> some View {
        Button {
            Task { await viewModel.buy() }
        } label: {
            Text("Unlock for \(price)")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        // NFR-6: white on AccentColor is 3.19:1, under AA's 4.5:1 for normal
        // text; on AccentFill (#B45309) it is 5.02:1. Same fix as "Reveal".
        .tint(Color.accentFill)
        .controlSize(.large)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Color.textPrimary)
            .multilineTextAlignment(.center)
    }
}
