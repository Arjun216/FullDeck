import Domain
import Testing

@testable import FullDeck

@Test("FR-3 starting a session presents the first card")
@MainActor
func startPresentsTheFirstCard() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let viewModel = makeStudyViewModel(pack: pack)

    await viewModel.start()

    #expect(
        viewModel.state
            == .card(
                StudyViewModel.Card(
                    entry: pack.words[0], isRevealed: false, index: 1, total: 2)))
}

@Test("FR-5 a freshly presented card hides its answer")
@MainActor
func freshCardHidesTheAnswer() async {
    let viewModel = makeStudyViewModel()

    await viewModel.start()

    guard case .card(let card) = viewModel.state else {
        Issue.record("expected a card, got \(viewModel.state)")
        return
    }
    #expect(!card.isRevealed)
}

@Test("FR-6 every card carries exactly one non-empty example sentence")
@MainActor
func cardCarriesOneExampleSentence() async {
    let viewModel = makeStudyViewModel()

    await viewModel.start()

    guard case .card(let card) = viewModel.state else {
        Issue.record("expected a card, got \(viewModel.state)")
        return
    }
    #expect(!card.entry.example.isEmpty)
}

@Test("FR-12 an empty session shows the caught-up state with the next due date")
@MainActor
func emptySessionShowsCaughtUp() async {
    let pack = frPack([entry("chat", rank: 1)])
    let notYetDue = ReviewState(
        wordID: WordID("fr:chat:NOUN"), intervalDays: 6, repetitions: 2,
        nextReviewDate: day(3), firstReviewedDate: day(-6))
    let viewModel = makeStudyViewModel(
        pack: pack, newWordCap: 0, reviewStore: InMemoryReviewStore(seed: [notYetDue]))

    await viewModel.start()

    #expect(viewModel.state == .caughtUp(nextDue: day(3)))
}

@Test("NFR-10 a missing pack surfaces a failed state instead of crashing")
@MainActor
func missingPackSurfacesFailedState() async {
    let viewModel = makeStudyViewModel(pack: nil)

    await viewModel.start()

    guard case .failed = viewModel.state else {
        Issue.record("expected a failed state, got \(viewModel.state)")
        return
    }
}

@Test("FR-5 reveal exposes the answer side of the card")
@MainActor
func revealExposesTheAnswer() async {
    let viewModel = makeStudyViewModel()
    await viewModel.start()

    viewModel.reveal()

    guard case .card(let card) = viewModel.state else {
        Issue.record("expected a card, got \(viewModel.state)")
        return
    }
    #expect(card.isRevealed)
}

@Test("FR-5 grading before reveal does nothing")
@MainActor
func gradingBeforeRevealDoesNothing() async {
    let store = InMemoryReviewStore()
    let viewModel = makeStudyViewModel(reviewStore: store)
    await viewModel.start()

    await viewModel.grade(.recalled)

    let saved = try? await store.reviewState(for: WordID("fr:chat:NOUN"))
    #expect(saved == nil)
    guard case .card(let card) = viewModel.state else {
        Issue.record("expected to still be on the first card, got \(viewModel.state)")
        return
    }
    #expect(card.index == 1)
}

@Test("FR-8 grading persists the scheduler's updated state")
@MainActor
func gradingPersistsScheduledState() async {
    let store = InMemoryReviewStore()
    let viewModel = makeStudyViewModel(reviewStore: store)
    await viewModel.start()
    viewModel.reveal()

    await viewModel.grade(.recalled)

    let saved = try? await store.reviewState(for: WordID("fr:chat:NOUN"))
    #expect(saved?.repetitions == 1)
    #expect(saved?.intervalDays == 1)
    #expect(saved?.nextReviewDate == day(1))
}

@Test("FR-4 the first grade stamps firstReviewedDate so the daily cap can count it")
@MainActor
func firstGradeStampsFirstReviewedDate() async {
    let store = InMemoryReviewStore()
    let viewModel = makeStudyViewModel(reviewStore: store)
    await viewModel.start()
    viewModel.reveal()

    await viewModel.grade(.recalled)

    let saved = try? await store.reviewState(for: WordID("fr:chat:NOUN"))
    #expect(saved?.firstReviewedDate == day0)
}

@Test("FR-3 grading advances to the next card")
@MainActor
func gradingAdvancesToTheNextCard() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let viewModel = makeStudyViewModel(pack: pack)
    await viewModel.start()
    viewModel.reveal()

    await viewModel.grade(.recalled)

    #expect(
        viewModel.state
            == .card(
                StudyViewModel.Card(
                    entry: pack.words[1], isRevealed: false, index: 2, total: 2)))
}

@Test("FR-12 grading the last card ends the session in the caught-up state")
@MainActor
func gradingLastCardEndsTheSession() async {
    let viewModel = makeStudyViewModel(pack: frPack([entry("chat", rank: 1)]))
    await viewModel.start()
    viewModel.reveal()

    await viewModel.grade(.recalled)

    #expect(viewModel.state == .caughtUp(nextDue: day(1)))
}

@Test("FR-7 speaking the word sends it to the speech port with the pack's language")
@MainActor
func speakWordSendsTheWord() async {
    let speech = FakeSpeechService()
    let viewModel = makeStudyViewModel(speech: speech)
    await viewModel.start()

    viewModel.speakWord()

    #expect(speech.spoken.count == 1)
    #expect(speech.spoken.first?.text == "chat")
    #expect(speech.spoken.first?.language == LanguageCode("fr"))
}

@Test("FR-7 speaking the sentence sends the card's example sentence")
@MainActor
func speakSentenceSendsTheExample() async {
    let speech = FakeSpeechService()
    let viewModel = makeStudyViewModel(speech: speech)
    await viewModel.start()

    viewModel.speakSentence()

    #expect(speech.spoken.first?.text == "Une phrase avec chat.")
}

@Test("FR-7 an unavailable voice flags audio unavailable and leaves the session usable")
@MainActor
func unavailableVoiceDegradesGracefully() async {
    let speech = FakeSpeechService()
    speech.errorToThrow = .voiceUnavailable(LanguageCode("fr"))
    let viewModel = makeStudyViewModel(speech: speech)
    await viewModel.start()

    viewModel.speakWord()

    #expect(viewModel.audioUnavailable)
    guard case .card = viewModel.state else {
        Issue.record("the session must stay usable, got \(viewModel.state)")
        return
    }
}

@Test("FR-8 a double-tapped grade is applied once")
@MainActor
func doubleTappedGradeIsAppliedOnce() async {
    let pack = frPack(
        [entry("chat", rank: 1), entry("chien", rank: 2), entry("maison", rank: 3)])
    let store = InMemoryReviewStore()
    let viewModel = makeStudyViewModel(pack: pack, reviewStore: store)
    await viewModel.start()
    viewModel.reveal()

    // Two unstructured taps on the same revealed card, as `StudyView`'s
    // `Task { await viewModel.grade(grade) }` per button produces. `async let`
    // starts both before either resumes past its first `await` — deterministic
    // interleaving, no sleep needed.
    async let first: Void = viewModel.grade(.recalled)
    async let second: Void = viewModel.grade(.recalled)
    _ = await (first, second)

    let saved = try? await store.reviewState(for: WordID("fr:chat:NOUN"))
    #expect(saved?.repetitions == 1)
    #expect(saved?.intervalDays == 1)
    guard case .card(let card) = viewModel.state else {
        Issue.record("expected still to be on a card, got \(viewModel.state)")
        return
    }
    #expect(card.index == 2)
}

@Test("FR-7 advancing to a new card stops any in-flight speech")
@MainActor
func advancingToANewCardStopsInFlightSpeech() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let speech = FakeSpeechService()
    let viewModel = makeStudyViewModel(pack: pack, speech: speech)
    await viewModel.start()
    viewModel.reveal()
    let stopsBeforeGrading = speech.stopCount

    await viewModel.grade(.recalled)

    #expect(speech.stopCount == stopsBeforeGrading + 1)
}

@Test("FR-3 restarting an in-progress session keeps the current card")
@MainActor
func restartingKeepsTheCurrentCard() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let viewModel = makeStudyViewModel(pack: pack)
    await viewModel.start()
    viewModel.reveal()
    await viewModel.grade(.recalled)

    // The view's .task re-fires every time its tab reappears; that must not
    // throw away the session the learner is halfway through.
    await viewModel.start()

    #expect(
        viewModel.state
            == .card(
                StudyViewModel.Card(
                    entry: pack.words[1], isRevealed: false, index: 2, total: 2)))
}

@Test("FR-11 a pack with every word learned shows the completion state")
@MainActor
func everyWordLearnedShowsCompletionState() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let seed = pack.words.map { learnedState($0) }
    let viewModel = makeStudyViewModel(
        pack: pack, today: day(10), reviewStore: InMemoryReviewStore(seed: seed))

    await viewModel.start()

    #expect(viewModel.state == .complete(nextDue: day(22)))
}

@Test("FR-11 the completion state is not shown while a review is due")
@MainActor
func completionStateNotShownWhileReviewIsDue() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    var seed = pack.words.map { learnedState($0) }
    seed[0].nextReviewDate = day(10)  // learned, but due today
    let viewModel = makeStudyViewModel(
        pack: pack, today: day(10), reviewStore: InMemoryReviewStore(seed: seed))

    await viewModel.start()

    #expect(
        viewModel.state
            == .card(
                StudyViewModel.Card(
                    entry: pack.words[0], isRevealed: false, index: 1, total: 1)))
}

@Test("FR-12 an unfinished pack with an empty queue still shows caught up")
@MainActor
func unfinishedPackWithEmptyQueueShowsCaughtUp() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    // Both seen, neither learned, neither due — caught up, not complete.
    let seed = pack.words.map {
        ReviewState(
            wordID: $0.id, intervalDays: 6, repetitions: 2, nextReviewDate: day(22),
            firstReviewedDate: day0)
    }
    let viewModel = makeStudyViewModel(
        pack: pack, today: day(10), reviewStore: InMemoryReviewStore(seed: seed))

    await viewModel.start()

    #expect(viewModel.state == .caughtUp(nextDue: day(22)))
}

@Test("FR-11 no new words are introduced once the pack is complete")
@MainActor
func noNewWordsIntroducedWhenComplete() async {
    let pack = frPack([entry("chat", rank: 1), entry("chien", rank: 2)])
    let seed = pack.words.map { learnedState($0) }
    let viewModel = makeStudyViewModel(
        pack: pack, today: day(10), newWordCap: 100,
        reviewStore: InMemoryReviewStore(seed: seed))

    await viewModel.start()

    // A cap of 100 against a 2-word pack: if anything could still be introduced,
    // this would be a card.
    #expect(viewModel.state == .complete(nextDue: day(22)))
}

@Test("NFR-10 a schema-version mismatch surfaces the update message")
@MainActor
func studySchemaVersionMismatchSurfacesUpdateMessage() async {
    let viewModel = makeStudyViewModel(
        errorOverride: .unsupportedSchemaVersion(found: 99, maxSupported: 1))

    await viewModel.start()

    #expect(viewModel.state == .failed("This language needs an app update."))
}

@Test("NFR-10 a save failure surfaces a failed state instead of crashing")
@MainActor
func saveFailureSurfacesFailedState() async {
    let store = InMemoryReviewStore(saveErrorOverride: FakeStoreError())
    let viewModel = makeStudyViewModel(reviewStore: store)
    await viewModel.start()
    viewModel.reveal()

    await viewModel.grade(.recalled)

    #expect(viewModel.state == .failed("Couldn't save your progress."))
}
