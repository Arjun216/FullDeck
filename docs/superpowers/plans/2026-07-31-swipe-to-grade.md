# Swipe to Grade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the learner grade a revealed card by swiping it — right for
`recalled`, left for `forgot` — while both buttons stay fully functional.

**Architecture:** The commit decision (does this drag distance count as a grade, and
which one?) is pure input→output logic, so it is extracted to a testable
`CardSwipe` type and driven test-first. The view keeps only the gesture plumbing:
offset, rotation, and a hint whose opacity tracks drag progress. The swipe needs
something to swipe, so this phase also introduces the card surface — the first
consumer of the `AppSurface` and `AppSeparator` tokens added in part 2.

**Tech Stack:** SwiftUI `DragGesture`, Swift Testing (`@Test`/`#expect`), XCUITest
(`performAccessibilityAudit`).

## Global Constraints

- Source spec:
  `docs/superpowers/specs/2026-07-28-binary-recall-and-warm-ui-design.md`,
  Decision 3.
- **Both buttons remain visible and functional.** Gesture-only features are the
  top accessibility failure; every custom gesture needs a visible-control
  equivalent. The swipe is an accelerator, never the only path.
- **Reveal stays, and grading before reveal still does nothing.** The flow is
  see word → attempt → Reveal → swipe. Allowing a grade before reveal converts
  verified self-testing into unverified self-assessment, which is the exact
  failure active recall exists to prevent. `gradingBeforeRevealDoesNothing` keeps
  its test, and the swipe must not create a second path around it.
- Button labels are `Knew it!` and `Let's try this again` — settled by the product
  owner, not to be re-litigated.
- Test-first for logic: write the failing test, run it, confirm it fails *because
  the behaviour is missing*, then the minimal code. Not a batch of tests followed
  by a wall of code.
- No test may read `Date()`, sleep, or use unseeded randomness
  (`scripts/determinism-check.sh` greps for these).
- Warnings are errors; SwiftLint runs `--strict`.
- Conventional commits, small and focused.
- Branch `swipe-to-grade` is already created off `main`.

### The inherited contrast fix — Task 1, not deferred again

Part 2 measured white-on-`#D97706` at **3.19:1** under `.borderedProminent`, below
WCAG AA's 4.5:1 for normal text, and left it for this phase on the grounds that
this phase touches button styling. It does. Fix it here.

The fix is *not* to retint with `AccentText`. That token is `#B45309` in light but
`#FCD34D` in dark, and white on `#FCD34D` is ~1.2:1 — trading a light-mode
failure for a far worse dark-mode one. It is also not to change `AccentColor`
itself: its dark value `#F59E0B` has to stay bright to work as *text* on the dark
background (8.15:1), and white on `#F59E0B` is 2.15:1.

A prominent **fill** and an accent **text** colour have opposite requirements, so
they need separate tokens. Task 1 adds `AccentFill` at `#B45309` in *both*
appearances:

| Pair | Ratio | Verdict |
|---|---|---|
| white on `#B45309` | 5.02:1 | passes AA normal text — light and dark |
| `#B45309` on `#FFFBEB` (light bg) | 4.84:1 | passes as a fill |
| `#B45309` on `#1C1917` (dark bg) | 3.48:1 | passes the 3:1 graphical-object bar |

---

### Task 1: A prominent-button fill that clears WCAG AA

**Files:**
- Create: `FullDeck/FullDeck/Assets.xcassets/AccentFill.colorset/Contents.json`
- Modify: `FullDeck/FullDeck/Views/StudyView.swift`
- Modify: `FullDeck/FullDeckUITests/FullDeckUITests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `Color.accentFill` — the tint for every `.borderedProminent` button.

- [ ] **Step 1: Add the colorset**

Write `FullDeck/FullDeck/Assets.xcassets/AccentFill.colorset/Contents.json`. Both
appearances are `#B45309` on purpose — a fill under a white label has the same
contrast requirement in either mode, unlike accent *text*, which has to invert.

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0x09",
          "green" : "0x53",
          "red" : "0xB4"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0x09",
          "green" : "0x53",
          "red" : "0xB4"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

Validate it:

```bash
python3 -m json.tool FullDeck/FullDeck/Assets.xcassets/AccentFill.colorset/Contents.json > /dev/null && echo ok
```

Expected: `ok`.

- [ ] **Step 2: Tint both prominent buttons**

In `FullDeck/FullDeck/Views/StudyView.swift`, the Reveal button:

```swift
                Button("Reveal") { viewModel.reveal() }
                    .buttonStyle(.borderedProminent)
                    // NFR-6: `.borderedProminent` puts a white label on the
                    // accent fill. White on AccentColor (#D97706) is 3.19:1,
                    // under WCAG AA's 4.5:1 for normal text; on AccentFill
                    // (#B45309) it is 5.02:1.
                    .tint(Color.accentFill)
                    .accessibilityHint("Shows the answer")
```

And the completion screen's unlock button, which has the same style and the same
problem:

```swift
            Button("Add another language — $0.99", action: onAddLanguage)
                .buttonStyle(.borderedProminent)
                // NFR-6: same white-on-accent issue as the Reveal button.
                .tint(Color.accentFill)
                .accessibilityHint("Opens the languages list")
```

- [ ] **Step 3: Retire the audit's contrast exclusion**

This is the point of the task. `performAudit` currently filters out the Reveal
button's contrast finding; with the fill fixed there is nothing left to excuse, and
keeping the filter would hide the next real regression.

In `FullDeck/FullDeckUITests/FullDeckUITests.swift`, replace `performAudit`
entirely:

```swift
    /// No issue filter. The one known exclusion — `.borderedProminent`'s white
    /// label on the accent fill — was retired when the prominent buttons moved
    /// to `AccentFill` (#B45309, 5.02:1 against white). A filter that outlives
    /// the problem it was written for hides the next real regression.
    private func performAudit(on app: XCUIApplication) throws {
        try app.performAccessibilityAudit()
    }
```

- [ ] **Step 4: Run the full app test suite**

Run:

```bash
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: `** TEST SUCCEEDED **`. Confirm the real count out of the result bundle —
`** TEST SUCCEEDED **` has previously been printed for a run that executed zero
tests:

```bash
RESULT=$(ls -td ~/Library/Developer/Xcode/DerivedData/FullDeck-*/Logs/Test/*.xcresult | head -1)
xcrun xcresulttool get test-results summary --path "$RESULT"
```

Expected: 53 total, 0 failed.

If the audit now reports a contrast finding on Reveal, the tint did not take —
check that `.tint` is applied *after* `.buttonStyle`, not before. If it reports one
on a *different* element, that is a genuine pre-existing issue the exclusion was
masking; report it rather than restoring the filter.

- [ ] **Step 5: Commit**

```bash
git add FullDeck/FullDeck/Assets.xcassets FullDeck/FullDeck/Views/StudyView.swift FullDeck/FullDeckUITests/FullDeckUITests.swift
git commit -m "fix: give prominent buttons a fill that clears WCAG AA"
```

---

### Task 2: The commit rule, test-first

The only part of a swipe that is input→output logic: given how far the finger
travelled and how wide the card is, does this count as a grade, and which one?
Extracting it keeps the threshold testable at its exact boundary, which is not
something a UI test can pin down.

**Files:**
- Create: `FullDeck/FullDeck/DesignSystem/CardSwipe.swift`
- Test: `FullDeck/FullDeckTests/CardSwipeTests.swift`

**Interfaces:**
- Consumes: `Domain.Grade` (`.forgot`, `.recalled`).
- Produces:
  - `enum CardSwipe`
  - `static let commitFraction: CGFloat` — fraction of card width that commits.
  - `static func grade(forTranslation: CGFloat, cardWidth: CGFloat) -> Grade?` —
    `nil` means "not far enough, spring back".
  - `static func progress(forTranslation: CGFloat, cardWidth: CGFloat) -> Double` —
    0…1, how close the drag is to committing. Drives the hint's opacity.

- [ ] **Step 1: Write the first failing test**

Create `FullDeck/FullDeckTests/CardSwipeTests.swift`:

```swift
import Domain
import Foundation
import Testing

@testable import FullDeck

@Test("FR-5 dragging right past the threshold commits a recalled grade")
func draggingRightPastThresholdCommitsRecalled() {
    let grade = CardSwipe.grade(forTranslation: 120, cardWidth: 300)

    #expect(grade == .recalled)
}
```

- [ ] **Step 2: Run it and confirm it fails for the right reason**

Run:

```bash
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "error:|cannot find"
```

Expected: a compile error naming `CardSwipe` as unresolved. That is the correct
red — the behaviour is missing. A typo in the test is *not* a red; fix and re-run
until it fails for this reason.

- [ ] **Step 3: Write the minimal implementation**

Create `FullDeck/FullDeck/DesignSystem/CardSwipe.swift`:

```swift
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
```

- [ ] **Step 4: Run the test and confirm it passes**

Run:

```bash
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "draggingRightPastThreshold|\*\* TEST"
```

Expected: `draggingRightPastThresholdCommitsRecalled()` passed.

- [ ] **Step 5: Add the remaining behaviours, one test at a time**

Append to `CardSwipeTests.swift`. Each of these already passes against the
implementation above — they are the cases that pin it down, so add them, run, and
confirm green rather than expecting a red:

```swift
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
```

- [ ] **Step 6: Run the suite and lint**

Run:

```bash
swiftlint lint --strict
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: 0 violations; 59 tests total (53 + 6 new), 0 failed, confirmed from the
result bundle.

- [ ] **Step 7: Commit**

```bash
git add FullDeck/FullDeck/DesignSystem/CardSwipe.swift FullDeck/FullDeckTests/CardSwipeTests.swift
git commit -m "feat: add the swipe commit rule"
```

---

### Task 3: The card surface

The swipe needs something visibly swipeable — dragging unanchored text reads as a
glitch. This is also what finally consumes `AppSurface` and `AppSeparator`, added
in part 2 with no consumer.

**Files:**
- Modify: `FullDeck/FullDeck/Views/StudyView.swift`

**Interfaces:**
- Consumes: `Color.appSurface`, `Color.appSeparator`, `Spacing` from part 2.
- Produces: nothing new. Task 4 attaches the gesture to this surface.

- [ ] **Step 1: Wrap the card content in a surface**

In `FullDeck/FullDeck/Views/StudyView.swift`, replace `cardContent`'s trailing
`.padding()` with the surface treatment. The `VStack` and everything inside it are
unchanged:

```swift
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Spacing.md, style: .continuous)
                .fill(Color.appSurface)
                .stroke(Color.appSeparator, lineWidth: 1)
        )
        .padding(Spacing.md)
    }
```

The two paddings do different jobs: the inner one is the card's own gutter, the
outer one is the margin between the card and the screen edge. `.frame(maxWidth:
.infinity)` makes the card fill the available width rather than shrink-wrapping
the word, so it reads as a card rather than a label.

- [ ] **Step 2: Look at it**

Build and install, then screenshot the Study tab. This step is not decorative —
the audit cannot tell you whether a card looks like a card.

```bash
xcodebuild build -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'
```

Then install the built `.app`, launch, tap Study, and screenshot. Confirm: white
card on the cream background, hairline border visible, the word centred, the card
reaching near both screen edges.

**Terminate the manually launched instance before running any test**
(`xcrun simctl terminate booted arjunpathak.FullDeck`). A second app instance
contends with the `xcodebuild test` runner's own and produces a "Failed to get
background assertion … Timed out" failure that looks like a regression and is not.

- [ ] **Step 3: Run the full suite and lint**

Run:

```bash
swiftlint lint --strict
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: 0 violations; 59 tests, 0 failed, confirmed from the result bundle.

The audit is the one to watch here. `AppSurface` is `#FFFFFF` in light, so the text
tokens sit on white rather than cream — `#1C1917` is 17.9:1 and `#57534E` is 7.8:1
on white, both *higher* than on cream, so no text can regress. A "may be clipped"
finding at large Dynamic Type would instead mean the new paddings pushed content
past what the `ScrollView` absorbs; report it rather than shrinking the padding
blindly.

- [ ] **Step 4: Commit**

```bash
git add FullDeck/FullDeck/Views/StudyView.swift
git commit -m "feat: give the study card a surface"
```

---

### Task 4: The swipe gesture

**Files:**
- Modify: `FullDeck/FullDeck/Views/StudyView.swift`
- Modify: `FullDeck/FullDeck/Localizable.xcstrings`
- Test: `FullDeck/FullDeckUITests/FullDeckUITests.swift` (existing tests, not
  edited — see Step 5 for why no new UI test)

**Interfaces:**
- Consumes: `CardSwipe.grade(forTranslation:cardWidth:)`,
  `CardSwipe.progress(forTranslation:cardWidth:)` from Task 2; the card surface
  from Task 3.
- Produces: nothing.

- [ ] **Step 1: Add the drag state**

At the top of `StudyView`, beside the existing `let` properties:

```swift
    /// Live horizontal offset of the card while a finger is down. Reset to zero
    /// when the drag is released — either because it sprang back or because the
    /// next card replaced this one.
    @State private var dragTranslation: CGFloat = 0
    /// Measured, not assumed: the commit threshold is a fraction of the card's
    /// real width, which differs by device and orientation.
    @State private var cardWidth: CGFloat = 0
```

- [ ] **Step 2: Add the hint overlay and its strings**

Add this to `StudyView`. It renders the label of whichever grade the current drag
direction would commit, fading in with progress so the card responds to the finger
before anything is decided:

```swift
    /// The grade this drag *would* commit, or nil at rest. Direction alone
    /// decides it — distance only drives the opacity.
    private var pendingGrade: Grade? {
        if dragTranslation > 0 { return .recalled }
        if dragTranslation < 0 { return .forgot }
        return nil
    }

    @ViewBuilder
    private var swipeHint: some View {
        if let pendingGrade {
            Text(label(for: pendingGrade))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .padding(Spacing.sm)
                .opacity(CardSwipe.progress(forTranslation: dragTranslation, cardWidth: cardWidth))
                // Decoration: the buttons below already announce both grades, and
                // a label that fades in mid-gesture would be read out mid-drag.
                .accessibilityHidden(true)
        }
    }
```

No new `Localizable.xcstrings` entries are needed — `label(for:)` already returns
the two localized strings the buttons use, and reusing them is what keeps the hint
and the button that does the same thing from ever disagreeing.

- [ ] **Step 3: Attach the gesture to the card**

Replace `cardView` in `FullDeck/FullDeck/Views/StudyView.swift`:

```swift
    private func cardView(_ card: StudyViewModel.Card) -> some View {
        // NFR-5: at the largest accessibility Dynamic Type sizes this card's
        // content (word, buttons, grade row) can exceed the screen height —
        // a ScrollView lets it grow instead of clip, caught by the
        // accessibility audit's "may be clipped" finding.
        ScrollView {
            cardContent(card)
                .overlay(swipeHint)
                .offset(x: dragTranslation)
                // Tilt with the drag. Dividing by 20 keeps a full-width throw
                // under about 20 degrees — enough to feel physical, not enough
                // to make the word hard to read on the way out.
                .rotationEffect(.degrees(Double(dragTranslation) / 20))
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                    cardWidth = $0
                }
                // Only a revealed card can be graded (FR-5). Without this the
                // swipe would be a second path around `reveal()`, which is the
                // one thing active recall exists to prevent — `grade()` would
                // reject it, but the card would still animate as if it worked.
                .gesture(card.isRevealed ? swipeGesture : nil)
                .animation(.spring(duration: 0.3), value: dragTranslation)
        }
    }

    private var swipeGesture: some Gesture {
        // minimumDistance lets the enclosing ScrollView claim vertical drags
        // first, so scrolling a long card at large type sizes still works.
        DragGesture(minimumDistance: 20)
            .onChanged { dragTranslation = $0.translation.width }
            .onEnded { value in
                guard
                    let grade = CardSwipe.grade(
                        forTranslation: value.translation.width, cardWidth: cardWidth)
                else {
                    dragTranslation = 0
                    return
                }
                // Throw the card clear before the next one arrives, then reset
                // without animation so the incoming card starts centred.
                dragTranslation = value.translation.width > 0 ? cardWidth * 2 : -cardWidth * 2
                Task {
                    await viewModel.grade(grade)
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { dragTranslation = 0 }
                }
            }
    }
```

- [ ] **Step 4: Verify `onGeometryChange` is available**

`onGeometryChange(for:of:action:)` is iOS 18+. The project's deployment target is
iOS 17, so this will not compile if that is still true.

Run:

```bash
grep -n "IPHONEOS_DEPLOYMENT_TARGET" FullDeck/FullDeck.xcodeproj/project.pbxproj | sort -u
```

If it reports 18.0 or higher, continue. If it reports 17.x, replace the
`.onGeometryChange` line with a `GeometryReader` in a `.background`, which works on
17:

```swift
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { cardWidth = proxy.size.width }
                            .onChange(of: proxy.size.width) { _, new in cardWidth = new }
                    }
                )
```

Do not raise the deployment target to avoid the older spelling — that drops
devices for a layout convenience.

- [ ] **Step 5: Drive the gesture in the simulator**

There is deliberately **no new XCUITest here.** The commit rule is already pinned
by Task 2's six unit tests at the exact boundary, and an XCUITest swipe cannot
express "74 points does not commit, 75 does" — it would assert that swiping works
at all, which is an expensive restatement of what the unit tests already prove.
`testFR3StudySessionSurvivesATabSwitch` continues to cover the button path
end-to-end.

Build, install, launch, and drive it by hand:

1. Study tab → Reveal.
2. Short drag right (under a quarter of the card width) → card springs back, no
   advance. Confirm the card index is unchanged.
3. Full drag right → hint reads "Knew it!", card leaves right, next card centred.
4. Full drag left → hint reads "Let's try this again", card leaves left, advances.
5. Before Reveal, drag → **nothing moves.** This is the constraint that matters
   most; if the card tracks the finger pre-reveal, the `card.isRevealed` guard on
   the gesture is wrong.
6. Both buttons still work.

Use the simulator control tool's `touch_path` for the drags — a plain `swipe`
starting within 4pt of the screen edge triggers the OS back gesture instead.

**Terminate the manual instance before Step 6.**

- [ ] **Step 6: Run the full suite and lint**

Run:

```bash
swiftlint lint --strict
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: 0 violations; 59 tests, 0 failed, confirmed from the result bundle.

- [ ] **Step 7: Commit**

```bash
git add FullDeck/FullDeck/Views/StudyView.swift
git commit -m "feat: grade a revealed card by swiping it"
```

---

### Task 5: Record the change and hand off to Phase 11

**Files:**
- Modify: `docs/next-task.md`
- Modify: `docs/build-plan.md`

- [ ] **Step 1: Point `docs/next-task.md` at Phase 11**

Rewrite the "Right now" block:

- **Task:** Phase 11 design — StoreKit 2 purchase/entitlement state machine
- **Model:** Opus 5, xhigh effort
- **Why Opus:** new API surface, purchase correctness, and IAP is new to Arjun —
  no spec exists yet, so this is a decision, not a diff.

Summarise what part 3 shipped: swipe right for `recalled`, left for `forgot`, with
both buttons retained as the accessible path; the commit rule extracted to
`CardSwipe` so its threshold is unit-tested at the boundary; the card surface, which
is what finally consumes `AppSurface` and `AppSeparator`.

Record the two things worth not rediscovering:

- The gesture is attached conditionally on `card.isRevealed`. `grade()` would
  reject a pre-reveal grade anyway, but without the guard the card animates as
  though the swipe worked — a silent lie about a mechanic the product is built on.
- `performAudit`'s contrast exclusion is **gone**, and `AccentFill` (`#B45309`,
  both appearances) is why. A prominent fill under a white label and an accent
  used as text have opposite contrast requirements; one token cannot serve both.

Then delete the whole part-2 carry-forward about the 3.19:1 finding — it is fixed,
and a resolved warning left in a living doc is worse than no warning.

Leave the "Carried forward from Phase 10" block untouched: both manual checklists in
`docs/phase-10-verification.md` and the two unaudited screens
(`StudyView.completionView`, `StudyView.caughtUpView`) are still open.

Move the "Then" table up by one and renumber. Strike the swipe-to-grade row in
"Full remaining map" with today's date.

- [ ] **Step 2: Close out Phase 10.5 in `docs/build-plan.md`**

Strike through sub-decision 3 with today's date, matching 1 and 2. All three parts
are then done, so note that the phase is complete and Phase 11 is next.

- [ ] **Step 3: Commit and open the PR**

```bash
git add docs/next-task.md docs/build-plan.md
git commit -m "docs: record swipe to grade and close out phase 10.5"
git push -u origin swipe-to-grade
gh pr create --title "Swipe to grade" --body "Implements Decision 3 of the binary-recall-and-warm-UI spec, and fixes the WCAG AA prominent-button contrast finding part 2 deferred here."
```

---

## Self-Review

**Spec coverage.** Decision 3 has four claims. Direction mapping: Task 2 pins
right→`recalled` and left→`forgot` in unit tests, Task 4 wires it. "The card tracks
the finger with a live directional hint": Task 4's `offset`, `rotationEffect`, and
`swipeHint`, whose opacity is `CardSwipe.progress`. "Both buttons remain visible and
functional": no task touches `gradeButtons`, and Task 4 Step 5 checks them by hand.
"Reveal stays": the gesture is attached only when `card.isRevealed`, and
`gradingBeforeRevealDoesNothing` is untouched. The button-labels section needs no
task — those labels shipped in part 1 and `label(for:)` is reused for the hint.

**The contrast fix belongs here.** It arrived as a deferral from part 2 rather than
from Decision 3, but the deferral's stated condition was "the phase that touches
button styling", and this is it. Doing it first, in its own task, keeps it
reviewable separately from the gesture work.

**Test-first is real, not decorative.** Task 2 is the only genuinely testable logic
in the phase, and it is driven properly: one failing test, a run that confirms it
fails because `CardSwipe` does not exist, then the minimal implementation. The five
follow-up tests are honestly labelled as pinning tests that pass on arrival rather
than being dressed up as further reds. Tasks 1, 3 and 4 are framework glue — a
colorset, a rounded rectangle, and gesture plumbing — where the existing
accessibility audit and a hands-on simulator pass are the honest checks, and Task 4
Step 5 says plainly why no XCUITest was added rather than leaving the gap unexplained.

**Type consistency.** `CardSwipe.grade(forTranslation:cardWidth:)` and
`CardSwipe.progress(forTranslation:cardWidth:)` are declared in Task 2 Step 3 and
called with those exact labels in Task 2 Step 5 and Task 4 Steps 2–3.
`dragTranslation` and `cardWidth` are declared in Task 4 Step 1 and used in Steps
2–3. `Color.accentFill` is created in Task 1 and used only there. `Color.appSurface`,
`Color.appSeparator` and `Spacing.*` all came from part 2 and are already on `main`.

**Known risk, flagged not hidden.** The `DragGesture` sits inside the `ScrollView`
added in Phase 10. `minimumDistance: 20` is the intended mitigation — the ScrollView
claims vertical drags first — but gesture arbitration is not something a unit test
settles. Task 4 Step 5 checks scrolling still works at large Dynamic Type sizes by
hand. `onGeometryChange` is iOS 18+, so Task 4 Step 4 verifies the deployment target
before relying on it and supplies the iOS 17 spelling rather than quietly raising
the floor.
