import SwiftUI

/// The shared `.failed` state rendering for the three top-level views. Phase 10
/// owns the final user-facing copy — this keeps the current wording verbatim.
///
/// Written out rather than as a `ContentUnavailableView`, which is what it was
/// until Phase 13 made the screen reachable (`-uiTestUnreadablePack`) and the
/// accessibility audit saw it for the first time. The system component failed
/// the audit twice on the same node: its description renders in `.secondary`,
/// under 4.5:1 on the warm background, and then — with the colour corrected, and
/// with an explicit `.font(.body)` — still reported "user will not be able to
/// change the font size of this SwiftUI.AccessibilityNode".
///
/// `caughtUpView` uses the same component and passes, so this is not a blanket
/// verdict on `ContentUnavailableView`; the difference appears to be a
/// *runtime* `String` description rather than a literal. Rather than keep
/// guessing at a system view's internals, this screen is now four ordinary
/// views the project already knows how to make accessible. Same layout, same
/// words, and every attribute is ours.
struct ErrorStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Color.textSecondary)
                // The heading below says the same thing in words.
                .accessibilityHidden(true)
            Text("Something went wrong")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                // NFR-5: lets the text take its full ideal height at large
                // Dynamic Type sizes rather than being compressed by the VStack.
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Color.textPrimary)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                // NFR-6: `.secondary` is under 4.5:1 on AppBackground at this
                // size — the defect this screen shipped with. TextPrimary is
                // 16.87:1.
                .foregroundStyle(Color.textPrimary)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // One element to VoiceOver: "Something went wrong" and the reason are one
        // message, not two things to swipe between.
        .accessibilityElement(children: .combine)
    }
}
