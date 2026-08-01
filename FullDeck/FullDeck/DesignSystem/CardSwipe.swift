import CoreGraphics
import Domain

/// Turns a horizontal drag into a grade (spec Decision 3): right is `recalled`,
/// left is `forgot`.
///
/// Split out of the view because this is the one part of a swipe that is
/// input→output logic, and its threshold behaviour is worth pinning at the exact
/// boundary — which a UI test cannot do.
enum CardSwipe {
    /// Fraction of the card's width the finger must cross to commit. A quarter is
    /// far enough that a stray horizontal nudge during a vertical scroll doesn't
    /// grade a word, and close enough that a deliberate flick isn't work.
    static let commitFraction: CGFloat = 0.25

    /// `nil` means the drag did not travel far enough — the caller springs back.
    static func grade(forTranslation translation: CGFloat, cardWidth: CGFloat) -> Grade? {
        // A zero or negative width is a layout that hasn't resolved yet. Refusing
        // to grade is the safe reading: the alternative divides by it.
        guard cardWidth > 0 else { return nil }
        let threshold = cardWidth * commitFraction
        if translation >= threshold { return .recalled }
        if translation <= -threshold { return .forgot }
        return nil
    }

    /// 0…1, how close the drag is to committing. Drives the hint's opacity so the
    /// card reads as responding to the finger before anything is decided.
    static func progress(forTranslation translation: CGFloat, cardWidth: CGFloat) -> Double {
        guard cardWidth > 0 else { return 0 }
        let threshold = cardWidth * commitFraction
        return Double(min(abs(translation) / threshold, 1))
    }
}
