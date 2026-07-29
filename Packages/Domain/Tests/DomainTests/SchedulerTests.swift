import Foundation
import Testing

@testable import Domain

// A fixed instant on a UTC day boundary. Tests never read the wall clock
// (scripts/determinism-check.sh enforces this) — `today` is always passed in.
private let day0 = Date(timeIntervalSince1970: 86_400 * 20_000)  // 2024-10-04T00:00:00Z

private func day(_ offset: Int) -> Date {
    day0.addingTimeInterval(TimeInterval(offset) * 86_400)
}

private let chat = WordID("fr:chat:NOUN")

@Test("FR-8 a first passing review schedules the word one day out")
func firstPassingReviewSchedulesOneDay() {
    let state = ReviewState(wordID: chat)

    let next = Scheduler().schedule(state, grade: .recalled, today: day0)

    #expect(next.intervalDays == 1)
    #expect(next.nextReviewDate == day(1))
}

@Test("FR-8 the second passing review jumps to a six-day interval")
func secondPassingReviewSchedulesSixDays() {
    let state = ReviewState(wordID: chat, intervalDays: 1, repetitions: 1, nextReviewDate: day(1))

    let next = Scheduler().schedule(state, grade: .recalled, today: day(1))

    #expect(next.intervalDays == 6)
    #expect(next.nextReviewDate == day(7))
}

@Test("FR-8 a passing grade increments the repetition count")
func passingGradeIncrementsRepetitions() {
    let state = ReviewState(wordID: chat, intervalDays: 6, repetitions: 1, nextReviewDate: day(7))

    let next = Scheduler().schedule(state, grade: .recalled, today: day(7))

    #expect(next.repetitions == 2)
}

@Test("FR-8 from the third review on, the interval multiplies by the ease factor")
func matureIntervalMultipliesByEaseFactor() {
    let state = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 6, repetitions: 2, nextReviewDate: day(7))

    let next = Scheduler().schedule(state, grade: .recalled, today: day(7))

    #expect(next.intervalDays == 15)  // 6 × 2.5
    #expect(next.nextReviewDate == day(22))
}

@Test("FR-8 a failing grade resets the interval and the repetition count")
func failingGradeResetsIntervalAndRepetitions() {
    let state = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 30, repetitions: 5, nextReviewDate: day(30))

    let next = Scheduler().schedule(state, grade: .forgot, today: day(30))

    #expect(next.intervalDays == 1)
    #expect(next.repetitions == 0)
    #expect(next.nextReviewDate == day(31))
}

// `arguments:` runs the same test body once per case — Swift Testing's
// table-driven form, reported as separate results.
@Test(
    "FR-8 each grade moves the ease factor by its own delta",
    arguments: [
        (Grade.forgot, 2.30),
        (Grade.recalled, 2.50),
    ])
func gradeMovesEaseFactorByItsDelta(grade: Grade, expectedEase: Double) {
    let state = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 6, repetitions: 2, nextReviewDate: day(7))

    let next = Scheduler().schedule(state, grade: grade, today: day(7))

    #expect(abs(next.easeFactor - expectedEase) < 1e-9)
}

@Test("FR-8 repeated failures cannot drive the ease factor below its floor")
func easeFactorStaysAboveItsFloor() {
    let state = ReviewState(
        wordID: chat, easeFactor: 1.35, intervalDays: 10, repetitions: 3,
        nextReviewDate: day(10))

    let next = Scheduler().schedule(state, grade: .forgot, today: day(10))

    #expect(abs(next.easeFactor - 1.30) < 1e-9)
}

@Test("FR-8 the interval never grows past its one-year ceiling")
func intervalNeverGrowsPastCeiling() {
    let state = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 300, repetitions: 10, nextReviewDate: day(300))

    let next = Scheduler().schedule(state, grade: .recalled, today: day(300))

    #expect(next.intervalDays == 365)  // 300 × 2.5 = 750, capped
    #expect(next.nextReviewDate == day(665))
}

// MARK: - The learned threshold (Phase 9)

@Test("FR-10 a word that lands below the learned interval is not learned")
func belowLearnedIntervalIsNotLearned() {
    // Ease 2.2 — a word that has lapsed before. 6 × 2.2 = 13.2 → 13, one short.
    let state = ReviewState(
        wordID: chat, easeFactor: 2.2, intervalDays: 6, repetitions: 2,
        nextReviewDate: day(7), firstReviewedDate: day0)

    let next = Scheduler().schedule(state, grade: .recalled, today: day(7))

    #expect(next.intervalDays == 13)
    #expect(next.learnedDate == nil)
}

@Test("FR-10 crossing the learned interval stamps learnedDate")
func crossingLearnedIntervalStampsLearnedDate() {
    // Ease 2.5 — same shape as the test above, one notch easier. 6 × 2.5 = 15.
    let state = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 6, repetitions: 2,
        nextReviewDate: day(7), firstReviewedDate: day0)

    let next = Scheduler().schedule(state, grade: .recalled, today: day(7))

    #expect(next.intervalDays == 15)
    #expect(next.learnedDate == day(7))
}

@Test("FR-10 a lapse does not un-learn a word")
func lapseDoesNotUnlearnWord() {
    let learned = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 15, repetitions: 3,
        nextReviewDate: day(22), firstReviewedDate: day0, learnedDate: day(7))

    let next = Scheduler().schedule(learned, grade: .forgot, today: day(22))

    #expect(next.intervalDays == 1)
    #expect(next.learnedDate == day(7))
}

@Test("FR-10 a later review does not restamp learnedDate")
func laterReviewDoesNotRestampLearnedDate() {
    let learned = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 15, repetitions: 3,
        nextReviewDate: day(22), firstReviewedDate: day0, learnedDate: day(7))

    let next = Scheduler().schedule(learned, grade: .recalled, today: day(22))

    #expect(next.intervalDays == 38)
    #expect(next.learnedDate == day(7))
}

@Test("FR-4 a first review stamps firstReviewedDate")
func firstReviewStampsFirstReviewedDate() {
    let state = ReviewState(wordID: chat)

    let next = Scheduler().schedule(state, grade: .recalled, today: day0)

    #expect(next.firstReviewedDate == day0)
}

@Test("FR-4 a later review leaves firstReviewedDate alone")
func laterReviewLeavesFirstReviewedDateAlone() {
    let state = ReviewState(
        wordID: chat, intervalDays: 1, repetitions: 1, nextReviewDate: day(1),
        firstReviewedDate: day0)

    let next = Scheduler().schedule(state, grade: .recalled, today: day(1))

    #expect(next.firstReviewedDate == day0)
}

// MARK: - Invariants

/// SplitMix64 — a tiny seeded generator. The stdlib's default RNG cannot be
/// seeded, and `scripts/determinism-check.sh` forbids it in tests: a property
/// test that can't be replayed from its seed is a flake waiting to happen.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

/// The example tests above prove the listed cases. This one walks 2,000 random
/// (grade, review-day) steps and asserts the properties hold at *every* step —
/// it's what catches drift and off-by-ones at clamps only reached after many
/// repetitions, which no hand-written case would think to visit.
@Test("FR-8 scheduling invariants hold across a long seeded random walk")
func schedulingInvariantsHoldAcrossSeededRandomWalk() {
    var rng = SeededGenerator(seed: 0xF001_2026)
    let scheduler = Scheduler()
    var state = ReviewState(wordID: chat)
    var today = day0
    var everCrossedLearnedInterval = false

    for step in 0..<2_000 {
        let grade = Grade.allCases.randomElement(using: &rng) ?? .recalled
        let previousInterval = state.intervalDays

        let next = scheduler.schedule(state, grade: grade, today: today)

        #expect(next.nextReviewDate >= today, "step \(step): next review fell into the past")
        #expect(
            Scheduler.easeRange.contains(next.easeFactor),
            "step \(step): ease \(next.easeFactor) escaped its clamp")
        #expect(
            Scheduler.intervalRange.contains(next.intervalDays),
            "step \(step): interval \(next.intervalDays) escaped its clamp")
        if grade == .forgot {
            // `max(_, 1)` because a never-reviewed word starts at interval 0 and
            // a lapse still schedules it for tomorrow — the floor, not a growth.
            #expect(
                next.intervalDays <= max(previousInterval, 1),
                "step \(step): a failing grade lengthened the interval")
        }
        #expect(
            scheduler.schedule(state, grade: grade, today: today) == next,
            "step \(step): scheduling is not pure — same inputs gave different output")
        if next.intervalDays >= Scheduler.learnedIntervalDays { everCrossedLearnedInterval = true }
        #expect(
            next.firstReviewedDate != nil,
            "step \(step): a reviewed word has no firstReviewedDate")
        if let previouslyLearned = state.learnedDate {
            #expect(
                next.learnedDate == previouslyLearned,
                "step \(step): learnedDate moved after it was set")
        }
        #expect(
            next.learnedDate == nil || everCrossedLearnedInterval,
            "step \(step): learnedDate was set without any interval reaching the threshold")

        state = next
        // Learners review late as often as on time; jitter the next visit so the
        // walk exercises overdue reviews too.
        let daysLate = Int.random(in: 0...3, using: &rng)
        today = next.nextReviewDate.addingTimeInterval(TimeInterval(daysLate) * 86_400)
    }
}
