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

    let next = Scheduler().schedule(state, grade: .good, today: day0)

    #expect(next.intervalDays == 1)
    #expect(next.nextReviewDate == day(1))
}

@Test("FR-8 the second passing review jumps to a six-day interval")
func secondPassingReviewSchedulesSixDays() {
    let state = ReviewState(wordID: chat, intervalDays: 1, repetitions: 1, nextReviewDate: day(1))

    let next = Scheduler().schedule(state, grade: .good, today: day(1))

    #expect(next.intervalDays == 6)
    #expect(next.nextReviewDate == day(7))
}

@Test("FR-8 a passing grade increments the repetition count")
func passingGradeIncrementsRepetitions() {
    let state = ReviewState(wordID: chat, intervalDays: 6, repetitions: 1, nextReviewDate: day(7))

    let next = Scheduler().schedule(state, grade: .good, today: day(7))

    #expect(next.repetitions == 2)
}

@Test("FR-8 from the third review on, the interval multiplies by the ease factor")
func matureIntervalMultipliesByEaseFactor() {
    let state = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 6, repetitions: 2, nextReviewDate: day(7))

    let next = Scheduler().schedule(state, grade: .good, today: day(7))

    #expect(next.intervalDays == 15)  // 6 × 2.5
    #expect(next.nextReviewDate == day(22))
}

@Test("FR-8 a failing grade resets the interval and the repetition count")
func failingGradeResetsIntervalAndRepetitions() {
    let state = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 30, repetitions: 5, nextReviewDate: day(30))

    let next = Scheduler().schedule(state, grade: .again, today: day(30))

    #expect(next.intervalDays == 1)
    #expect(next.repetitions == 0)
    #expect(next.nextReviewDate == day(31))
}

// `arguments:` runs the same test body once per case — Swift Testing's
// table-driven form, reported as four separate results.
@Test(
    "FR-8 each grade moves the ease factor by its own delta",
    arguments: [
        (Grade.again, 2.30),
        (Grade.hard, 2.35),
        (Grade.good, 2.50),
        (Grade.easy, 2.65),
    ])
func gradeMovesEaseFactorByItsDelta(grade: Grade, expectedEase: Double) {
    let state = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 6, repetitions: 2, nextReviewDate: day(7))

    let next = Scheduler().schedule(state, grade: grade, today: day(7))

    #expect(abs(next.easeFactor - expectedEase) < 1e-9)
}

@Test(
    "FR-8 the ease factor stays inside its clamps",
    arguments: [
        (1.35, Grade.again, 1.30),  // floor: repeated failures can't drive ease to zero
        (2.95, Grade.easy, 3.00),  // ceiling: intervals can't run away
    ])
func easeFactorStaysInsideItsClamps(startEase: Double, grade: Grade, expectedEase: Double) {
    let state = ReviewState(
        wordID: chat, easeFactor: startEase, intervalDays: 10, repetitions: 3,
        nextReviewDate: day(10))

    let next = Scheduler().schedule(state, grade: grade, today: day(10))

    #expect(abs(next.easeFactor - expectedEase) < 1e-9)
}

@Test("FR-8 a hard grade grows the interval by a small fixed step, not by the ease factor")
func hardGradeGrowsIntervalBySmallStep() {
    let state = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 10, repetitions: 3, nextReviewDate: day(10))

    let next = Scheduler().schedule(state, grade: .hard, today: day(10))

    #expect(next.intervalDays == 12)  // 10 × 1.2 — textbook SM-2 would give 10 × 2.35
}

@Test("FR-8 a grade schedules with the ease it just changed, not the old one")
func gradeSchedulesWithTheEaseItJustChanged() {
    let state = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 10, repetitions: 3, nextReviewDate: day(10))

    let next = Scheduler().schedule(state, grade: .easy, today: day(10))

    #expect(next.intervalDays == 27)  // 10 × 2.65 (raised ease), not 10 × 2.5
}

@Test("FR-8 the interval never grows past its one-year ceiling")
func intervalNeverGrowsPastCeiling() {
    let state = ReviewState(
        wordID: chat, easeFactor: 2.5, intervalDays: 300, repetitions: 10, nextReviewDate: day(300))

    let next = Scheduler().schedule(state, grade: .good, today: day(300))

    #expect(next.intervalDays == 365)  // 300 × 2.5 = 750, capped
    #expect(next.nextReviewDate == day(665))
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

    for step in 0..<2_000 {
        let grade = Grade.allCases.randomElement(using: &rng) ?? .good
        let previousInterval = state.intervalDays

        let next = scheduler.schedule(state, grade: grade, today: today)

        #expect(next.nextReviewDate >= today, "step \(step): next review fell into the past")
        #expect(
            Scheduler.easeRange.contains(next.easeFactor),
            "step \(step): ease \(next.easeFactor) escaped its clamp")
        #expect(
            Scheduler.intervalRange.contains(next.intervalDays),
            "step \(step): interval \(next.intervalDays) escaped its clamp")
        if grade == .again {
            // `max(_, 1)` because a never-reviewed word starts at interval 0 and
            // a lapse still schedules it for tomorrow — the floor, not a growth.
            #expect(
                next.intervalDays <= max(previousInterval, 1),
                "step \(step): a failing grade lengthened the interval")
        }
        #expect(
            scheduler.schedule(state, grade: grade, today: today) == next,
            "step \(step): scheduling is not pure — same inputs gave different output")

        state = next
        // Learners review late as often as on time; jitter the next visit so the
        // walk exercises overdue reviews too.
        let daysLate = Int.random(in: 0...3, using: &rng)
        today = next.nextReviewDate.addingTimeInterval(TimeInterval(daysLate) * 86_400)
    }
}
