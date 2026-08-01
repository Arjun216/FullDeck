# Build Plan — "Top 1000 Words" App (14 phases)

Engineered build, systems-design first → thorough testing last. This is the sequenced prompt library for building the app through a disciplined SWE process: design front-loaded (requirements → architecture → data contracts), verification back-loaded (unit → integration → UI → QA → beta). Each phase produces a concrete artifact and is gated by tests before moving on.

> **Provenance:** This is the original prompt library with the amendments from
> `docs/superpowers/specs/2026-07-06-top-1000-words-feasibility-design.md` applied.
> Changes vs. the original: Step 0 is done (see `CLAUDE.md`); git is already initialized;
> Phase 3 makes audio optional and adds the sentence-frequency validation rule;
> Phase 6 names `wordfreq` as the settled source and adds LLM sentence generation;
> Phase 8 routes audio through a TTS speech protocol; Phase 13 adds the sentence
> spot-check and swaps the audio edge case; Phase 14 adds wordfreq attribution.

### How to use it
- Work inside this repo so Claude Code retains context across sessions (`CLAUDE.md` loads automatically).
- **One phase per session.** Read the output, run it, commit it, then move on. Don't paste multiple phases at once.
- Design phases (1–3) produce **documents, not code**. Resist the urge to skip them — they're what make the later phases fast and the codebase maintainable.
- Because tooling/APIs move fast, several prompts tell Claude Code to **verify current best practice before committing to a specific API or library version** rather than trusting its defaults. Keep that instruction in.
- Setup for the Claude Code + Xcode workflow itself: `docs/claude-code-xcode-setup.md`.

---

## Step 0 — Standing context file (`CLAUDE.md`) ✅ DONE

`CLAUDE.md` exists in the project root with the design philosophy, architecture constraints, engineering standards, and the settled spec decisions (D1–D6). Reread it if a phase seems to contradict it — CLAUDE.md and the spec win.

---

## PHASE 1 — Requirements Specification

*Artifact: `docs/requirements.md`. No code.*

```
We're starting a disciplined build. This phase is requirements only — produce a document, not code.

Write docs/requirements.md covering:
1. Functional requirements, each with a stable ID (FR-1, FR-2, …) and a testable acceptance criterion. Cover at minimum: language selection, the study/review session, active-recall interaction, spaced-repetition scheduling, progress tracking, the completion/"done" state, audio playback (on-device TTS per the spec), and the optional daily reminder, and purchasing an additional language.
2. Non-functional requirements (NFR-1, …): offline-first operation, performance targets (e.g. cold launch and card-advance latency), accessibility (VoiceOver + Dynamic Type), privacy (local-only data, no tracking), and supported iOS versions.
3. Explicit out-of-scope list for v1, drawn from CLAUDE.md.
4. Key user flows described as short step sequences (not diagrams yet): first launch, a study session, hitting the completion state, unlocking a second language.

Keep it concise and unambiguous — this is the contract the tests will verify against later. Ask me about anything genuinely ambiguous before finalizing, but make reasonable assumptions and note them rather than blocking on every detail.
```

---

## PHASE 2 — System Design & Architecture (with ADRs)

*Artifact: `docs/architecture.md` + `docs/adr/` records. No production code.*

```
Now the system design phase — still documents, not implementation code.

Produce docs/architecture.md:
1. A layered architecture description (presentation / domain / data), the responsibility of each layer, and the dependency direction rules from CLAUDE.md. Include a simple text/ASCII diagram of the modules and which way dependencies point.
2. The module/target breakdown: what should be its own Swift module or folder, and where the seams are that let each part be tested in isolation. Consider the local-Swift-package structure recommended in docs/claude-code-xcode-setup.md (Domain and Data as SPM packages, thin app target).
3. The key protocol boundaries (interfaces) between layers — e.g. how the presentation layer talks to the domain, how the domain gets word data without knowing about persistence, and the speech/audio protocol that wraps on-device TTS — so dependencies can be injected and mocked in tests.

Then write short Architecture Decision Records in docs/adr/ (one file each, ADR-001, …) for these decisions, each stating context, options considered, decision, and consequences:
- Persistence: Core Data vs. bundled SQLite (e.g. via GRDB) vs. JSON + Codable. Recommend one for a solo-maintained, offline-first, bundled-content app and justify it.
- UI architecture pattern (recommend MVVM unless you have a better-justified alternative for this app).
- Testing frameworks: recommend the current best-practice choice for unit tests and for UI tests, and confirm they're current — don't assume, check what's recommended now.
- Language-pack format and how packs are bundled, discovered, and (if ever) updated.

For each ADR, verify your recommendation reflects current Apple/community best practice before committing. Present the architecture and ADRs for my review before we scaffold anything.
```

---

## PHASE 3 — Data Contract & Language-Pack Schema

*Artifact: `docs/language-pack-schema.md` + a formal schema file + validation rules. No app code yet.*

```
Define the data contract that every language pack must satisfy — this is what keeps "add a language" a content task instead of an engineering task, so treat it as a versioned, validated interface.

Produce:
1. docs/language-pack-schema.md: the formal schema for a word entry (unique ID, lemma, display form, part of speech, frequency rank, register tag [casual/formal/neutral], content-vs-function-word flag, exactly one example sentence, and an OPTIONAL audio reference — v1 ships no audio files and speaks via on-device TTS; the field exists so future packs can add real recordings without a schema change) AND the pack-level metadata (language code, display name, schema version, word count, source/attribution, license note — must carry the wordfreq CC-BY-SA 4.0 attribution). Include a schema_version field and a short policy for how schema changes are versioned so old packs don't silently break.
2. A machine-readable schema (JSON Schema) that a pack can be validated against.
3. The validation rules a pack must pass to be considered valid: no missing required fields, unique IDs, exactly 1000 usable entries, every audio reference (if present) resolvable, AND the sentence-frequency constraint from the spec — every example sentence uses only words more frequent than its target word (define precisely how function words and proper nouns are treated). This constraint is a formal, machine-checked rule, not a guideline.
4. A tiny hand-written example pack of ~5 entries that conforms, so we have a fixture for tests — plus a `fixtures/invalid/` set: one minimal pack per validation-rule class, each breaking exactly one rule and named for it (`dup-id`, `id-mismatch`, `dup-rank`, `function-word-flag`, `word-count-mismatch`, `sentence-content-violation`, `sentence-missing-target`, `wordfreq-attribution`, `future-schema-version`, `unresolvable-audio`), with an `expected.json` mapping each file to the rule it violates. These are the rejection fixtures the Phase 6 and Phase 7 validators must catch (a validator that rejects nothing passes an all-valid corpus). The valid pack is the positive control.

Explain the tradeoffs of any modeling decisions that matter for morphologically rich languages (lemma vs. inflected forms) and for register, since those affect every future pack. Present for review before implementation.
```

---

## PHASE 4 — Repository Scaffolding, Tooling & CI

*Artifact: project skeleton, linting/formatting, CI pipeline. First code, but mostly config.*

> ⚠️ **Naming gate:** the real app name must be decided before running this phase (CLAUDE.md still says "TopWords (working title)" otherwise).
> Note: git is already initialized with `main` as the default branch — skip re-initializing; just add the .gitignore.

```
Set up the project foundation and engineering tooling. I have Xcode installed but have never created a Swift project — walk me through each step and explain what each generated file/folder is for.

Do the following:
1. Create the SwiftUI app project [App Name], structured to reflect the layered architecture from Phase 2 (separate folders/modules for presentation, domain, data, plus a test target per layer). Use Xcode 16+ synchronized folder groups and local Swift packages per docs/claude-code-xcode-setup.md so files added on disk appear in the project automatically.
2. Add an appropriate Swift/Xcode .gitignore (git itself is already initialized) and set up a conventional-commits-friendly workflow.
3. Add and configure static analysis / formatting (SwiftLint + a formatter). Give me a sensible baseline config and explain the few rules that matter most.
4. Add a README.md with a project overview, the architecture summary, and how to build/test locally.
5. Set up CI (GitHub Actions on a macOS runner) that on every push builds the project and runs the test suite and the linter. Keep it lean to stay within free runner minutes. Explain the workflow file line by line since CI for iOS will be new to me. The CI must **enforce the CLAUDE.md testing standards as hard gates**, not just run tests:
   - **Coverage gate:** `swift test --enable-code-coverage` for the Domain and Data packages, then `xcrun llvm-cov export --summary-only` — fail if Domain line coverage < 90% or Data < 80%. Pin the exact `.build/.../*.profdata` path (it varies by toolchain) so the gate is stable. No coverage gate on the app target.
   - **Warnings as errors:** build the packages and app with `-warnings-as-errors` (this is what actually enforces the Swift 6 strict-concurrency model from architecture.md §4).
   - **Traceability report:** run `scripts/trace-requirements.sh` and print its output (report, does not fail the build).
   - **Determinism grep:** fail if any test source under a `Tests` path references `Date()`, `Task.sleep`, or unseeded `random` (tests must use the injected `Clock`/seeds).
   Before finishing the phase, **prove each gate actually bites**: once, deliberately break a test, add a compiler warning, and add a Domain source file with no test; confirm CI goes red on each; then revert. An unverified gate is not a gate.
6. Fill in the "Build & test commands" section of CLAUDE.md with the exact working commands (templates in docs/claude-code-xcode-setup.md).

Put only placeholder screens in the app for now (language selection, study, progress) — no real logic yet. Confirm the build is green and CI passes before we continue.
```

---

## PHASE 5 — Domain Layer: Spaced-Repetition Engine (Test-First / TDD)

*Artifact: fully unit-tested pure-Swift scheduler. No UI, no persistence.*

```
Build the spaced-repetition engine as a pure-Swift domain module with zero dependencies on SwiftUI, persistence, or the file system — using test-driven development.

Process, in this order:
1. First, describe the algorithm (a simplified SM-2-style scheduler tracking ease factor, interval, repetition count, and next-review date per word) and recommend whether the recall grade should be a 4-level scale (again/hard/good/easy) or a simpler correct/incorrect, with reasoning. I'll confirm before you write tests.
2. Write the unit tests FIRST — before the implementation — covering normal scheduling progression, the reset-on-failure path, first-ever review, boundary values (minimum/maximum intervals), and any edge cases you can identify. **In addition to these example cases, add invariant/property tests** that drive a long seeded random walk of (state, grade) steps and assert the properties hold at every step: `next-review ≥ today` always (FR-8), ease and interval stay within their clamps (no drift over long sequences), a failing grade never lengthens an interval, and the engine is pure — same `(state, grade, today)` ⇒ same output. Example tests prove the listed cases; the invariants catch drift and off-by-ones at clamps only reached after many reps. Work the CLAUDE.md red-green-refactor cycle one behavior at a time — write a test, run it, and show me that it fails *because the scheduler doesn't exist yet* (not because it doesn't compile) before writing any engine code.
3. Then implement the engine one behavior at a time — the minimal code to green each failing test, refactoring while green — never more than the current test demands. Keep it a plain, injectable type (no singletons, no global state) so it can be driven deterministically in tests — including making "today's date" injectable rather than reading the system clock directly.
4. Explain the algorithm and the Swift specifics as you go; spaced-repetition implementations are new to me even though the concept makes sense.

End with a coverage summary and note any behavior you deliberately left simple for v1.
```

---

## PHASE 6 — Data Pipeline (Python) with Validation & Tests

*Artifact: tested Python tool that emits schema-valid language packs, sentences included.*

```
Now the content pipeline. Write a Python tool (I'm strong in Python) that generates a schema-valid language pack for French and validates its own output against the JSON Schema from Phase 3.

Source: the `wordfreq` package — this is settled (spec D2). Licensing is pre-answered: data is CC-BY-SA 4.0, commercial use OK with attribution; the pipeline must emit the attribution/license fields in pack metadata. (Do a quick sanity check that wordfreq's license hasn't changed; don't re-open the source decision.)

The tool should:
1. Pull ~1,200 top words (a buffer above 1,000), clean and lemmatize the raw token list (it contains inflections, names, and noise), tag part of speech, and flag function vs. content words — spaCy is the expected workhorse.
2. Generate exactly one example sentence per word via the Claude API, subject to the spec's hard constraint: each sentence uses only words more frequent than its target word (per the Phase 3 validation rules' treatment of function words / proper nouns). Enforce the constraint programmatically after generation — regenerate on violation, never just trust the prompt.
3. Leave the audio-reference field empty by design (v1 is on-device TTS; the field is optional in the schema).
4. Validate its own output against the JSON Schema and ALL Phase 3 validation rules (including the sentence constraint), failing loudly if the pack is non-conforming.
5. **Build the validator and the sentence-constraint checker test-first** (they are pure logic): write the rejection tests before the checker exists — load every pack in `fixtures/invalid/` and assert each fails *for the specific rule it breaks* (per `fixtures/invalid/expected.json`), plus `fixtures/fr-mini.pack.json` passes as the positive control — run them, watch them fail because the checker isn't there yet, then implement to green them one rule at a time. The spaCy parsing/tagging and Claude-API generation are IO-heavy glue: test those alongside (mock the Claude API), not necessarily first. Add a lint/format setup for the Python side, and gate validator-module coverage with `--cov-fail-under` (validator module only, not the whole tool) so the checker itself can't rot untested.

Explain the pipeline design and how it stays reusable across languages, since ease-of-adding-languages is a core goal. Flag anything about the French output that a human should review before it ships (the ~100-sentence spot-check happens at Phase 13).
```

---

## PHASE 7 — Persistence Layer (behind a protocol, tested)

*Artifact: storage implementation hidden behind a repository interface, with tests using an in-memory double.*

```
Implement the data/persistence layer using the technology chosen in the Phase 2 ADR, hidden behind the repository protocol(s) defined in the architecture doc — so the domain and presentation layers never depend on the concrete storage.

Deliver:
1. The concrete persistence implementation for: loading a language pack, and reading/writing per-word review state (ease factor, interval, next-review date, learned status) and per-language progress.
2. An in-memory test double conforming to the same protocol, for use in higher-layer tests.
3. Tests for the real implementation. The SwiftData round-trip and fixture load are glue — test them alongside the store. But the **loader's error mapping is logic: write those tests first** (which malformed input maps to which typed error), watch them fail, then implement. Cover: round-tripping review state, loading the Phase 3 fixture pack, handling a missing or corrupt pack gracefully (returns a typed error, does not crash), and a migration/versioning smoke test if the chosen store needs one. For the pack loader, drive the `fixtures/invalid/` set the same way Phase 6 does: each malformed pack the loader is responsible for must surface a *typed* error (not just "some error"), and `future-schema-version.pack.json` in particular must return the `unsupportedSchemaVersion` fail-closed error from the schema doc §9. The valid `fr-mini` pack is the positive control.

Explain the persistence API choices and any Swift concurrency considerations (e.g. actor isolation, main-thread rules) as they come up, since these are new to me.
```

---

## PHASE 8 — Presentation Layer (SwiftUI + ViewModels, ViewModels tested)

*Artifact: thin views, tested ViewModels, wired to domain + a fake repository.*

```
Build the presentation layer with MVVM (or the pattern chosen in Phase 2). Keep SwiftUI views thin; put logic in ViewModels that depend only on protocols (the repository and the domain engine), injected so they can be tested with fakes.

The ViewModels are logic, so build them **test-first** (CLAUDE.md): for each screen, write the ViewModel unit tests before the ViewModel exists, watch them fail, then implement to green them. The SwiftUI views themselves are thin glue and aren't unit-tested here. Build these screens against the tested domain engine and the in-memory repository double from Phase 7:
1. Study/review session: presents a card, enforces active recall (recommend and implement either reveal-then-self-grade or a lightweight production/selection interaction, per our active-recall principle), speaks the word and example sentence through a speech protocol wrapping AVSpeechSynthesizer (spec D3) — the protocol is injectable and fake-able in tests, and callers must not know whether speech is TTS or a future audio file — shows the one example sentence, and feeds the grade back to the scheduler.
2. Progress screen: words learned out of 1000 for the current language, and nothing else.
3. Language selection: lists available packs; shows locked/unlocked state (purchase wiring comes in Phase 11 — stub the lock check behind a protocol now).

Requirements:
- Write ViewModel unit tests for each screen (correct card sequencing, grade handling, progress calculation, transition into the completion state) using the fakes — no real persistence or real TTS in these tests.
- Keep visuals plain and functional; the dedicated design pass is later. Focus on correct behavior and clean view/ViewModel separation.

Explain SwiftUI state-management concepts (state, bindings, observation) the first time each appears.
```

---

## PHASE 9 — Integration & the "Done" State

*Artifact: layers wired end-to-end with real persistence; integration tests across the seams.*

```
Wire the real layers together end-to-end (real persistence, real domain engine, real ViewModels) and add integration tests across the seams.

Also implement the completion/"done" state properly:
1. Define precisely what "learned" means for a single word (e.g. reaching N successful intervals) and surface it in progress. This rule is pure domain logic — **test it first** (a word at N-1 intervals is not learned; the Nth crosses it; a lapse un-learns it or not, whichever you decide) before implementing, same cycle as Phase 5. The end-to-end wiring below is glue, tested by the integration tests as written.
2. When all 1000 words in a language reach that state, present a clear completion screen instead of continuing silently. Propose 2–3 options for what that screen offers (e.g. review-only mode, prompt to unlock another language) and let me choose.

Integration tests to add:
- A full session flow: load pack → study several words → grades persist → progress updates → relaunch reflects saved state.
- Reaching the completion state end-to-end.
- Graceful handling of a corrupt/missing pack at the integration level.

Report anything that had to change in the layers to make integration work, and whether any of it violated the dependency-direction rules (it shouldn't have).
```

---

## PHASE 10 — Cross-Cutting Concerns

*Artifact: accessibility, error states, offline correctness, UI localization, observability decision.*

```
Harden the cross-cutting concerns that a serious app needs. Address each and add tests where testable:

1. Accessibility: VoiceOver labels for every interactive element and card, Dynamic Type support across all screens, and sufficient color contrast. Tell me how to verify each manually (VoiceOver walkthrough, largest Dynamic Type setting). **Also add the automated net:** a XCUITest that calls `try app.performAccessibilityAudit()` on each core screen (Xcode's built-in audit — catches missing labels, low contrast, and clipping at large Dynamic Type, and fails the test on any issue; scope with `XCUIAccessibilityAuditType` and filter individual known-OK issues via the closure). This runs in CI so accessibility regressions are caught every push, not only at a manual pass. The manual VoiceOver walkthrough stays for what an audit can't judge — whether a label is *meaningful* — but the regression-catching half is automated.
2. Error handling & user-facing states: replace any silent failures or fatal errors with typed errors and real UI states (e.g. "couldn't load this language"). The error→state mapping is logic — **test-first**: write the failing test that a given error surfaces a given UI state, then implement it.
3. Offline-first verification: audit that every core feature works with no network and that nothing silently depends on a network call. Document the result.
4. UI localization readiness: extract the app's own interface strings (buttons, labels, the completion screen) into a localization catalog so the UI itself can later be translated — separate from the learning-content packs. Localize into at least one second language to prove the setup works.
5. Observability/analytics decision: consistent with the privacy stance, decide and document what (if anything) is collected. Default to little/none, local-only; no third-party trackers. Write down the decision and why.

Summarize what you changed and any residual risks.
```

---

## PHASE 10.5 — Recall Scale & Visual Design (inserted 2026-07-28)

Not in the original plan. Added after reviewing the app on device.

Spec: `docs/superpowers/specs/2026-07-28-binary-recall-and-warm-ui-design.md`

1. ~~**Binary recall scale**~~ — `Grade` reduces from four cases to `forgot` /
   `recalled`; `recalled` gains a positive ease delta so ease can recover.
   Done 2026-07-29.
2. ~~**Warm minimal token layer**~~ — semantic colorsets and a spacing scale,
   replacing the empty `AccentColor` that left every control system blue.
   Done 2026-07-31.
3. ~~**Swipe to grade**~~ — right for recalled, left for forgot, with both buttons
   retained as the accessible path. Done 2026-07-31.

`docs/requirements.md` already parameterised the grade scale as "4-level vs.
binary", so no requirement changes.

**Phase complete 2026-07-31.** Phase 11 is next.

---

> **Reordered 2026-08-01: Phase 12 ran before Phase 11, and is now complete.**
> Monetization needed a second pack to sell. Hindi is real — 1000 words, shipped
> locked — so Phase 11 unshelves now:
> `docs/superpowers/specs/2026-08-01-storekit-monetization-design.md`. **Re-verify
> its StoreKit API notes first** (last checked 2026-08-01).
>
> Until Phase 11 lands, Hindi shows as **locked with no way to unlock it**.
> `LanguageSelectionViewModel.select` refuses locked packs, so this is safe, but
> it is a worse user-facing state than the "coming soon" row it replaced. The two
> phases should land close together.

## PHASE 11 — Monetization (StoreKit 2) with Sandbox + StoreKit Testing

*Artifact: purchase flow behind the Phase 8 lock protocol, tested with StoreKit's test tooling and sandbox.*

```
Implement in-app purchases with StoreKit 2, plugged into the lock-check protocol stubbed in Phase 8 — first language free, each additional language a $0.99 non-consumable one-time unlock.

Deliver:
1. The purchase flow: fetch products, purchase, handle success/failure/cancellation with real UI states, and — importantly — restore purchases.
2. Persist entitlement so unlocked languages stay unlocked across relaunch/reinstall, and verify entitlements against StoreKit rather than trusting a local flag alone.
3. The purchase/entitlement state machine (success → unlocked, failure → stays locked with a message, cancellation → no change, restore → re-granted) is logic — build it **test-first** with the StoreKit testing framework (a local `.storekit` configuration): write each state-transition test first against StoreKitTest, watch it fail, then implement. The StoreKit *SDK calls* (fetch products, the purchase sheet) are glue tested alongside; the state machine reacting to their results is what gets tested first.
4. A step-by-step guide for the App Store Connect setup I must do outside Xcode: creating the IAP products, enrolling in the Small Business Program (relevant to the fee split at $0.99), setting up a sandbox tester, and running through a sandbox purchase to confirm it works end-to-end.

Confirm the StoreKit 2 APIs you're using are current before committing. Explain the purchase/entitlement concepts as we go — IAP is entirely new to me.
```

---

## PHASE 12 — Second Language: Architecture Validation (Hindi)

*Artifact: a second pack integrated with (ideally) zero app-code change — the real test of the core design goal.*

> **Phase complete 2026-08-01.** Full verdict:
> [`docs/phase-12-verdict.md`](phase-12-verdict.md). The headline:
>
> - **App code: one file, +6/−29, and all six insertions are comments.** 29 of the
>   deletions remove the `comingSoon` placeholder. Exactly one behavioural line
>   changed, and it was a latent Phase 8 accessibility bug that Hindi merely
>   exposed. Nothing in `Packages/`. **ADR-004 holds for the app layer.**
> - **Pipeline: three files, +262/−15** — a new `UDPipeAnalyzer` backend, the
>   `ANALYZERS` table, `packgen models`, and two correctness fixes. spaCy
>   publishes no Hindi POS model at all, so the honest restatement is: adding a
>   language is a table entry *provided a tagging model exists for it*.
> - **Nine §6 waivers** against French's one — but a different kind. French's was
>   unsatisfiable; all nine of Hindi's are *unverifiable*: correct sentences whose
>   target word the tagger cannot recognise.
>
> Two findings the design missed, both invisible from the 15-word sample it was
> written against: `words.py` discarded 2707 of Hindi's top 3000 forms because
> Devanagari vowels are Unicode *marks*, not letters; and the tagger cites verbs
> by stem (`कर`) where the pack cites the infinitive (`करना`), which alone
> accounted for 333 of the first-run violations.

```
Time to prove the central architectural claim: adding a language should require no app-code changes. Using the Phase 6 pipeline, generate a pack for Hindi (spec D5 — chosen deliberately because its weaker NLP tooling and richer morphology stress the pipeline). Help me integrate it.

Then give me an honest verdict:
1. Did any Swift/app code have to change to support this language, beyond adding the data pack and its assets? List exactly what, if anything. **Make this mechanical, not self-reported:** the claim holds only if `git diff --name-only` for the integration commit touches nothing under `Packages/*/Sources` or the app target's source folders (data packs, assets, and the pack manifest are the only allowed additions). Show me that diff as the evidence. This is the project's central architectural claim (ADR-004) — it gets checked, not asserted.
2. If code did change, that's a leak in the abstraction — identify the root cause and propose a refactor so the next language truly needs zero code changes.
3. Add/extend tests so both languages are covered (pack loads, progress is tracked independently per language, switching languages preserves each one's state).

Also sanity-check the pack itself against the Phase 3 validation rules before integrating, and report honestly on pipeline friction: where Hindi needed pipeline work (lemmatization, POS quality, sentence generation), so we know the real per-language cost.
```

---

## PHASE 13 — Comprehensive Testing & QA

*Artifact: full test-suite review, UI/snapshot tests, edge-case matrix, performance check, manual QA checklist, TestFlight.*

```
Pull the whole test strategy together and close the gaps. Produce docs/test-plan.md and implement what's missing.

1. Coverage review: report unit-test coverage per layer, and flag any domain or ViewModel logic that isn't adequately covered. Fill the important gaps.
2. UI tests: add automated UI tests for the critical flows (complete a study session, reach the completion state, unlock a second language) and, if the chosen tooling supports it and it's currently maintained, snapshot tests for the key screens.
3. Edge-case matrix: enumerate and test the nasty cases — empty/corrupt pack, interrupted purchase, app backgrounded mid-session, device date changed (spaced-repetition depends on dates), very large Dynamic Type, VoiceOver navigation, TTS voice unavailable or uninstalled (the speech protocol must degrade gracefully, not crash), and rapid repeated input.
4. Performance check: measure cold launch and card-advance latency against the Phase 1 NFR targets, and profile for any obvious main-thread jank or memory issues. Measure these **locally on the baseline device** (NFR-2/NFR-3) — deliberately **not** a CI gate: a shared GitHub macOS runner is too noisy for a reliable 100 ms / 2 s assertion, so gating there would only produce flakes. Record the measured numbers in `docs/test-plan.md` instead.
5. Content QA (spec D4): draw ~100 random example sentences from the French pack for my human spot-check; give me a simple way to record verdicts and regenerate rejects through the pipeline.
6. Manual QA checklist: a concrete, step-by-step checklist I can run on a physical device before any release, covering every functional requirement from Phase 1 and every flow above.
7. TestFlight: walk me through setting up a TestFlight beta and what feedback to collect from a small group of real testers (I can recruit a few French/heritage-language learners) before public launch — including explicitly asking testers to flag any example sentence that sounds unnatural.

Give me a clear read on whether the app is release-quality or what specifically still blocks it.
```

---

## PHASE 14 — Release Engineering

*Artifact: submission-ready build + checklist.*

```
Final phase: get to a submittable, well-documented release.

1. App Store submission checklist tailored to this app: privacy policy (what it must say given local-only, no-tracking data practices), the privacy "nutrition label" answers, screenshot and metadata requirements, the age-rating questionnaire, and the items first-time submitters most often miss.
2. Attribution (spec D2): verify the wordfreq CC-BY-SA 4.0 attribution appears in the app's about/credits screen and in each pack's license-note metadata before submission.
3. Versioning & release notes: set a sane version/build scheme and draft the initial release notes in the app's plain, no-hype voice.
4. A short MAINTENANCE.md: how to cut a release, how to add a new language end-to-end (pipeline → validate → bundle → test), and the known tech debt list accumulated across phases so future-me has a map.
5. A final pre-submission self-review: confirm no deprecated APIs, all tests green, CI passing, accessibility verified, and offline-first intact. Report anything outstanding.
```

---

### Phase map at a glance
- **Design (no code):** 1 Requirements → 2 Architecture/ADRs → 3 Data contract
- **Foundation:** 4 Scaffolding + tooling + CI *(naming gate)*
- **Core, test-first:** 5 Domain engine → 6 Content pipeline (words + sentences) → 7 Persistence
- **Product:** 8 Presentation → 9 Integration + done-state → 10 Cross-cutting concerns
- **Business & proof:** 11 StoreKit → 12 Hindi validation
- **Verify & ship:** 13 Comprehensive testing/QA → 14 Release engineering

Phases 1–9 get you a working, tested single-language app. 10–14 make it accessible, purchasable, provably extensible, thoroughly tested, and submittable. TestFlight sits in Phase 13, before any public launch.
