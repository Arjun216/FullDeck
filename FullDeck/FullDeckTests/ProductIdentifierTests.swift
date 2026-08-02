import Domain
import Testing

@testable import FullDeck

@Test("FR-14 a language's product id is derived from its code, never stored")
func derivesProductIdentifierFromLanguageCode() {
    #expect(
        ProductIdentifier.forLanguage(LanguageCode("hi"))
            == "arjunpathak.FullDeck.language.hi")
}

@Test("FR-14 a transaction's product id maps back to its language")
func derivesLanguageCodeFromProductIdentifier() {
    #expect(
        ProductIdentifier.languageCode(from: "arjunpathak.FullDeck.language.hi")
            == LanguageCode("hi"))
}

@Test("NFR-10 a product id from outside this app maps to no language")
func foreignProductIdentifiersMapToNoLanguage() {
    // StoreKit hands back every transaction on the account, not only ours.
    #expect(ProductIdentifier.languageCode(from: "com.example.other") == nil)
    #expect(ProductIdentifier.languageCode(from: "arjunpathak.FullDeck.language.") == nil)
}
