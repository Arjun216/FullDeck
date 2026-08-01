import CoreGraphics

/// The 4pt spacing scale (spec Decision 2), replacing the ad-hoc 8/12/16/24 mix.
///
/// A caseless `enum` rather than a `struct`: it has no instances and cannot be
/// accidentally initialised.
///
/// These are *fixed* points, not `@ScaledMetric`. Dynamic Type grows the text and
/// the stacks grow with it; scaling the gaps as well pushes the largest
/// accessibility sizes off screen. NFR-5 is carried by the semantic font styles
/// and the `ScrollView` in `StudyView.cardView`, not by the gaps.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}
