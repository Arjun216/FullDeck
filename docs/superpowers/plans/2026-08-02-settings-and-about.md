# Settings & About Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Settings screen the app has never had, and fill it with the three requirements that were blocked on it — FR-16 credits (a licence obligation), FR-13 daily reminder, FR-4's adjustable new-word cap.

**Architecture:** Presentation-only. A `NavigationLink` row in the Languages list pushes `SettingsView`; `SettingsViewModel` owns the reminder state machine and the cap preference over a new `NotificationScheduler` port; `CreditsViewModel` owns the async pack load that produces attribution. `Packages/` is not touched.

**Tech Stack:** SwiftUI, Swift Testing (`@Test`), XCTest for UI tests, `UserNotifications`, `UserDefaults`, `@Observable`.

**Spec:** [`../specs/2026-08-02-settings-and-about-design.md`](../specs/2026-08-02-settings-and-about-design.md)

## Global Constraints

- **Test-first.** Write one failing test, run it, confirm it fails *because the behaviour is missing* (a compile error is not a red — fix and re-run), then the minimal code to green it. ViewModels are logic under `CLAUDE.md`; they get tests before implementation. The adapter and the views are framework glue and are tested alongside.
- **Every test display name starts with its requirement ID:** `@Test("FR-13 reminders are off by default")`.
- **No test may read `Date()`/`Date.now`, sleep, or use unseeded randomness.** `scripts/determinism-check.sh` greps test sources and fails the build. Store the reminder time as hour/minute `Int`s.
- **Warnings are errors.** The app target sets `SWIFT_TREAT_WARNINGS_AS_ERRORS`.
- **SwiftLint `--strict` is the gate** and must report 0 violations. `swift format` is not gated and disagrees with SwiftLint about brace placement — SwiftLint wins.
- **No new dependencies.** `UserNotifications` is a system framework.
- **`Packages/Domain` and `Packages/Data` must not change.** If a task seems to need a Domain change, stop and flag it — that would contradict the spec's Decision 7.
- **New Swift files under `FullDeck/FullDeck/` need no Xcode work.** The project uses `PBXFileSystemSynchronizedRootGroup`, so files on disk join the target automatically. Do not hand-edit `project.pbxproj`.
- **Strings are extracted automatically.** `Text("...")` literals and `String(localized:)` populate `Localizable.xcstrings` at build time. Do not edit the catalog by hand.
- **Notification copy is fixed:** title `"Time to study"`, no body. No streak, guilt, or urgency language — §4 of the requirements rules out gamification.
- **iOS prompts for notification permission once per install.** Never re-request after a denial.

### Commands

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckTests
```

To run a single Swift Testing function, **the parentheses are required** — without them nothing matches and `xcodebuild` still prints `** TEST SUCCEEDED **`:

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:'FullDeckTests/reminderIsOffByDefault()'
```

Gates:

```sh
swiftlint lint --strict
scripts/determinism-check.sh
scripts/trace-requirements.sh
```

## File Structure

| File | Responsibility |
|---|---|
| `FullDeck/FullDeck/Services/NotificationScheduler.swift` | **Create.** Port, `ReminderAuthorization`, `NoNotificationScheduler` stub |
| `FullDeck/FullDeck/Services/UNNotificationScheduler.swift` | **Create.** The only file importing `UserNotifications` |
| `FullDeck/FullDeck/ViewModels/SettingsViewModel.swift` | **Create.** Reminder state machine + cap preference |
| `FullDeck/FullDeck/ViewModels/CreditsViewModel.swift` | **Create.** Async pack load → grouped `Credit` list |
| `FullDeck/FullDeck/Views/SettingsView.swift` | **Create.** The `Form` |
| `FullDeck/FullDeck/Views/CreditsSection.swift` | **Create.** Attribution rows + licence link |
| `FullDeck/FullDeck/Views/LanguageSelectionView.swift` | **Modify.** One `NavigationLink` row |
| `FullDeck/FullDeck/ContentView.swift` | **Modify.** Own the two new ViewModels; push the cap into `StudyViewModel` |
| `FullDeck/FullDeck/ViewModels/StudyViewModel.swift` | **Modify.** `newWordCap` becomes a `var` |
| `FullDeck/FullDeck/AppDependencies.swift` | **Modify.** Add `notifications:` and `defaults:` |
| `FullDeck/FullDeckTests/SettingsViewModelTests.swift` | **Create.** FR-13 + FR-4 |
| `FullDeck/FullDeckTests/CreditsViewModelTests.swift` | **Create.** FR-16 |
| `FullDeck/FullDeckTests/Fakes.swift` | **Modify.** `FakeNotificationScheduler` |
| `FullDeck/FullDeckUITests/FullDeckUITests.swift` | **Modify.** Reachability test + audit |
| `docs/requirements.md` | **Modify.** FR-4 acceptance amendment |
| `docs/known-issues.md` | **Modify.** Close N-1, N-4; record the FR-4 finding |
| `docs/next-task.md` | **Modify.** Point at part B |

### One deviation from the spec, decided here

Decision 7 said `ContentView` would read the cap with `@AppStorage`. It does not need to: `ContentView` already owns `SettingsViewModel` as `@State`, and `@Observable` makes `settingsViewModel.newWordsPerDay` observable directly. Using `@AppStorage` as well would create a second source of truth for the same key and force a `store:` argument that unit tests cannot inject. `ContentView` observes the ViewModel instead. Same behaviour, one fewer moving part.

---

### Task 1: The Settings container, reachable from Languages

**Files:**
- Create: `FullDeck/FullDeck/ViewModels/SettingsViewModel.swift`
- Create: `FullDeck/FullDeck/Views/SettingsView.swift`
- Modify: `FullDeck/FullDeck/Views/LanguageSelectionView.swift`
- Modify: `FullDeck/FullDeck/ContentView.swift`
- Test: `FullDeck/FullDeckUITests/FullDeckUITests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `SettingsViewModel(defaults: UserDefaults)` — later tasks add a `notifications:` argument. `SettingsView(viewModel: SettingsViewModel)` — Task 2 adds a `credits:` argument.

- [ ] **Step 1: Write the failing UI test**

Add to `FullDeck/FullDeckUITests/FullDeckUITests.swift`, inside the existing test class:

```swift
/// FR-16's acceptance is *reachability*, not content — a ViewModel test cannot
/// prove a screen can be got to. This is the half that was missing as N-4.
@MainActor
func testFR16SettingsIsReachableFromLanguages() throws {
    let app = XCUIApplication()
    app.launch()

    let tabBar = app.tabBars.firstMatch
    XCTAssertTrue(tabBar.buttons["Languages"].waitForExistence(timeout: 15))

    let settings = app.buttons["Settings"]
    XCTAssertTrue(
        settings.waitForExistence(timeout: 15),
        "no Settings row on the Languages screen. Hierarchy:\n\(app.debugDescription)")
    settings.tap()

    XCTAssertTrue(
        app.navigationBars["Settings"].waitForExistence(timeout: 10),
        "tapping Settings did not push the Settings screen. Hierarchy:\n\(app.debugDescription)")
}
```

- [ ] **Step 2: Run it and confirm it fails for the right reason**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:'FullDeckUITests/FullDeckUITests/testFR16SettingsIsReachableFromLanguages'
```

Expected: FAIL on the first assertion — "no Settings row on the Languages screen". If it fails to *compile*, that is not a red; fix and re-run.

- [ ] **Step 3: Create `SettingsViewModel` with the cap preference only**

`FullDeck/FullDeck/ViewModels/SettingsViewModel.swift`:

```swift
import Domain
import Foundation
import Observation

/// Owns the two things the learner can change (FR-13 reminder, FR-4 new-word cap).
///
/// Separate from `CreditsViewModel` on purpose: credits is failable async pack
/// I/O, this is preferences. Folding them together would make every reminder
/// test set up packs and a manifest before reaching its assertion — the same
/// argument `PurchaseViewModel` makes for staying out of
/// `LanguageSelectionViewModel`.
@MainActor
@Observable
final class SettingsViewModel {
    static let newWordsPerDayKey = "newWordsPerDay"
    /// 1000 words at 30/day is a bit over a month; at 1/day it is most of three
    /// years. Both ends are defensible, and the Stepper clamps to them.
    static let capRange = 1...30

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.integer(forKey: Self.newWordsPerDayKey)
        // `integer(forKey:)` answers 0 for a key that was never written, which is
        // outside the range — so absent and "set to zero" are the same thing here,
        // and both mean "use the default".
        storedCap = stored == 0 ? SessionBuilder.defaultNewWordCap : Self.clamp(stored)
    }

    private var storedCap: Int

    /// FR-4. Clamped on write, so a hand-edited or stale defaults value cannot
    /// put the session builder outside its range.
    var newWordsPerDay: Int {
        get { storedCap }
        set {
            storedCap = Self.clamp(newValue)
            defaults.set(storedCap, forKey: Self.newWordsPerDayKey)
        }
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, capRange.lowerBound), capRange.upperBound)
    }
}
```

- [ ] **Step 4: Create `SettingsView` with an empty Form**

`FullDeck/FullDeck/Views/SettingsView.swift`:

```swift
import SwiftUI

/// Reached from a row on the Languages screen, inside the NavigationStack that
/// already lives there. Not a fourth tab, and not a toolbar item: E-2 records
/// that iOS 26 renders toolbar text at a fixed size and the accessibility audit
/// fails it outright, which is why Restore is a row too.
struct SettingsView: View {
    /// `@Bindable`, not `let`: `@Observable` types need it to hand out the
    /// `$viewModel.property` bindings the controls below take.
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Settings")
    }
}
```

- [ ] **Step 5: Add the row to `LanguageSelectionView`**

Add the stored property beside the existing ones:

```swift
    let settingsViewModel: SettingsViewModel
```

Add the row, and put it in the `List` after `restoreRow`:

```swift
    /// A row rather than a toolbar item, for the reason in `SettingsView`'s
    /// comment — and beside Restore, which made the same call.
    private var settingsRow: some View {
        NavigationLink {
            SettingsView(viewModel: settingsViewModel)
        } label: {
            Text("Settings")
                .foregroundStyle(Color.textPrimary)
        }
        .listRowBackground(Color.appBackground)
    }
```

In `content`'s `.ready` branch, the `List` becomes:

```swift
            List {
                ForEach(options) { option in
                    languageRow(option)
                }
                restoreRow
                settingsRow
            }
```

- [ ] **Step 6: Own the ViewModel in `ContentView` and pass it down**

Add the `@State` property beside the others:

```swift
    @State private var settingsViewModel: SettingsViewModel
```

In `init`, after `_selectionViewModel`:

```swift
        _settingsViewModel = State(initialValue: SettingsViewModel())
```

Update the `LanguageSelectionView` construction in `body`:

```swift
            LanguageSelectionView(
                viewModel: selectionViewModel, purchases: dependencies.purchases,
                settingsViewModel: settingsViewModel
            )
```

- [ ] **Step 7: Run the UI test and confirm it passes**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:'FullDeckUITests/FullDeckUITests/testFR16SettingsIsReachableFromLanguages'
```

Expected: PASS.

- [ ] **Step 8: Run the gates**

```sh
swiftlint lint --strict
```

Expected: 0 violations.

- [ ] **Step 9: Commit**

```bash
git add FullDeck/FullDeck/ViewModels/SettingsViewModel.swift \
        FullDeck/FullDeck/Views/SettingsView.swift \
        FullDeck/FullDeck/Views/LanguageSelectionView.swift \
        FullDeck/FullDeck/ContentView.swift \
        FullDeck/FullDeckUITests/FullDeckUITests.swift
git commit -m "feat: add the Settings screen the app has never had

A NavigationLink row beside Restore Purchases, for the reason Restore is a
row: E-2 fails toolbar text in the accessibility audit on iOS 26. No fourth
tab, so TabView tag identity is untouched.

Empty for now. Three requirements land in it next, all of which have gone
unimplemented because there was nowhere to put them."
```

---

### Task 2: FR-16 credits — the licence blocker

**Files:**
- Create: `FullDeck/FullDeck/ViewModels/CreditsViewModel.swift`
- Create: `FullDeck/FullDeck/Views/CreditsSection.swift`
- Modify: `FullDeck/FullDeck/Views/SettingsView.swift`
- Modify: `FullDeck/FullDeck/ContentView.swift`
- Modify: `FullDeck/FullDeck/Views/LanguageSelectionView.swift`
- Test: `FullDeck/FullDeckTests/CreditsViewModelTests.swift`
- Test: `FullDeck/FullDeckUITests/FullDeckUITests.swift`

**Interfaces:**
- Consumes: `SettingsView(viewModel:)` from Task 1 — this task adds a `credits:` argument.
- Produces: `CreditsViewModel(packStore: PackStore)` with `state: CreditsViewModel.State` and `func load() async`; `Credit(sourceName:license:attribution:languages:)`.

- [ ] **Step 1: Write the first failing test**

`FullDeck/FullDeckTests/CreditsViewModelTests.swift`:

```swift
import Domain
import Foundation
import Testing

@testable import FullDeck

private let hindiDescriptor = PackDescriptor(
    languageCode: LanguageCode("hi"), displayName: "Hindi", filename: "hi.pack.json",
    unlockedByDefault: false)

private func pack(
    _ code: String, name: String, source: PackSource
) -> LanguagePack {
    LanguagePack(
        schemaVersion: 1, packVersion: "1.0.0", languageCode: LanguageCode(code),
        languageName: name, baseLanguage: "en", wordCount: 1, source: source,
        words: [entry("chat", rank: 1)])
}

private let wordfreq = PackSource(
    name: "wordfreq", license: "CC-BY-SA 4.0", attribution: "wordfreq contributors")

@Test("FR-16 credits list each bundled pack's source, licence and attribution")
@MainActor
func creditsListEachPacksAttribution() async {
    let store = InMemoryPackStore(
        descriptors: [frDescriptor()],
        packs: [LanguageCode("fr"): pack("fr", name: "Français", source: wordfreq)])
    let viewModel = CreditsViewModel(packStore: store)

    await viewModel.load()

    #expect(
        viewModel.state
            == .ready([
                Credit(
                    sourceName: "wordfreq", license: "CC-BY-SA 4.0",
                    attribution: "wordfreq contributors", languages: ["Français"])
            ]))
}
```

- [ ] **Step 2: Run it and confirm it fails for the right reason**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:'FullDeckTests/creditsListEachPacksAttribution()'
```

Expected: FAIL to build — `CreditsViewModel` does not exist. That is a compile error, not a red. Write the type in Step 3, then this test's failure (or pass) is meaningful.

- [ ] **Step 3: Write `CreditsViewModel`**

`FullDeck/FullDeck/ViewModels/CreditsViewModel.swift`:

```swift
import Domain
import Foundation
import Observation

/// One credit line: a source, its licence, and every bundled language that uses
/// it. Grouped rather than per-pack, so two wordfreq packs do not render the
/// same three lines twice.
struct Credit: Equatable, Identifiable {
    let sourceName: String
    let license: String
    let attribution: String
    let languages: [String]

    var id: String { "\(sourceName)|\(license)|\(attribution)" }
}

/// FR-16, the app half. The pack-metadata half has been enforced by
/// `PackValidator` since Phase 6, which is exactly what made this half easy to
/// miss for four phases (N-4).
///
/// Reads each pack's own `PackSource` rather than a hardcoded string, so
/// ADR-004 survives: a third pack from a different source shows up here with no
/// app code touched. wordfreq's data is CC-BY-SA 4.0, and this screen is the
/// licence condition, not a nicety.
@MainActor
@Observable
final class CreditsViewModel {
    enum State: Equatable {
        case loading
        case ready([Credit])
        case failed(String)
    }

    private(set) var state: State = .loading

    private let packStore: PackStore

    init(packStore: PackStore) {
        self.packStore = packStore
    }

    func load() async {
        state = .loading
        do {
            let descriptors = try await packStore.availablePacks()
            var loaded: [(name: String, source: PackSource)] = []
            for descriptor in descriptors {
                let pack = try await packStore.loadPack(descriptor.languageCode)
                loaded.append((pack.languageName, pack.source))
            }
            state = .ready(Self.grouped(loaded))
        } catch let error as PackLoadError {
            state = .failed(error.userMessage)
        } catch {
            state = .failed(String(localized: "Couldn't load the credits."))
        }
    }

    /// Groups by the whole source triple, preserving first-appearance order so
    /// the list is stable rather than dictionary-ordered.
    static func grouped(_ packs: [(name: String, source: PackSource)]) -> [Credit] {
        var order: [String] = []
        var byKey: [String: Credit] = [:]
        for pack in packs {
            let key = "\(pack.source.name)|\(pack.source.license)|\(pack.source.attribution)"
            if let existing = byKey[key] {
                byKey[key] = Credit(
                    sourceName: existing.sourceName, license: existing.license,
                    attribution: existing.attribution,
                    languages: existing.languages + [pack.name])
            } else {
                order.append(key)
                byKey[key] = Credit(
                    sourceName: pack.source.name, license: pack.source.license,
                    attribution: pack.source.attribution, languages: [pack.name])
            }
        }
        return order.compactMap { byKey[$0] }
    }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Write the grouping test, run it, confirm it fails**

Append to `CreditsViewModelTests.swift`:

```swift
@Test("FR-16 two packs from one source render one grouped credit")
@MainActor
func creditsGroupPacksSharingASource() async {
    let store = InMemoryPackStore(
        descriptors: [frDescriptor(), hindiDescriptor],
        packs: [
            LanguageCode("fr"): pack("fr", name: "Français", source: wordfreq),
            LanguageCode("hi"): pack("hi", name: "हिन्दी", source: wordfreq),
        ])
    let viewModel = CreditsViewModel(packStore: store)

    await viewModel.load()

    #expect(
        viewModel.state
            == .ready([
                Credit(
                    sourceName: "wordfreq", license: "CC-BY-SA 4.0",
                    attribution: "wordfreq contributors", languages: ["Français", "हिन्दी"])
            ]))
}
```

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:'FullDeckTests/creditsGroupPacksSharingASource()'
```

This one should PASS immediately — `grouped` was written to handle it. If it fails, the grouping is wrong; fix `grouped`, not the test.

- [ ] **Step 6: Write the failure test, run it, confirm it fails**

```swift
@Test("NFR-10 a pack that cannot load surfaces a message, not a crash")
@MainActor
func creditsReportAFailedLoad() async {
    let store = InMemoryPackStore(
        descriptors: [frDescriptor()],
        errorOverride: .fileNotFound(languageCode: LanguageCode("fr")))
    let viewModel = CreditsViewModel(packStore: store)

    await viewModel.load()

    guard case .failed(let message) = viewModel.state else {
        Issue.record("expected .failed, got \(viewModel.state)")
        return
    }
    #expect(!message.isEmpty)
}
```

Run it. Expected: PASS (the `catch let error as PackLoadError` branch already handles it). If it fails, the error mapping is wrong.

- [ ] **Step 7: Write `CreditsSection`**

`FullDeck/FullDeck/Views/CreditsSection.swift`:

```swift
import SwiftUI

/// Maps a licence string to its canonical text, when we recognise it.
///
/// `PackSource` carries no URL, so a link needs a literal — the one place this
/// feature could break ADR-004's "add a pack, not app code" rule. An
/// unrecognised licence degrades to text only rather than to a wrong link.
/// Text attribution alone satisfies CC-BY-SA; the URI is its "where reasonably
/// practicable" clause.
enum LicenseLink {
    static func url(for license: String) -> URL? {
        switch license {
        case "CC-BY-SA 4.0": URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")
        default: nil
        }
    }
}

/// FR-16. A section rather than a pushed screen: two packs at three lines each
/// fits, and burying a licence obligation one level deeper serves nobody.
struct CreditsSection: View {
    let viewModel: CreditsViewModel

    var body: some View {
        Section("Credits") {
            switch viewModel.state {
            case .loading:
                ProgressView()
            case .ready(let credits):
                ForEach(credits) { credit in
                    creditRow(credit)
                }
            case .failed(let message):
                Text(message)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .listRowBackground(Color.appBackground)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func creditRow(_ credit: Credit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(credit.languages.joined(separator: ", "))
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text("Word list from \(credit.sourceName). \(credit.attribution).")
                .foregroundStyle(Color.textPrimary)
            if let url = LicenseLink.url(for: credit.license) {
                Link(credit.license, destination: url)
            } else {
                Text(credit.license)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        // One row per credit to VoiceOver, rather than three unrelated
        // fragments the learner has to stitch together.
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 8: Put the section in `SettingsView`**

Add the property and the section:

```swift
struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    let credits: CreditsViewModel

    var body: some View {
        Form {
            CreditsSection(viewModel: credits)
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Settings")
    }
}
```

Update `LanguageSelectionView`: add `let creditsViewModel: CreditsViewModel` beside `settingsViewModel`, and pass it in `settingsRow`:

```swift
            SettingsView(viewModel: settingsViewModel, credits: creditsViewModel)
```

Update `ContentView`: add `@State private var creditsViewModel: CreditsViewModel`, initialize it in `init` with `_creditsViewModel = State(initialValue: CreditsViewModel(packStore: dependencies.packStore))`, and pass `creditsViewModel: creditsViewModel` to `LanguageSelectionView`.

- [ ] **Step 9: Extend the reachability UI test to assert attribution is on screen**

In `testFR16SettingsIsReachableFromLanguages`, after the navigation-bar assertion:

```swift
    // The licence condition itself: the attribution has to be *visible*, not
    // merely present in a pack file.
    let attribution = app.staticTexts.containing(
        NSPredicate(format: "label CONTAINS %@", "wordfreq")
    ).firstMatch
    XCTAssertTrue(
        attribution.waitForExistence(timeout: 10),
        "no wordfreq attribution on the Settings screen. Hierarchy:\n\(app.debugDescription)")
```

- [ ] **Step 10: Run the whole unit bundle and the UI test**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckTests
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:'FullDeckUITests/FullDeckUITests/testFR16SettingsIsReachableFromLanguages'
```

Expected: both PASS.

- [ ] **Step 11: Run the gates**

```sh
swiftlint lint --strict
scripts/determinism-check.sh
scripts/trace-requirements.sh
```

Expected: 0 violations; determinism silent; FR-16 no longer flagged pipeline-only.

- [ ] **Step 12: Commit**

```bash
git add FullDeck/FullDeck/ViewModels/CreditsViewModel.swift \
        FullDeck/FullDeck/Views/CreditsSection.swift \
        FullDeck/FullDeck/Views/SettingsView.swift \
        FullDeck/FullDeck/Views/LanguageSelectionView.swift \
        FullDeck/FullDeck/ContentView.swift \
        FullDeck/FullDeckTests/CreditsViewModelTests.swift \
        FullDeck/FullDeckUITests/FullDeckUITests.swift
git commit -m "feat: show the wordfreq attribution the licence requires (FR-16)

Closes N-4, the one item on known-issues.md that stopped a release. The
pack-metadata half has been enforced by PackValidator since Phase 6; the app
half never existed, and the traceability report called FR-16 covered because
two pipeline tests name it.

Credits read each pack's own PackSource rather than a hardcoded string, so a
third pack from a different source appears here with no app code touched.
The licence hyperlinks only when the string is recognised and degrades to
text otherwise -- text attribution alone satisfies CC-BY-SA."
```

---

### Task 3: FR-4 — make the new-word cap adjustable

**Files:**
- Modify: `FullDeck/FullDeck/Views/SettingsView.swift`
- Modify: `FullDeck/FullDeck/ViewModels/StudyViewModel.swift:46,68,77`
- Modify: `FullDeck/FullDeck/ContentView.swift`
- Modify: `docs/requirements.md`
- Test: `FullDeck/FullDeckTests/SettingsViewModelTests.swift`

**Interfaces:**
- Consumes: `SettingsViewModel.newWordsPerDay`, `SettingsViewModel.capRange`, `SettingsViewModel.newWordsPerDayKey` from Task 1.
- Produces: `StudyViewModel.newWordCap` as a settable `var`.

- [ ] **Step 1: Write the failing default/persistence test**

`FullDeck/FullDeckTests/SettingsViewModelTests.swift`:

```swift
import Domain
import Foundation
import Testing

@testable import FullDeck

/// A throwaway suite per call, so no test reads or writes the simulator's real
/// defaults or leaks a preference into a sibling test.
private func emptyDefaults() -> UserDefaults {
    UserDefaults(suiteName: "com.fulldeck.tests.settings.\(UUID().uuidString)")!
}

@Test("FR-4 the new-word cap defaults to 10 and persists")
@MainActor
func capDefaultsAndPersists() {
    let defaults = emptyDefaults()
    let viewModel = SettingsViewModel(defaults: defaults)
    #expect(viewModel.newWordsPerDay == 10)

    viewModel.newWordsPerDay = 25

    // A fresh ViewModel over the same defaults is what a relaunch looks like.
    #expect(SettingsViewModel(defaults: defaults).newWordsPerDay == 25)
}
```

- [ ] **Step 2: Run it and confirm it passes**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:'FullDeckTests/capDefaultsAndPersists()'
```

Expected: PASS — Task 1 built this. If it fails, the defaults handling in `SettingsViewModel.init` is wrong.

- [ ] **Step 3: Write the failing clamp test**

```swift
@Test("FR-4 the new-word cap clamps to its range")
@MainActor
func capClampsToItsRange() {
    let viewModel = SettingsViewModel(defaults: emptyDefaults())

    viewModel.newWordsPerDay = 999
    #expect(viewModel.newWordsPerDay == SettingsViewModel.capRange.upperBound)

    viewModel.newWordsPerDay = -5
    #expect(viewModel.newWordsPerDay == SettingsViewModel.capRange.lowerBound)
}
```

Run it. Expected: PASS.

- [ ] **Step 4: Make `StudyViewModel.newWordCap` settable**

In `FullDeck/FullDeck/ViewModels/StudyViewModel.swift`, change line 46:

```swift
    /// FR-4. A `var` so a settings change reaches an in-flight session's *next*
    /// build without rebuilding the ViewModel — rebuilding would discard the
    /// learner's place in the deck. `start()` reads it when assembling a queue,
    /// so a change takes effect from the next session, never mid-deck.
    var newWordCap: Int
```

The `init` and its assignment are unchanged.

- [ ] **Step 5: Add the Stepper to `SettingsView`**

Add above `CreditsSection`:

```swift
            Section("Study") {
                Stepper(value: $viewModel.newWordsPerDay, in: SettingsViewModel.capRange) {
                    Text("New words per day: \(viewModel.newWordsPerDay)")
                        .foregroundStyle(Color.textPrimary)
                }
            }
            .listRowBackground(Color.appBackground)
```

- [ ] **Step 6: Push the cap into `StudyViewModel` from `ContentView`**

In `makeViewModels(for:)`, pass the current value at construction:

```swift
        studyViewModel = StudyViewModel(
            languageCode: language, packStore: dependencies.packStore,
            reviewStore: dependencies.reviewStore,
            scheduler: dependencies.scheduler,
            sessionBuilder: dependencies.sessionBuilder,
            speech: dependencies.speech, clock: dependencies.clock,
            newWordCap: settingsViewModel.newWordsPerDay)
```

And in `body`, after the existing `.task(id:)`:

```swift
        // Assign rather than rebuild. `.task(id:)` above rebuilds StudyViewModel
        // when the language changes, and doing that for a cap edit would throw
        // away whatever session the learner is in the middle of.
        .onChange(of: settingsViewModel.newWordsPerDay) { _, cap in
            studyViewModel?.newWordCap = cap
        }
```

- [ ] **Step 7: Amend FR-4 in `docs/requirements.md`**

Replace the last sentence of FR-4's **Acceptance** line:

```
Changing `N` in settings takes effect for the next day's introductions.
```

with:

```
Changing `N` takes effect from the next session; words already introduced today are never retracted.
```

Add immediately below the FR-4 acceptance line:

```
> **Amended 2026-08-02** (spec `2026-08-02-settings-and-about-design.md`,
> Decision 7). Was "takes effect for the next day's introductions". Honouring
> that literally needs a pending/active cap pair with an effective-from date,
> to deliver worse behaviour: a learner who lowers the cap because today is too
> much wants relief today. Consequence: lowering below what has already been
> introduced today yields zero further new words today, since
> `max(0, cap - introducedToday)` clamps at zero. Due reviews are never capped.
```

- [ ] **Step 8: Run the full unit bundle**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckTests
```

Expected: PASS, including the existing `StudyViewModel` tests — the `let`→`var` change must not disturb them.

- [ ] **Step 9: Run the gates**

```sh
swiftlint lint --strict
scripts/determinism-check.sh
```

- [ ] **Step 10: Commit**

```bash
git add FullDeck/FullDeck/Views/SettingsView.swift \
        FullDeck/FullDeck/ViewModels/StudyViewModel.swift \
        FullDeck/FullDeck/ContentView.swift \
        FullDeck/FullDeckTests/SettingsViewModelTests.swift \
        docs/requirements.md
git commit -m "feat: make the new-word cap adjustable, and amend FR-4 to match

FR-4 has said N is user-adjustable since Phase 1. SessionBuilder and
StudyViewModel both accept newWordCap, but ContentView never passed one, so
it has always been 10 with no way to change it. The cap-enforcement clause
is well tested; the adjustability clause had no implementation -- the same
multi-clause blind spot that hid FR-16's missing half.

FR-4's acceptance is amended from 'next day' to 'next session'. Honouring
'next day' literally needs a pending/active cap pair with an effective-from
date, to deliver worse behaviour: someone who lowers the cap because today
is too much wants relief today.

ContentView assigns the cap rather than rebuilding StudyViewModel, which
would discard the learner's place in the deck."
```

---

### Task 4: FR-13 — the reminder state machine, against a fake

No UI and no real notification centre in this task. The whole state machine becomes testable in milliseconds first; the framework glue follows in Task 5.

**Files:**
- Create: `FullDeck/FullDeck/Services/NotificationScheduler.swift`
- Modify: `FullDeck/FullDeck/ViewModels/SettingsViewModel.swift`
- Modify: `FullDeck/FullDeckTests/Fakes.swift`
- Test: `FullDeck/FullDeckTests/SettingsViewModelTests.swift`

**Interfaces:**
- Consumes: `SettingsViewModel` from Task 1.
- Produces: `NotificationScheduler` protocol; `ReminderAuthorization`; `NoNotificationScheduler`; `SettingsViewModel(defaults:notifications:)` with `isReminderOn`, `reminderHour`, `reminderMinute`, `permissionNote`, `func refreshAuthorization() async`, `func setReminder(on:) async`, `func setReminderTime(hour:minute:) async`.

- [ ] **Step 1: Write the port**

`FullDeck/FullDeck/Services/NotificationScheduler.swift`:

```swift
import Foundation

/// What iOS will currently allow. `.provisional` and `.ephemeral` collapse into
/// `.authorized` because a reminder can be delivered under both, and the
/// distinction is not one the learner can act on.
enum ReminderAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

/// FR-13's platform seam, owned by Presentation for the same reason
/// `PurchaseService` is: Domain's questions are about words and review
/// scheduling, and a daily notification is neither.
///
/// `authorizationStatus()` does not throw — reading `UNNotificationSettings`
/// cannot fail. The other two can.
nonisolated protocol NotificationScheduler: Sendable {
    func authorizationStatus() async -> ReminderAuthorization
    func requestAuthorization() async throws -> ReminderAuthorization
    func scheduleDailyReminder(hour: Int, minute: Int) async throws
    func cancelDailyReminder() async
}

/// The composition root's default, so `AppDependencies.make()` on its own never
/// reaches the notification centre — the rule `NoPurchasesService` set for
/// StoreKit. Integration tests and previews get this one.
struct NoNotificationScheduler: NotificationScheduler {
    func authorizationStatus() async -> ReminderAuthorization { .notDetermined }
    func requestAuthorization() async throws -> ReminderAuthorization { .denied }
    func scheduleDailyReminder(hour: Int, minute: Int) async throws {}
    func cancelDailyReminder() async {}
}
```

- [ ] **Step 2: Write the fake**

Append to `FullDeck/FullDeckTests/Fakes.swift`:

```swift
/// Records what was asked of iOS and returns whatever the test set up. Same
/// shape and same `@unchecked Sendable` justification as `FakePurchaseService`:
/// mutated only from the main actor inside tests.
final class FakeNotificationScheduler: NotificationScheduler, @unchecked Sendable {
    var statusToReturn: ReminderAuthorization = .notDetermined
    /// What the system prompt will answer. Granting also updates
    /// `statusToReturn`, because iOS does.
    var promptResult: ReminderAuthorization = .authorized
    var requestError: Error?
    var scheduleError: Error?

    private(set) var promptCount = 0
    private(set) var scheduled: [(hour: Int, minute: Int)] = []
    private(set) var cancelCount = 0

    func authorizationStatus() async -> ReminderAuthorization { statusToReturn }

    func requestAuthorization() async throws -> ReminderAuthorization {
        promptCount += 1
        if let requestError { throw requestError }
        statusToReturn = promptResult
        return promptResult
    }

    func scheduleDailyReminder(hour: Int, minute: Int) async throws {
        if let scheduleError { throw scheduleError }
        scheduled.append((hour, minute))
    }

    func cancelDailyReminder() async { cancelCount += 1 }
}
```

- [ ] **Step 3: Write the first failing reminder test**

Append to `SettingsViewModelTests.swift`:

```swift
@MainActor
private func makeSettingsViewModel(
    notifications: FakeNotificationScheduler = FakeNotificationScheduler(),
    defaults: UserDefaults = emptyDefaults()
) -> SettingsViewModel {
    SettingsViewModel(defaults: defaults, notifications: notifications)
}

@Test("FR-13 reminders are off by default")
@MainActor
func reminderIsOffByDefault() {
    #expect(!makeSettingsViewModel().isReminderOn)
}
```

- [ ] **Step 4: Run it, confirm the failure is a missing behaviour**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:'FullDeckTests/reminderIsOffByDefault()'
```

Expected: build failure — `SettingsViewModel` has no `notifications:` argument and no `isReminderOn`. Compile errors are not reds; add the members in Step 5 and re-run.

- [ ] **Step 5: Add the reminder state to `SettingsViewModel`**

Add the keys and defaults beside the existing statics:

```swift
    static let reminderOnKey = "reminderEnabled"
    static let reminderHourKey = "reminderHour"
    static let reminderMinuteKey = "reminderMinute"
    /// A picker position, never a scheduled notification — nothing is scheduled
    /// until the learner turns the toggle on.
    static let defaultReminderHour = 20
    static let defaultReminderMinute = 0
```

Add the stored state:

```swift
    private(set) var isReminderOn = false
    private(set) var reminderHour: Int
    private(set) var reminderMinute: Int
    /// Non-nil only when iOS will not deliver the reminder. Separate from a
    /// scheduling failure on purpose: collapsing the two would repeat D-4.
    private(set) var permissionNote: String?

    private let notifications: NotificationScheduler
```

Replace the initializer:

```swift
    init(
        defaults: UserDefaults = .standard,
        notifications: NotificationScheduler = NoNotificationScheduler()
    ) {
        self.defaults = defaults
        self.notifications = notifications
        let stored = defaults.integer(forKey: Self.newWordsPerDayKey)
        storedCap = stored == 0 ? SessionBuilder.defaultNewWordCap : Self.clamp(stored)
        isReminderOn = defaults.bool(forKey: Self.reminderOnKey)
        reminderHour =
            defaults.object(forKey: Self.reminderHourKey) as? Int ?? Self.defaultReminderHour
        reminderMinute =
            defaults.object(forKey: Self.reminderMinuteKey) as? Int ?? Self.defaultReminderMinute
    }
```

`object(forKey:) as? Int` rather than `integer(forKey:)`, because midnight is hour 0 and `integer` cannot tell that from an absent key.

- [ ] **Step 6: Run the test and confirm it passes**

Expected: PASS.

- [ ] **Step 7: Write the enable-and-schedule test, run it, confirm it fails**

```swift
@Test("FR-13 enabling requests permission and schedules exactly one reminder")
@MainActor
func enablingSchedulesOneReminder() async {
    let notifications = FakeNotificationScheduler()
    notifications.promptResult = .authorized
    let viewModel = makeSettingsViewModel(notifications: notifications)

    await viewModel.setReminder(on: true)

    #expect(viewModel.isReminderOn)
    #expect(viewModel.permissionNote == nil)
    #expect(notifications.promptCount == 1)
    #expect(notifications.scheduled.count == 1)
    #expect(notifications.scheduled.first?.hour == SettingsViewModel.defaultReminderHour)
}
```

Expected: build failure — `setReminder(on:)` does not exist.

- [ ] **Step 8: Implement `setReminder(on:)` and the rest of the machine**

```swift
    /// FR-13. Reconciles the learner's intent against what iOS will actually
    /// allow, so the toggle is on only when a notification will really fire.
    func setReminder(on isOn: Bool) async {
        permissionNote = nil
        guard isOn else {
            await notifications.cancelDailyReminder()
            isReminderOn = false
            defaults.set(false, forKey: Self.reminderOnKey)
            return
        }

        var status = await notifications.authorizationStatus()
        if status == .notDetermined {
            do {
                status = try await notifications.requestAuthorization()
            } catch {
                isReminderOn = false
                permissionNote = String(localized: "Couldn't turn on reminders. Try again.")
                return
            }
        }
        // iOS prompts once per install; asking again after a denial silently
        // returns denied, so a UI that keeps asking is a UI that looks broken.
        guard status == .authorized else {
            isReminderOn = false
            defaults.set(false, forKey: Self.reminderOnKey)
            permissionNote = String(
                localized: "Notifications are turned off for Full Deck in Settings.")
            return
        }

        await schedule()
    }

    /// FR-13. Changing the time while the reminder is on replaces it rather
    /// than adding a second — the identifier does that in the adapter, and the
    /// explicit cancel makes the intent testable.
    func setReminderTime(hour: Int, minute: Int) async {
        reminderHour = hour
        reminderMinute = minute
        defaults.set(hour, forKey: Self.reminderHourKey)
        defaults.set(minute, forKey: Self.reminderMinuteKey)
        guard isReminderOn else { return }
        await notifications.cancelDailyReminder()
        await schedule()
    }

    /// Called when the screen appears. Permission can be revoked in iOS
    /// Settings between visits, and a toggle still showing "on" would be a
    /// promise the app cannot keep.
    func refreshAuthorization() async {
        guard isReminderOn else { return }
        guard await notifications.authorizationStatus() != .authorized else { return }
        await notifications.cancelDailyReminder()
        isReminderOn = false
        defaults.set(false, forKey: Self.reminderOnKey)
        permissionNote = String(
            localized: "Notifications are turned off for Full Deck in Settings.")
    }

    private func schedule() async {
        do {
            try await notifications.scheduleDailyReminder(
                hour: reminderHour, minute: reminderMinute)
            isReminderOn = true
            defaults.set(true, forKey: Self.reminderOnKey)
        } catch {
            isReminderOn = false
            defaults.set(false, forKey: Self.reminderOnKey)
            permissionNote = String(localized: "Couldn't set the reminder. Try again.")
        }
    }
```

- [ ] **Step 9: Run the test and confirm it passes**

Expected: PASS.

- [ ] **Step 10: Write the remaining six tests**

Append all six, run the file, and fix implementation — not tests — for any red:

```swift
@Test("FR-13 a denied prompt reverts the toggle and explains")
@MainActor
func deniedPromptRevertsTheToggle() async {
    let notifications = FakeNotificationScheduler()
    notifications.promptResult = .denied
    let viewModel = makeSettingsViewModel(notifications: notifications)

    await viewModel.setReminder(on: true)

    #expect(!viewModel.isReminderOn)
    #expect(viewModel.permissionNote != nil)
    #expect(notifications.scheduled.isEmpty)
}

@Test("FR-13 enabling when already denied does not prompt again")
@MainActor
func alreadyDeniedDoesNotPromptAgain() async {
    let notifications = FakeNotificationScheduler()
    notifications.statusToReturn = .denied
    let viewModel = makeSettingsViewModel(notifications: notifications)

    await viewModel.setReminder(on: true)

    #expect(notifications.promptCount == 0)
    #expect(!viewModel.isReminderOn)
    #expect(viewModel.permissionNote != nil)
}

@Test("FR-13 disabling cancels the scheduled reminder")
@MainActor
func disablingCancels() async {
    let notifications = FakeNotificationScheduler()
    let viewModel = makeSettingsViewModel(notifications: notifications)
    await viewModel.setReminder(on: true)

    await viewModel.setReminder(on: false)

    #expect(!viewModel.isReminderOn)
    #expect(notifications.cancelCount == 1)
}

@Test("FR-13 changing the time reschedules rather than adding a second")
@MainActor
func changingTimeReschedules() async {
    let notifications = FakeNotificationScheduler()
    let viewModel = makeSettingsViewModel(notifications: notifications)
    await viewModel.setReminder(on: true)

    await viewModel.setReminderTime(hour: 7, minute: 30)

    #expect(notifications.cancelCount == 1)
    #expect(notifications.scheduled.count == 2)
    #expect(notifications.scheduled.last?.hour == 7)
    #expect(notifications.scheduled.last?.minute == 30)
}

@Test("FR-13 permission revoked outside the app turns the toggle off on next appearance")
@MainActor
func revokedPermissionReconcilesOnAppearance() async {
    let notifications = FakeNotificationScheduler()
    let viewModel = makeSettingsViewModel(notifications: notifications)
    await viewModel.setReminder(on: true)
    #expect(viewModel.isReminderOn)

    // The learner turns notifications off in iOS Settings and comes back.
    notifications.statusToReturn = .denied
    await viewModel.refreshAuthorization()

    #expect(!viewModel.isReminderOn)
    #expect(viewModel.permissionNote != nil)
    #expect(notifications.cancelCount == 1)
}

@Test("NFR-10 a scheduling failure surfaces as a message, not a crash")
@MainActor
func schedulingFailureIsReported() async {
    let notifications = FakeNotificationScheduler()
    notifications.scheduleError = FakeStoreError()
    let viewModel = makeSettingsViewModel(notifications: notifications)

    await viewModel.setReminder(on: true)

    #expect(!viewModel.isReminderOn)
    #expect(viewModel.permissionNote != nil)
}
```

- [ ] **Step 11: Run the whole unit bundle**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckTests
```

Expected: PASS.

- [ ] **Step 12: Run the gates and commit**

```sh
swiftlint lint --strict
scripts/determinism-check.sh
```

```bash
git add FullDeck/FullDeck/Services/NotificationScheduler.swift \
        FullDeck/FullDeck/ViewModels/SettingsViewModel.swift \
        FullDeck/FullDeckTests/Fakes.swift \
        FullDeck/FullDeckTests/SettingsViewModelTests.swift
git commit -m "feat: the daily reminder state machine, testable without a device (FR-13)

A Presentation-owned NotificationScheduler port, for the reason
PurchaseService is one: Domain's questions are about words and review
scheduling, and a notification is neither. Eight behaviours covered against
a fake in milliseconds -- no simulator, no permission prompt.

The two off-states stay distinct. Denied gets an explanation the learner can
act on; a scheduling failure gets a retryable message. Collapsing them would
repeat D-4, where 'product not found' and 'store unreachable' became one
string and left the setup work nothing to diagnose with."
```

---

### Task 5: FR-13 — the adapter and the UI

**Files:**
- Create: `FullDeck/FullDeck/Services/UNNotificationScheduler.swift`
- Modify: `FullDeck/FullDeck/Views/SettingsView.swift`
- Modify: `FullDeck/FullDeck/AppDependencies.swift`
- Modify: `FullDeck/FullDeck/ContentView.swift`

**Interfaces:**
- Consumes: everything from Task 4.
- Produces: `UNNotificationScheduler()`; `AppDependencies.notifications`.

- [ ] **Step 1: Write the adapter**

`FullDeck/FullDeck/Services/UNNotificationScheduler.swift`:

```swift
import Foundation
import UserNotifications

/// The **only** file in the app that imports `UserNotifications` — the same
/// containment rule `StoreKitPurchaseService` follows for StoreKit.
///
/// Deliberately untested: every method is a direct passthrough, and a unit test
/// here would assert that Apple's framework was called, which is not a fact
/// about this app. The XCUITest and a manual device check are the honest
/// coverage. Recorded as such in known-issues.md rather than claimed otherwise.
nonisolated struct UNNotificationScheduler: NotificationScheduler {
    /// One constant identifier is what makes "exactly one reminder" (FR-13)
    /// true without bookkeeping: adding a request with an existing identifier
    /// replaces it.
    static let reminderIdentifier = "arjunpathak.FullDeck.dailyReminder"

    func authorizationStatus() async -> ReminderAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized, .provisional, .ephemeral: return .authorized
        default: return .denied
        }
    }

    func requestAuthorization() async throws -> ReminderAuthorization {
        let granted = try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        return granted ? .authorized : .denied
    }

    func scheduleDailyReminder(hour: Int, minute: Int) async throws {
        let content = UNMutableNotificationContent()
        // Title only. A repeating local notification cannot know the due count
        // at fire time without background refresh (out of scope, §4), so any
        // body promising ready cards is false on the days there are none.
        content.title = String(localized: "Time to study")
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let request = UNNotificationRequest(
            identifier: Self.reminderIdentifier, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
        try await UNUserNotificationCenter.current().add(request)
    }

    func cancelDailyReminder() async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])
    }
}
```

- [ ] **Step 2: Wire it into `AppDependencies`**

Add the property:

```swift
    let notifications: NotificationScheduler
```

Add the parameter to `make(...)`, defaulting to the stub so integration tests never reach the notification centre:

```swift
    static func make(
        packsDirectory: URL, inMemory: Bool,
        entitlements: EntitlementStore = NoPurchasesEntitlementStore(),
        purchases: PurchaseService = NoPurchasesService(),
        notifications: NotificationScheduler = NoNotificationScheduler()
    ) throws -> AppDependencies {
```

Pass it in the `AppDependencies(...)` construction inside `make`, add `notifications: NoNotificationScheduler()` to the `allWordsLearnedFixture()` construction, and in `live()` pass the real one:

```swift
        return try make(
            packsDirectory: bundledPacksDirectory, inMemory: false,
            entitlements: store, purchases: store,
            notifications: UNNotificationScheduler())
```

- [ ] **Step 3: Give `SettingsViewModel` the real scheduler in `ContentView`**

```swift
        _settingsViewModel = State(
            initialValue: SettingsViewModel(notifications: dependencies.notifications))
```

- [ ] **Step 4: Add the reminder section to `SettingsView`**

Above the `Study` section:

```swift
            Section("Reminder") {
                // A computed Binding, not `$viewModel.isReminderOn`: the property
                // is private(set) because turning it on is an async negotiation
                // with iOS that can end in "no", not a value the view may assign.
                Toggle(
                    "Daily reminder",
                    isOn: Binding(
                        get: { viewModel.isReminderOn },
                        set: { on in Task { await viewModel.setReminder(on: on) } }))
                if viewModel.isReminderOn {
                    DatePicker(
                        "Time",
                        selection: Binding(
                            get: { viewModel.reminderDate },
                            set: { date in
                                Task { await viewModel.setReminderTime(from: date) }
                            }),
                        displayedComponents: .hourAndMinute)
                }
                if let note = viewModel.permissionNote {
                    Text(note)
                        .foregroundStyle(Color.textSecondary)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: url)
                    }
                }
            }
            .listRowBackground(Color.appBackground)
```

Add `.task { await viewModel.refreshAuthorization() }` to the `Form`, so a permission revoked in iOS Settings reconciles on every appearance.

- [ ] **Step 5: Add the two `Date` conversions to `SettingsViewModel`**

The ViewModel stores hour/minute so no test needs a clock; `DatePicker` speaks `Date`, and this is the only place the two meet:

```swift
    /// `DatePicker` binds to a `Date`, while this type stores hour/minute so no
    /// test ever needs the wall clock (`scripts/determinism-check.sh`). The day
    /// is arbitrary and never read — only the time components are.
    var reminderDate: Date {
        Calendar.current.date(
            from: DateComponents(
                year: 2000, month: 1, day: 1, hour: reminderHour, minute: reminderMinute))
            ?? Date(timeIntervalSince1970: 0)
    }

    func setReminderTime(from date: Date) async {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        await setReminderTime(
            hour: components.hour ?? reminderHour, minute: components.minute ?? reminderMinute)
    }
```

`SettingsView.swift` needs `import UIKit` for `openSettingsURLString`.

- [ ] **Step 6: Build and run the full unit bundle**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FullDeckTests
```

Expected: PASS, with no change to Task 4's tests — the adapter is not in their path.

- [ ] **Step 7: Verify by hand on a simulator**

```sh
xcodebuild build -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Launch, go Languages → Settings, and check: toggling on prompts for permission; granting reveals the time picker; the notification arrives at the chosen time; turning notifications off in iOS Settings and returning turns the toggle off with an explanation.

**Use a fresh simulator** (`xcrun simctl erase`) if the permission prompt has already been answered — iOS prompts once per install, and a stale answer makes the flow look broken.

- [ ] **Step 8: Run the gates and commit**

```sh
swiftlint lint --strict
scripts/determinism-check.sh
```

```bash
git add FullDeck/FullDeck/Services/UNNotificationScheduler.swift \
        FullDeck/FullDeck/Views/SettingsView.swift \
        FullDeck/FullDeck/AppDependencies.swift \
        FullDeck/FullDeck/ContentView.swift
git commit -m "feat: wire the daily reminder to iOS (FR-13)

UNNotificationScheduler is the only file importing UserNotifications, the
same containment rule StoreKit gets. One constant identifier is what makes
'exactly one reminder' true without bookkeeping -- adding a request with an
existing identifier replaces it.

Title only, no body: a repeating local notification cannot know the due
count at fire time without background refresh, which §4 puts out of scope,
so any body promising ready cards is false on the days there are none.

AppDependencies.make() still defaults to the no-op stub, so integration
tests never reach the notification centre."
```

---

### Task 6: Accessibility audit and documentation

**Files:**
- Modify: `FullDeck/FullDeckUITests/FullDeckUITests.swift:148`
- Modify: `docs/known-issues.md`
- Modify: `docs/next-task.md`

**Interfaces:**
- Consumes: everything above.
- Produces: nothing.

- [ ] **Step 1: Add `SettingsView` to the audit's core screens**

In `testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens`, after the first `try performAudit(on: app)`:

```swift
        // Settings — a whole screen the audit had never seen, carrying a
        // Stepper, a Toggle, a DatePicker and a Link, none of which any other
        // screen uses.
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        try performAudit(on: app)
        app.navigationBars["Settings"].buttons.firstMatch.tap()
```

- [ ] **Step 2: Run the audit and fix what it reports**

```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:'FullDeckUITests/FullDeckUITests/testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens'
```

Expected: PASS. If contrast fails on a control, fix the colour — do not filter the audit. If a `Link` fails Dynamic Type, that is a genuine finding and belongs in `known-issues.md` under **E**, since it would be Apple's control, not ours.

- [ ] **Step 3: Update `docs/known-issues.md`**

- Mark **N-1** (FR-13) and **N-4** (FR-16) as FIXED 2026-08-02, keeping the entries with what they taught.
- Under **N**, add the FR-4 finding: the adjustability clause had no implementation, it was found by reading the acceptance criterion against the code, and no layer heuristic catches that shape.
- Update the page's opening summary — "the one that blocks shipping outright is N-4" is no longer true.
- Add to **C**: `UNNotificationScheduler` has no unit test, deliberately, with the reasoning from its doc comment.
- Note that **N-2** (FR-17) and **N-3** (FR-18) remain, and are part B.

- [ ] **Step 4: Update `docs/next-task.md`**

Replace the "Right now" block: part A is done, part B (FR-17, FR-18, `StatsService`) is next and needs its own spec via brainstorming. Keep the pointer to `known-issues.md`.

- [ ] **Step 5: Run every gate**

```sh
swift test --package-path Packages/Domain
swift test --package-path Packages/Data
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17'
swiftlint lint --strict
scripts/determinism-check.sh
scripts/trace-requirements.sh
```

Expected: all pass. Domain and Data must be untouched — if their tests changed behaviour, something in this plan went wrong.

- [ ] **Step 6: Commit**

```bash
git add FullDeck/FullDeckUITests/FullDeckUITests.swift docs/known-issues.md docs/next-task.md
git commit -m "docs: close N-1 and N-4, and record what FR-4 taught

The credits screen exists, so the licence blocker is gone and the app can
ship. The reminder exists, so the one notification CLAUDE.md permits is
real.

The finding worth keeping is FR-4's. Its adjustability clause had no
implementation while its cap-enforcement clause was well tested, and nothing
automated catches that -- not the traceability report, not the layer
heuristic. Only reading an acceptance criterion against the code does. That
is the second instance in two days, after FR-16.

N-2 and N-3 remain: the Progress screen work is part B."
```

---

## Self-Review

**Spec coverage.** Decision 1 (row container) → Task 1. Decision 2 (per-pack `PackSource`) and its licence-link map → Task 2. Decision 3 (section not sub-screen) → Task 2 Step 7. Decision 4 (the port, `NoNotificationScheduler`, `AppDependencies` wiring) → Tasks 4 and 5. Decision 5 (two ViewModels, the file list) → Tasks 1, 2, 4. Decision 6 (the state machine table, copy) → Tasks 4 and 5. Decision 7 (cap immediate, FR-4 amendment, reaching an in-flight session) → Task 3. Errors section → Task 4 Step 8. Testing section → all thirteen named tests plus the XCUITest, Tasks 2–4 and 6. No spec section is unassigned.

**Deviation, recorded rather than silent.** Decision 7 specified `@AppStorage` in `ContentView`; the plan observes `SettingsViewModel` directly instead. Reason in "File Structure" above — one source of truth, and `@AppStorage`'s `store:` cannot be injected by a unit test.

**Placeholders.** None. Every code step carries real code; no "add error handling", no "similar to Task N".

**Type consistency.** `SettingsViewModel` is constructed as `(defaults:)` in Task 1 and `(defaults:notifications:)` from Task 4 on — both spellings work because Task 4 adds a defaulted parameter, and Task 3's tests use the Task 1 spelling deliberately. `newWordsPerDay`, `capRange`, `newWordsPerDayKey`, `isReminderOn`, `reminderHour`, `reminderMinute`, `permissionNote`, `setReminder(on:)`, `setReminderTime(hour:minute:)`, `setReminderTime(from:)`, `refreshAuthorization()`, `reminderDate` are spelled identically everywhere they appear. `CreditsViewModel.State` and `Credit`'s four properties match between Task 2's tests and its implementation. `FakeNotificationScheduler`'s `statusToReturn`/`promptResult`/`promptCount`/`scheduled`/`cancelCount` match between the fake and all eight tests. `StudyViewModel.newWordCap` is the same name in Task 3 Steps 4 and 6.

**Known gap, deliberate.** `UNNotificationScheduler` has no automated test. Task 5 Step 7 is a manual check and Task 6 Step 3 records it in `known-issues.md` rather than letting it pass as covered.
