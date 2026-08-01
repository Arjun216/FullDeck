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
