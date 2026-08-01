# Warm Minimal Token Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the app's default system-blue-on-white appearance with the warm
minimal palette and a named spacing scale, without regressing the gated
accessibility audit.

**Architecture:** Colors live as asset-catalog colorsets, not Swift constants — the
catalog resolves light/dark automatically and Xcode generates compile-checked Swift
symbols for each one (`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS
= YES` is already on, both build configurations). Filling `AccentColor` is the
single highest-leverage step: it is wired as
`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`, so it retints the tab bar,
`.borderedProminent`, and `.bordered` everywhere at once with zero code. Views then
swap SwiftUI's `.primary`/`.secondary` for the warm text tokens and gain an explicit
screen background. Spacing becomes a five-value enum replacing the ad-hoc 8/12/16/24
mix.

**Tech Stack:** SwiftUI, Xcode 26 asset catalogs, XCUITest
(`performAccessibilityAudit`).

## Global Constraints

- Source spec: `docs/superpowers/specs/2026-07-28-binary-recall-and-warm-ui-design.md`,
  Decision 2. Palette and contrast ratios there are settled — do not re-derive them.
- **`#D97706` must never be used as body text.** It is 3.07:1 on the light
  background — the fill/large-text bar, not the 4.5:1 normal-text bar. `#B45309`
  (`AccentText`) is the text-safe variant.
- Typography stays on SwiftUI's semantic styles (`.largeTitle`, `.body`,
  `.footnote`). Tokens set **weight and color only** — never hardcoded point sizes.
  NFR-5 / Dynamic Type depends on the semantic styles staying intact.
- Warnings are errors: the app target sets `SWIFT_TREAT_WARNINGS_AS_ERRORS`.
- SwiftLint runs `--strict`; any violation fails CI.
- No test may read `Date()`, sleep, or use unseeded randomness
  (`scripts/determinism-check.sh` greps for these).
- Conventional commits, small and focused.
- Work on a branch off `main`: `git checkout -b warm-token-layer`.

### Asset naming deviation from the spec — read before Task 1

The spec names three tokens `Background`, `Surface`, and `Separator`. Xcode's
generated symbols would emit `static var background`, `surface`, and `separator` on
`ShapeStyle where Self == Color`. SwiftUI **already** declares `.background`
(`BackgroundStyle`) and `.separator` on `ShapeStyle`, so `.background(.background)`
becomes an ambiguous overload the compiler cannot resolve.

This plan therefore prefixes exactly the colliding names: `AppBackground`,
`AppSurface`, `AppSeparator`. `TextPrimary`, `TextSecondary`, `AccentText`, and
`AccentColor` are collision-free and keep their spec names. `AppSurface` takes the
prefix for consistency with its two neighbours even though `surface` alone would
compile. Hex values, light/dark pairs, and intended use are unchanged from the spec.

### Known contrast trade to report at wrap-up — do not silently accept

`.borderedProminent` renders a white label on the accent fill. Measured against the
new light-mode accent `#D97706`, that is **3.19:1** — under WCAG AA's 4.5:1 for
normal text. The current system blue is ~3.5:1, so this is marginally worse, and
`FullDeckUITests.performAudit` already excludes the Reveal button's contrast finding
on the grounds that it is "Apple's own default prominent-button appearance". Once
the accent is ours, that justification no longer holds — the exclusion starts
shielding a colour we picked.

Do **not** redesign the palette here. Implement Decision 2 as specified, and record
the measurement in Task 4 so it is decided deliberately when part 3
(swipe-to-grade) revisits button styling anyway.

---

### Task 1: Colour tokens in the asset catalog

Adding colorsets needs no `project.pbxproj` edit: the target uses
`PBXFileSystemSynchronizedRootGroup` (objectVersion 77), so anything inside
`FullDeck/FullDeck/` is picked up from disk automatically.

**Files:**
- Modify: `FullDeck/FullDeck/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create: `FullDeck/FullDeck/Assets.xcassets/AccentText.colorset/Contents.json`
- Create: `FullDeck/FullDeck/Assets.xcassets/AppBackground.colorset/Contents.json`
- Create: `FullDeck/FullDeck/Assets.xcassets/AppSurface.colorset/Contents.json`
- Create: `FullDeck/FullDeck/Assets.xcassets/TextPrimary.colorset/Contents.json`
- Create: `FullDeck/FullDeck/Assets.xcassets/TextSecondary.colorset/Contents.json`
- Create: `FullDeck/FullDeck/Assets.xcassets/AppSeparator.colorset/Contents.json`
- Test: `FullDeck/FullDeckUITests/FullDeckUITests.swift` (existing audit, not edited)

**Interfaces:**
- Consumes: nothing.
- Produces: seven generated Swift symbols usable as `Color` / `ShapeStyle` —
  `Color.accentText`, `Color.appBackground`, `Color.appSurface`,
  `Color.textPrimary`, `Color.textSecondary`, `Color.appSeparator`. `AccentColor` is
  consumed implicitly by the build setting, never referenced by name in code.

- [ ] **Step 1: Fill in `AccentColor`**

It currently has an `idiom` entry with no `color` key at all, which is why the app
renders system blue.

Write `FullDeck/FullDeck/Assets.xcassets/AccentColor.colorset/Contents.json`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0x06",
          "green" : "0x77",
          "red" : "0xD9"
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
          "blue" : "0x0B",
          "green" : "0x9E",
          "red" : "0xF5"
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

- [ ] **Step 2: Create the six remaining colorsets**

Every file has the identical shape as Step 1 — only the two `components` blocks
differ. Create each directory and its `Contents.json`.

`AccentText.colorset` — light `#B45309`, dark `#FCD34D`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0x09", "green" : "0x53", "red" : "0xB4" }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0x4D", "green" : "0xD3", "red" : "0xFC" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`AppBackground.colorset` — light `#FFFBEB`, dark `#1C1917`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0xEB", "green" : "0xFB", "red" : "0xFF" }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0x17", "green" : "0x19", "red" : "0x1C" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`AppSurface.colorset` — light `#FFFFFF`, dark `#292524`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0xFF", "green" : "0xFF", "red" : "0xFF" }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0x24", "green" : "0x25", "red" : "0x29" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`TextPrimary.colorset` — light `#1C1917`, dark `#FAFAF9`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0x17", "green" : "0x19", "red" : "0x1C" }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0xF9", "green" : "0xFA", "red" : "0xFA" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`TextSecondary.colorset` — light `#57534E`, dark `#A8A29E`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0x4E", "green" : "0x53", "red" : "0x57" }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0x9E", "green" : "0xA2", "red" : "0xA8" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`AppSeparator.colorset` — light `#F5E9C8`, dark `#44403C`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0xC8", "green" : "0xE9", "red" : "0xF5" }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0x3C", "green" : "0x40", "red" : "0x44" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 3: Verify every `Contents.json` is valid JSON**

An asset catalog with malformed JSON fails at build time with a message that names
the catalog, not the file — check them directly first.

Run:

```bash
for f in FullDeck/FullDeck/Assets.xcassets/*.colorset/Contents.json; do python3 -m json.tool "$f" > /dev/null && echo "ok $f"; done
```

Expected: seven `ok` lines, no errors.

- [ ] **Step 4: Build and run the full app test suite**

`AccentColor` alone is a visible change: the tab bar, the Reveal button, and the two
grade buttons all retint. The accessibility audit is what proves it did not regress.

Run:

```bash
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: `** TEST SUCCEEDED **`.

**Do not trust that line alone.** `-only-testing:` runs have previously reported
success with zero tests executed. Confirm the real count from the result bundle
path printed in the log:

```bash
xcrun xcresulttool get test-results summary --path <path-to-.xcresult>
```

Expected: the same total as the last green run on `main` (53), zero failures.

If `testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens` fails with a contrast finding
on a *grade* button (`Knew it!` / `Let's try this again`), that is a genuine
regression, not the known Reveal trade — those buttons are `.bordered`, whose fill
is a translucent accent tint, and their labels are already pinned to
`.foregroundStyle(.primary)`. Report it rather than widening the audit's exclusion
filter.

- [ ] **Step 5: Commit**

```bash
git add FullDeck/FullDeck/Assets.xcassets
git commit -m "feat: add the warm minimal colour tokens"
```

---

### Task 2: Apply the tokens across the four screens

**Files:**
- Modify: `FullDeck/FullDeck/Views/StudyView.swift`
- Modify: `FullDeck/FullDeck/Views/LanguageSelectionView.swift`
- Modify: `FullDeck/FullDeck/Views/LearningProgressView.swift`
- Modify: `FullDeck/FullDeck/ContentView.swift`
- Test: `FullDeck/FullDeckUITests/FullDeckUITests.swift` (existing audit, not edited)

**Interfaces:**
- Consumes: `Color.appBackground`, `Color.textPrimary`, `Color.textSecondary` from
  Task 1.
- Produces: nothing new. `Color.appSurface`, `Color.appSeparator`, and
  `Color.accentText` stay unused until part 3 adds the card treatment — that is
  expected, and an unused colorset produces no warning.

`ErrorStateView.swift` is deliberately untouched: it is a bare
`ContentUnavailableView` rendered *inside* each screen's `content`, so it inherits
the background applied by its parent in this task.

- [ ] **Step 1: Give `StudyView` the warm background and text tokens**

In `FullDeck/FullDeck/Views/StudyView.swift`, replace the `body`:

```swift
    var body: some View {
        NavigationStack {
            content
                // The screen base (spec Decision 2). maxWidth/maxHeight makes the
                // background fill the tab even when `content` is a small
                // ProgressView or ContentUnavailableView.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
                .navigationTitle("Study")
                .task { await viewModel.start() }
        }
    }
```

Then swap the text colours. Every `.foregroundStyle(.primary)` in this file becomes
`.foregroundStyle(Color.textPrimary)`, and the two `.foregroundStyle(.secondary)`
become `.foregroundStyle(Color.textSecondary)`. The existing NFR-6 comments stay —
they still explain *why* the colour is pinned; only the token changed. Add the
contrast figure to the first one so the reason is checkable:

```swift
            Text("\(card.index) of \(card.total)")
                .font(.footnote)
                // NFR-6: `.secondary` at `.footnote` size falls under WCAG
                // AA's 4.5:1 normal-text threshold (caught by the
                // accessibility audit). `Color.textPrimary` (#1C1917 on
                // #FFFBEB) is 16.87:1.
                .foregroundStyle(Color.textPrimary)
```

The full set of replacements in this file — nine call sites:

| Line (pre-edit) | Was | Becomes |
|---|---|---|
| 57 | `.foregroundStyle(.primary)` | `.foregroundStyle(Color.textPrimary)` |
| 70 | `.foregroundStyle(.primary)` | `.foregroundStyle(Color.textPrimary)` |
| 82 | `.foregroundStyle(.primary)` | `.foregroundStyle(Color.textPrimary)` |
| 97 | `.foregroundStyle(.primary)` | `.foregroundStyle(Color.textPrimary)` |
| 119 | `.foregroundStyle(.primary)` | `.foregroundStyle(Color.textPrimary)` |
| 140 | `.foregroundStyle(.primary)` | `.foregroundStyle(Color.textPrimary)` |
| 174 | `.foregroundStyle(.secondary)` | `.foregroundStyle(Color.textSecondary)` |
| 183 | `.foregroundStyle(.primary)` | `.foregroundStyle(Color.textPrimary)` |

Verify none were missed:

```bash
grep -n "foregroundStyle(\.\(primary\|secondary\))" FullDeck/FullDeck/Views/StudyView.swift
```

Expected: no output.

- [ ] **Step 2: Give `LearningProgressView` the same treatment**

In `FullDeck/FullDeck/Views/LearningProgressView.swift`, replace the `body`:

```swift
    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
                .navigationTitle("Progress")
                .task { await viewModel.load() }
        }
    }
```

And the big count plus its two captions:

```swift
        case .ready(let learned, let total):
            VStack(spacing: 8) {
                Text("\(learned)")
                    .font(.system(size: countSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                Text("of \(total) words learned")
                    .font(.title3)
                    .foregroundStyle(Color.textSecondary)
                if viewModel.state.isComplete {
                    Text("Every word. That's the whole deck.")
                        .font(.callout)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(learned) of \(total) words learned")
```

`Color.textSecondary` is `#57534E` — 7.36:1 on the light background, better than the
system `.secondary` it replaces, so this cannot regress the audit.

- [ ] **Step 3: Give `LanguageSelectionView` the background through its `List`**

A `List` paints its own opaque system background, so the outer
`.background(Color.appBackground)` is invisible until `.scrollContentBackground(.hidden)`
removes it. The rows need the same treatment for the same reason.

In `FullDeck/FullDeck/Views/LanguageSelectionView.swift`, replace the `body`:

```swift
    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
                .navigationTitle("Languages")
                .task { await viewModel.load() }
        }
    }
```

And the `.ready` case:

```swift
        case .ready(let options):
            List(options) { option in
                Button {
                    viewModel.select(option)
                } label: {
                    HStack {
                        // Default Button styling tints this system blue, which
                        // fails WCAG AA contrast at body text size (caught by
                        // the accessibility audit) — the checkmark already
                        // carries the "selected" signal, so this text doesn't
                        // need to borrow the accent color too.
                        Text(option.descriptor.displayName)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        if !option.isUnlocked {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(Color.textSecondary)
                        } else if isActive(option) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!option.isUnlocked)
                .accessibilityLabel(accessibilityLabel(for: option))
                // Rows are opaque by default and would punch system-grey holes
                // in the warm background.
                .listRowBackground(Color.appBackground)
            }
            // A List paints its own background over the one set on the
            // NavigationStack content; hiding it lets the warm base show.
            .scrollContentBackground(.hidden)
```

The `checkmark` is left untinted on purpose — it now picks up the warm
`AccentColor` from Task 1, which is exactly the intent, and as a glyph it is a
graphical object held to 3:1 rather than 4.5:1.

- [ ] **Step 4: Give the placeholder tab the background too**

In `FullDeck/FullDeck/ContentView.swift`, replace `chooseALanguage`:

```swift
    private var chooseALanguage: some View {
        ContentUnavailableView(
            "Choose a language", systemImage: "globe",
            description: Text("Pick a language on the Languages tab to start."))
        // Not inside a NavigationStack, so it does not inherit a screen
        // background from either of the other two tabs.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
```

- [ ] **Step 5: Lint**

Run:

```bash
swiftlint lint --strict
```

Expected: `Done linting! Found 0 violations`.

- [ ] **Step 6: Build and run the full app test suite**

Run:

```bash
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: `** TEST SUCCEEDED **`, 53 tests, zero failures — confirmed from the
result bundle as in Task 1 Step 4, not from the summary line alone.

If the audit reports a contrast finding here, read *which element*: this task moves
every text colour to a token with a **higher** measured ratio than what it replaced,
so a text failure means a token was applied to the wrong element, not that the
palette is too weak.

If `testAppLaunchesWithThreeTabs` fails with "Failed to get background assertion …
Timed out", that is a simulator flake from a second app instance, not a regression —
close any manually launched instance (`xcrun simctl terminate booted
arjunpathak.FullDeck`) and re-run before investigating further.

- [ ] **Step 7: Commit**

```bash
git add FullDeck/FullDeck/Views FullDeck/FullDeck/ContentView.swift
git commit -m "feat: apply the warm colour tokens to the three screens"
```

---

### Task 3: The spacing scale

**Files:**
- Create: `FullDeck/FullDeck/DesignSystem/Spacing.swift`
- Modify: `FullDeck/FullDeck/Views/StudyView.swift`
- Modify: `FullDeck/FullDeck/Views/LearningProgressView.swift`

A new subdirectory needs no `project.pbxproj` edit — the synchronized root group
picks it up from disk, same as the colorsets in Task 1.

**Interfaces:**
- Consumes: nothing.
- Produces: `enum Spacing` with five `static let` members of type `CGFloat` —
  `Spacing.xs` (4), `Spacing.sm` (8), `Spacing.md` (16), `Spacing.lg` (24),
  `Spacing.xl` (32).

- [ ] **Step 1: Create the scale**

Write `FullDeck/FullDeck/DesignSystem/Spacing.swift`:

```swift
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
```

- [ ] **Step 2: Use it in `StudyView`**

Four call sites in `FullDeck/FullDeck/Views/StudyView.swift`:

| Was | Becomes |
|---|---|
| `VStack(spacing: 24) {` in `cardContent` | `VStack(spacing: Spacing.lg) {` |
| `VStack(spacing: 8) {` in `cardContent` | `VStack(spacing: Spacing.sm) {` |
| `VStack(spacing: 12) {` in `revealedContent` | `VStack(spacing: Spacing.md) {` |
| `HStack(spacing: 12) {` in `gradeButtons` | `HStack(spacing: Spacing.md) {` |
| `VStack(spacing: 16) {` in `completionView` | `VStack(spacing: Spacing.md) {` |

The two `12`s round **up** to `md` (16) rather than down to `sm` (8): 12 was already
closer to a comfortable gap than a tight one, and the scale has no 12.

Leave both bare `.padding()` calls alone. SwiftUI's default padding on iOS is
already 16 — writing `.padding(Spacing.md)` changes nothing at runtime and adds a
line to review.

- [ ] **Step 3: Use it in `LearningProgressView`**

One call site:

| Was | Becomes |
|---|---|
| `VStack(spacing: 8) {` | `VStack(spacing: Spacing.sm) {` |

- [ ] **Step 4: Verify no bare spacing literals remain in the views**

Run:

```bash
grep -rn "spacing: [0-9]" FullDeck/FullDeck
```

Expected: no output.

- [ ] **Step 5: Lint, build, and run the full app test suite**

Run:

```bash
swiftlint lint --strict
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: 0 violations; `** TEST SUCCEEDED **`, 53 tests, zero failures — confirmed
from the result bundle.

The gaps only widen (12 → 16), so `testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens`
is the one to watch: a "may be clipped" finding at large Dynamic Type would mean the
`ScrollView` in `cardView` is no longer absorbing the growth. Report it rather than
reverting to 12 — the fix belongs in the layout, not the scale.

- [ ] **Step 6: Commit**

```bash
git add FullDeck/FullDeck/DesignSystem FullDeck/FullDeck/Views
git commit -m "feat: replace ad-hoc spacing with the 4pt scale"
```

---

### Task 4: Record the change and hand off to part 3

**Files:**
- Modify: `docs/next-task.md`
- Modify: `docs/build-plan.md`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing.

- [ ] **Step 1: Point `docs/next-task.md` at part 3**

Rewrite the "Right now" block so it names the next task rather than this one:

- **Task:** Phase 10.5 part 3 — swipe to grade
- **Model:** Sonnet 5, default effort
- **Why Sonnet:** Decision 3 of the spec settles the gesture, the direction
  mapping, and the accessibility fallback.

Then summarise what part 2 shipped, in the same voice as the existing entries: the
seven colorsets; that `AccentColor` was wired as the global accent and so retinted
the tab bar and every button with no code; the `AppBackground`/`AppSurface`/
`AppSeparator` prefix and *why* (SwiftUI already owns `.background` and `.separator`
on `ShapeStyle`, so the generated symbols would have been ambiguous); the `Spacing`
scale and that its values are deliberately unscaled.

Record the two things a fresh reader would otherwise rediscover the hard way:

- A `List` paints its own opaque background over anything set on the enclosing
  `NavigationStack` content — `.scrollContentBackground(.hidden)` plus
  `.listRowBackground` is what lets the screen base through.
- **White on the light-mode accent `#D97706` is 3.19:1**, under WCAG AA's 4.5:1 for
  normal text. `performAudit` in `FullDeckUITests` already excludes the Reveal
  button's contrast finding as "Apple's own default prominent-button appearance" —
  that justification expired the moment the accent became ours. Decide it in part 3,
  which touches button styling anyway. `#B45309` (`AccentText`) as the prominent
  fill measures 5.02:1 against white and would clear the bar.

Move the "Then" table up by one: part 3 is no longer a future row once "Right now"
names it. Renumber the remaining rows so Phase 11 design is 1, Phase 11 execution
is 2, Phase 12 is 3.

Update the Phase 10.5 row in "Full remaining map" to strike through the token layer
and leave swipe-to-grade standing.

Leave the "Carried forward from Phase 10" block untouched — both manual checklists
in `docs/phase-10-verification.md` and the two unaudited screens
(`StudyView.completionView`, `StudyView.caughtUpView`) are still open.

- [ ] **Step 2: Tick the token layer off in `docs/build-plan.md`**

In the `PHASE 10.5` section, mark the warm-minimal-tokens sub-decision as done with
today's date, matching how the binary recall scale line was marked. Leave the
swipe-to-grade line open.

- [ ] **Step 3: Commit**

```bash
git add docs/next-task.md docs/build-plan.md
git commit -m "docs: record the warm token layer and point at swipe to grade"
```

- [ ] **Step 4: Open the pull request**

```bash
git push -u origin warm-token-layer
gh pr create --title "Warm minimal token layer" --body "Implements Decision 2 of the binary-recall-and-warm-UI spec."
```

Then report to Arjun, in the PR body and in the session: the seven tokens, the
`App*` prefix deviation and its compile-level reason, and the 3.19:1 measurement on
white-over-`#D97706` with the `#B45309` alternative. That last one is a decision he
owns, not a bug to quietly fix here.

---

## Self-Review

**Spec coverage.** Decision 2 has three parts. Colors: all seven tokens land in Task
1 with the spec's exact hex pairs, and Task 2 applies the three that current UI has
a use for. Typography: the spec says keep the semantic styles and set weight and
colour only — no task touches a font size, and Task 2's table is colour-only.
Spacing: Task 3 builds the five-value scale and replaces every literal. The one
uncovered spec sentence is `AccentColor` retinting "the tab bar,
`.borderedProminent`, and every plain button at once" — that needs no task, it is
what the `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` build setting already
does, and Task 1 Step 4 is where it gets verified.

**Unused tokens.** `AppSurface`, `AppSeparator`, and `AccentText` are created in
Task 1 and used by nothing. This is deliberate and called out in Task 2's
Interfaces block: the current screens have no cards and no hairlines, so part 3 is
their first consumer. They are eight lines of JSON each and splitting them into a
later commit would only move the same work.

**Contrast direction.** Every colour swap in Task 2 replaces a system semantic style
with a token of equal or higher measured contrast (`.primary` → 16.87:1,
`.secondary` → 7.36:1), so no text swap can regress the audit. The only ratio that
moves the wrong way is white-on-accent for `.borderedProminent`, which is already
covered by an existing exclusion, is measured in the Global Constraints, and is
escalated rather than absorbed in Task 4 Step 1.

**Type consistency.** `Spacing.xs/sm/md/lg/xl` are declared once in Task 3 Step 1 and
used with those exact names in Steps 2 and 3. The generated colour symbols are
written `Color.appBackground`, `Color.textPrimary`, `Color.textSecondary`,
`Color.appSurface`, `Color.appSeparator`, `Color.accentText` in every task that
names them — lowerCamelCase of the colorset directory name, which is how Xcode
generates them.

**Verification is honest, not ceremonial.** This is framework glue, not logic:
colour is asset-catalog data and the spacing scale is five constants, neither of
which has an input→output behaviour worth a unit test under the project's testing
standards. The real gate is
`testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens`, which already exists and already
runs in CI — so every task's test step runs the whole app suite and reads the actual
count out of the result bundle rather than trusting `** TEST SUCCEEDED **`.
