import Domain
import Testing

@testable import FullDeck

@MainActor
private func makePurchaseViewModel(
    _ purchases: FakePurchaseService = FakePurchaseService()
) -> PurchaseViewModel {
    PurchaseViewModel(
        languageCode: LanguageCode("hi"), displayName: "हिन्दी", purchases: purchases)
}

@Test("FR-14 the sheet opens idle")
@MainActor
func purchaseSheetStartsIdle() {
    #expect(makePurchaseViewModel().state == .idle)
}

@Test("FR-14 a found product shows StoreKit's localized price")
@MainActor
func loadsTheLocalizedPrice() async {
    let purchases = FakePurchaseService()
    purchases.priceToReturn = "€0,99"
    let viewModel = makePurchaseViewModel(purchases)

    await viewModel.loadProduct()

    #expect(viewModel.state == .ready(price: "€0,99"))
}

@Test("NFR-10 no product for this language is a state, not a crash")
@MainActor
func missingProductIsUnavailable() async {
    let purchases = FakePurchaseService()
    purchases.priceToReturn = nil
    let viewModel = makePurchaseViewModel(purchases)

    await viewModel.loadProduct()

    #expect(viewModel.state == .unavailable("The store isn't reachable right now."))
}

@Test("NFR-10 a store error is the same state as a missing product")
@MainActor
func storeErrorIsUnavailable() async {
    let purchases = FakePurchaseService()
    purchases.priceError = PurchaseFailure.storeError
    let viewModel = makePurchaseViewModel(purchases)

    await viewModel.loadProduct()

    #expect(viewModel.state == .unavailable("The store isn't reachable right now."))
}

@Test("FR-14 a verified purchase unlocks the language")
@MainActor
func successfulPurchase() async {
    let purchases = FakePurchaseService()
    let viewModel = makePurchaseViewModel(purchases)
    await viewModel.loadProduct()

    await viewModel.buy()

    #expect(viewModel.state == .purchased)
    #expect(viewModel.didUnlock)
}

@Test("FR-14 cancelling returns to the price with no error shown")
@MainActor
func cancellingIsSilent() async {
    let purchases = FakePurchaseService()
    purchases.outcomeToReturn = .cancelled
    let viewModel = makePurchaseViewModel(purchases)
    await viewModel.loadProduct()

    await viewModel.buy()

    #expect(viewModel.state == .ready(price: "$0.99"))
    #expect(!viewModel.didUnlock)
}

@Test("FR-14 an Ask-to-Buy purchase waits rather than failing")
@MainActor
func pendingPurchaseWaits() async {
    let purchases = FakePurchaseService()
    purchases.outcomeToReturn = .pending
    let viewModel = makePurchaseViewModel(purchases)
    await viewModel.loadProduct()

    await viewModel.buy()

    #expect(viewModel.state == .pending)
    #expect(!viewModel.didUnlock)
}

@Test("NFR-10 a store failure leaves the language locked and says so")
@MainActor
func failedPurchaseLeavesItLocked() async {
    let purchases = FakePurchaseService()
    purchases.purchaseError = PurchaseFailure.storeError
    let viewModel = makePurchaseViewModel(purchases)
    await viewModel.loadProduct()

    await viewModel.buy()

    #expect(
        viewModel.state == .failed("Couldn't complete the purchase. You haven't been charged."))
    #expect(!viewModel.didUnlock)
}

@Test("NFR-10 an unverified transaction is a failure, never a success")
@MainActor
func unverifiedTransactionIsAFailure() async {
    let purchases = FakePurchaseService()
    purchases.purchaseError = PurchaseFailure.unverified
    let viewModel = makePurchaseViewModel(purchases)
    await viewModel.loadProduct()

    await viewModel.buy()

    #expect(!viewModel.didUnlock)
    if case .failed = viewModel.state {
    } else {
        Issue.record("unverified must not unlock anything, got \(viewModel.state)")
    }
}

@Test("FR-14 a failed purchase can be retried without reopening the sheet")
@MainActor
func retryAfterFailure() async {
    let purchases = FakePurchaseService()
    purchases.purchaseError = PurchaseFailure.storeError
    let viewModel = makePurchaseViewModel(purchases)
    await viewModel.loadProduct()
    await viewModel.buy()

    purchases.purchaseError = nil
    await viewModel.buy()

    #expect(viewModel.state == .purchased)
    #expect(purchases.purchaseCount == 2)
}

@Test("NFR-10 buying before the price loads does not reach the store")
@MainActor
func buyingBeforeReadyIsANoOp() async {
    let purchases = FakePurchaseService()
    let viewModel = makePurchaseViewModel(purchases)

    await viewModel.buy()

    #expect(purchases.purchaseCount == 0)
    #expect(viewModel.state == .idle)
}
