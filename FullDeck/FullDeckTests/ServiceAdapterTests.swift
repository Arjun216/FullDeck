import Testing
import UserNotifications

@testable import FullDeck

/// `UNNotificationScheduler`, which the Phase 13 coverage review found at 0%.
///
/// Its *passthrough* is not worth a test — asserting that Apple's framework was
/// called is not a fact about this app, and the file says so. What is worth a
/// test is the part we author: the shape of the request, where a one-word slip
/// turns a daily reminder into a monthly one and nothing notices for a month.
@Suite("Platform adapters")
struct ServiceAdapterTests {
    @Test("FR-13 the reminder request repeats daily at the requested time")
    func reminderRequestRepeatsDaily() throws {
        let request = UNNotificationScheduler.reminderRequest(hour: 7, minute: 5)

        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.repeats)
        #expect(trigger.dateComponents.hour == 7)
        #expect(trigger.dateComponents.minute == 5)
        // No day, month or weekday: anything else here would make it fire once a
        // month, or once a week, rather than daily.
        #expect(trigger.dateComponents.day == nil)
        #expect(trigger.dateComponents.weekday == nil)
        #expect(trigger.dateComponents.month == nil)
    }

    @Test("FR-13 every reminder request carries the one identifier that makes it single")
    func reminderRequestUsesTheOneIdentifier() {
        let morning = UNNotificationScheduler.reminderRequest(hour: 8, minute: 0)
        let evening = UNNotificationScheduler.reminderRequest(hour: 20, minute: 30)

        // Adding a request with an existing identifier *replaces* it. That is the
        // whole mechanism behind "exactly one reminder" — two identifiers would
        // mean a learner who changed the time got two notifications a day.
        #expect(morning.identifier == evening.identifier)
        #expect(morning.identifier == UNNotificationScheduler.reminderIdentifier)
    }

    @Test("FR-13 the reminder says something, and promises nothing it cannot know")
    func reminderContentIsHonest() {
        let request = UNNotificationScheduler.reminderRequest(hour: 9, minute: 0)

        #expect(!request.content.title.isEmpty)
        // Deliberately empty: a repeating local notification cannot know the due
        // count at fire time, so a body like "5 cards ready" would be a lie on
        // the days there are none.
        #expect(request.content.body.isEmpty)
    }

    // No `AVSpeechService` test here, and the omission is deliberate rather than
    // an oversight the coverage table caught us in.
    //
    // One was written. `#expect(throws:)` on a language with no voice passes, and
    // costs **55 seconds** — the first touch of `AVSpeechSynthesisVoice` loads the
    // system voice catalogue, and a minute on every run buys very little: the
    // guard's *consumer* is already covered (`StudyViewModelTests`
    // "unavailableVoiceDegradesGracefully" drives the same error through a fake),
    // and deleting the guard would not crash — it would speak in the wrong voice,
    // which is a thing only a person with a real device and working ears can
    // judge. The simulator's voice set is not the phone's, so passing here would
    // not have meant much either way.
    //
    // It is on the manual QA checklist instead (`docs/test-plan.md` §6, FR-7),
    // where "does this sound like French" is a question that can actually be
    // answered.
}
