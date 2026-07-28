import Domain
import Testing

@testable import FullDeck

@Test("NFR-10 a schema-version mismatch tells the learner an app update is needed")
func schemaVersionMismatchSuggestsUpdate() {
    let error = PackLoadError.unsupportedSchemaVersion(found: 99, maxSupported: 1)

    #expect(error.userMessage == "This language needs an app update.")
}

@Test("NFR-10 a missing pack file tells the learner to reinstall")
func fileNotFoundSuggestsReinstall() {
    let error = PackLoadError.fileNotFound(languageCode: LanguageCode("fr"))

    #expect(error.userMessage == "This language's data couldn't be read. Try reinstalling the app.")
}

@Test("NFR-10 malformed JSON tells the learner to reinstall")
func malformedJSONSuggestsReinstall() {
    let error = PackLoadError.malformedJSON("unexpected end of file")

    #expect(error.userMessage == "This language's data couldn't be read. Try reinstalling the app.")
}

@Test("NFR-10 a failed validation rule tells the learner to reinstall")
func validationFailedSuggestsReinstall() {
    let error = PackLoadError.validationFailed(rule: "VR-3", reason: "duplicate word id")

    #expect(error.userMessage == "This language's data couldn't be read. Try reinstalling the app.")
}
