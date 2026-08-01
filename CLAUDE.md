# Project: Full Deck — Top 1000 Words

**Naming:** Decided 2026-07-24 (Phase 4). User-facing app name is **Full Deck**. The Xcode project, app target, and Swift module are `FullDeck` (no space — keeps generated identifiers clean); the display name "Full Deck" is set via the target's Display Name. Bundle id: `arjunpathak.FullDeck`.

## Product in one sentence
A SwiftUI iOS app that teaches the ~1000 highest-frequency words in a language using spaced repetition, and nothing else.

## Key project documents
- `docs/build-plan.md` — the 14-phase build plan. One phase per session; don't skip ahead.
- `docs/superpowers/specs/2026-07-06-top-1000-words-feasibility-design.md` — feasibility spec; decisions D1–D6 are settled, don't re-litigate them.
- `docs/claude-code-xcode-setup.md` — how Claude Code and Xcode work together here, including the build/test commands.

## Decisions already made (from the spec — treat as settled)
- **Word-list source:** the `wordfreq` Python package. Data is CC-BY-SA 4.0 — commercial use OK, attribution required in pack metadata and the app's credits. Leipzig Corpora is rejected (non-commercial).
- **Audio:** on-device TTS (`AVSpeechSynthesizer`) behind an injectable speech protocol. No bundled audio files in v1; the pack schema keeps an *optional* audio-reference field for future real recordings.
- **Example sentences:** LLM-generated in the Phase 6 pipeline (Claude API), with a programmatically enforced constraint: each sentence uses only words more frequent than its target word. Spot-checked by humans before beta.
- **Languages:** French is the free launch language; Hindi is the Phase 12 architecture-validation language.

## Design philosophy — read before writing any code
- Do one thing well. Every proposed feature is tested against: "does this help someone learn the 1000 words, or is it engagement/retention theater?" If the latter, flag it to me instead of building it.
- No gamification: no streaks, XP, leaderboards, mascots, confetti, or streak-guilt.
- No ads, no dark patterns, no infinite content treadmill.
- The app has a deliberate ending: when all 1000 words in a language are learned, say so clearly rather than inventing busywork.
- Visually clean and confident, not sterile. Reference points: Flighty, Streaks. Not Duolingo.

## Core learning mechanics — this IS the product
1. Spaced repetition (simplified SM-2-style scheduler). The highest-value component. Correctness here is non-negotiable.
2. Active recall over passive recognition: the user attempts to produce/select the answer before it's revealed.
3. One contextual example sentence per word — every card, always — built only from words the learner has already met (the frequency constraint above).

## Architecture constraints — hard rules
- Strict separation of layers: presentation (SwiftUI + ViewModels) → domain (pure Swift, no framework or persistence imports) → data (persistence + language packs). Dependencies point inward only: domain must not import UI or persistence.
- The spaced-repetition engine and all domain logic are pure Swift with zero dependencies on SwiftUI, Core Data, or the file system — so they're unit-testable in isolation.
- Each language is a self-contained, versioned data pack: frequency-ranked word list, part of speech, register tag, one example sentence per word, optional audio reference. Adding a language later must mean "add a data pack," never "write new app code." Flag any design choice that would break this.
- Speech/audio playback goes through a protocol so TTS can be swapped for bundled recordings later without touching callers.

## Monetization
- First language free. Each additional language: $0.99 one-time unlock (StoreKit non-consumable). No subscriptions, no ads.

## Engineering standards — apply throughout
- Test-first for all **logic** — anything expressible as input→output: the domain engine, the pack validator, ViewModels, the "learned"/done-state rule, the purchase state machine. Write the failing test first, then implement to pass. Don't write the scheduler without tests. **Framework glue** (SwiftData round-trips, end-to-end wiring, the accessibility audit) is tested *alongside* the implementation, not necessarily before it — an integration test is the honest test there. When unsure which side a piece falls on, treat it as logic.
- Every layer is testable in isolation via protocol boundaries and injected dependencies (dependency inversion). No singletons reaching into global state.
- Keep views thin: logic lives in ViewModels, not in SwiftUI view bodies.
- Handle errors explicitly with typed errors and real user-facing states — never crash on bad data or a missing file.
- Accessibility is a requirement, not a nice-to-have: VoiceOver labels and Dynamic Type support from the start.
- Conventional commits, small and focused. After each phase, do a self-review pass and tell me about any tech debt you're knowingly leaving.
- Don't use deprecated or soon-to-be-deprecated APIs. When unsure whether an API/library is still current best practice, check before committing to it and tell me what you found.

## Testing standards — apply throughout
These make the standards above *enforceable*, not just aspirational. They are gated in CI from Phase 4 on.
- **Red-green-refactor, one behavior at a time.** For each behavior: write one failing test → run it and confirm it fails *because the behavior is missing* (a compile error or typo is not a red — fix that and re-run until it fails for the right reason) → write the minimal code to green it → refactor while green. Not a batch of tests followed by a wall of code. This is what "test-first" means here; "wrote the tests first-ish" is not it.
- **Requirement traceability:** every test's display name starts with the requirement ID it verifies — `@Test("FR-8 failing grade resets the interval")`. `scripts/trace-requirements.sh` reports which FR-/NFR- IDs still have no test (report only, never blocks — many are untestable until their phase lands).
- **Coverage floors (hard CI fail):** Domain ≥ 90%, Data ≥ 80% line coverage. No floor on the app/UI targets — coverage % there is noise and invites tests written for the number.
- **Warnings are errors:** builds compile with `-warnings-as-errors` — CI passes `-Xswiftc -warnings-as-errors` to the packages, and the Xcode targets set `SWIFT_TREAT_WARNINGS_AS_ERRORS`. Note what this does *not* cover: the Domain and Data packages declare `swiftLanguageModes: [.v6]`, so the Swift 6 strict-concurrency model of `architecture.md` §4 is genuinely enforced there, but the app target still compiles in Swift 5 mode with the approachable-concurrency migration aids. Migrating it is deferred to its own follow-up phase, tracked separately from Phase 10's cross-cutting-concerns pass so each stays reviewable on its own. One deliberate carve-out, added in Phase 11: the `FullDeckTests` target passes `-Xcc -Wno-deprecated-declarations`, because Apple's own `StoreKitTest` header references `SKPaymentTransactionState`, which Apple deprecated in iOS 18. It silences deprecation from **C headers only**; `SWIFT_TREAT_WARNINGS_AS_ERRORS` stays on everywhere, and no Swift warning is suppressed.
- **Validators are tested for *rejection*, not just acceptance.** For every machine-checked rule (the pack VR-1…VR-18), there is a fixture that breaks exactly that rule, and the test asserts *which* rule fired. Fixtures live in `fixtures/invalid/` (`expected.json` maps each to its rule); `fixtures/fr-mini.pack.json` is the positive control. A validator that rejects nothing — or everything — must fail a test.
- **The scheduler is tested by invariant, not only by example.** Assert its properties over a long seeded random walk of (state, grade) steps: `next-review ≥ today` always, ease/interval stay within their clamps, a failing grade never lengthens an interval, and `(state, grade, today)` is pure. Example cases prove the cases; invariants catch drift and off-by-ones at clamps reached only after many reps.
- **Test determinism:** no test reads `Date()`, sleeps, or uses unseeded randomness. Domain injects `Clock`; use it. CI greps test sources for these. A flaky suite stops being believed.
- **A bug fix starts with a failing regression test** that reproduces it, then the fix — the same test-first discipline as new domain logic.

## Build & test commands
Run from the repo root. macOS + Xcode 26 (Swift 6 toolchain). CI (`.github/workflows/ci.yml`) runs the same gates.

**Domain / Data packages** — pure Swift, seconds, no simulator. Nearly all logic tests live here; run these constantly:
```sh
swift test --package-path Packages/Domain
swift test --package-path Packages/Data
```

**Coverage gates** — hard CI floors (Domain ≥ 90%, Data ≥ 80%). The gate script re-runs coverage export and fails below the floor:
```sh
swift test --package-path Packages/Domain --enable-code-coverage
scripts/coverage-gate.sh Packages/Domain 90 DomainPackageTests
swift test --package-path Packages/Data --enable-code-coverage
scripts/coverage-gate.sh Packages/Data 80 DataPackageTests
```

**Full app** — SwiftUI shell + XCUITest; needs a booted iOS simulator. Use any iPhone your Xcode has (CI auto-picks the newest on the runner):
```sh
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

**Lint & format** — SwiftLint `--strict` is the gated lint; `swift format` is a local convenience (not gated), config in `.swift-format`:
```sh
swiftlint lint --strict                                   # brew install swiftlint
swift format lint --strict --recursive Packages FullDeck  # add --in-place to fix
```

The two disagree, and **SwiftLint wins** — it is the gate. `swift format --in-place` puts the
opening brace of a multi-line `if` condition on its own line; SwiftLint's `opening_brace` rule
rejects exactly that. `LanguageSelectionViewModel.swift:55` is the one place this bites, and it
is left in SwiftLint's shape on purpose, so `swift format lint` reports one permanent error
there. Don't "fix" it — that reintroduces a gated violation. If a third site ever appears,
disable `opening_brace` in `.swiftlint.yml` rather than fighting it file by file.

**Content pipeline** (`pipeline/`, Python + uv — see `pipeline/README.md`). Its own CI job, on Linux:
```sh
uv sync --project pipeline
uv run --project pipeline pytest        # validator coverage floor is in pyproject addopts
# Pass the path explicitly. CI runs these with `working-directory: pipeline`, so its `.`
# means `pipeline/`; from the repo root a bare `.` walks docs/ too and ruff reformats the
# Python inside fenced code blocks in the plan documents — a failure CI never sees.
uv run --project pipeline ruff format --check pipeline && uv run --project pipeline ruff check pipeline
```

**Standalone gates** (also run in CI):
```sh
scripts/determinism-check.sh    # no Date()/sleep/unseeded-random in test sources
scripts/trace-requirements.sh   # FR-/NFR- coverage report — informational, never fails
```

## About me (the developer)
Strong Python and general SWE fundamentals; zero prior Swift/SwiftUI/Xcode experience. The first time you introduce a new Swift/SwiftUI/Xcode concept, briefly explain what it does and why — like explaining to someone fluent in other languages but new to this one. Don't re-explain concepts already established earlier in the project. Prefer incremental steps I can run and understand over large drops of code.

## Out of scope for v1 (do not build)
Grammar lessons, pronunciation scoring, social features, a backend/server, multiple example sentences per word, bundled audio recordings (v1 is on-device TTS), additional push notifications beyond one optional daily reminder.
