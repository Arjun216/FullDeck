import Domain
import Foundation
import Testing

@testable import FullDeck

@Test("FR-5 dragging right past the threshold commits a recalled grade")
func draggingRightPastThresholdCommitsRecalled() {
    let grade = CardSwipe.grade(forTranslation: 120, cardWidth: 300)

    #expect(grade == .recalled)
}

@Test("FR-5 dragging left past the threshold commits a forgot grade")
func draggingLeftPastThresholdCommitsForgot() {
    #expect(CardSwipe.grade(forTranslation: -120, cardWidth: 300) == .forgot)
}

@Test("FR-5 a drag short of the threshold commits nothing")
func shortDragCommitsNothing() {
    #expect(CardSwipe.grade(forTranslation: 40, cardWidth: 300) == nil)
    #expect(CardSwipe.grade(forTranslation: -40, cardWidth: 300) == nil)
}

// The boundary is the whole reason this is a separate type: exactly-at-threshold
// commits, one point short does not.
@Test("FR-5 the threshold itself commits, a point short of it does not")
func thresholdBoundaryCommits() {
    #expect(CardSwipe.grade(forTranslation: 75, cardWidth: 300) == .recalled)
    #expect(CardSwipe.grade(forTranslation: 74, cardWidth: 300) == nil)
}

// A card laid out at zero width would otherwise divide by it.
@Test("FR-5 an unresolved card width grades nothing")
func zeroWidthGradesNothing() {
    #expect(CardSwipe.grade(forTranslation: 500, cardWidth: 0) == nil)
    #expect(CardSwipe.progress(forTranslation: 500, cardWidth: 0) == 0)
}

@Test("FR-5 drag progress runs 0 to 1 and clamps at the threshold")
func progressClampsAtOne() {
    #expect(CardSwipe.progress(forTranslation: 0, cardWidth: 300) == 0)
    #expect(abs(CardSwipe.progress(forTranslation: 37.5, cardWidth: 300) - 0.5) < 1e-9)
    #expect(CardSwipe.progress(forTranslation: 75, cardWidth: 300) == 1)
    #expect(CardSwipe.progress(forTranslation: 900, cardWidth: 300) == 1)
}

// Direction must not change how *far* you have to drag.
@Test("FR-5 progress is symmetric in both directions")
func progressIsSymmetric() {
    #expect(
        CardSwipe.progress(forTranslation: -50, cardWidth: 300)
            == CardSwipe.progress(forTranslation: 50, cardWidth: 300))
}
