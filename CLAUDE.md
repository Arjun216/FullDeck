# Project: TopWords (working title) — Top 1000 Words

**Naming:** "TopWords" is a placeholder. The real app name MUST be decided before Phase 4 (project scaffolding) — renaming before the Xcode project exists is free, after is not. Remind me if Phase 4 starts and this line is still here.

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
- Test-first for domain logic: write failing tests, then implement to pass. Don't write the scheduler without tests.
- Every layer is testable in isolation via protocol boundaries and injected dependencies (dependency inversion). No singletons reaching into global state.
- Keep views thin: logic lives in ViewModels, not in SwiftUI view bodies.
- Handle errors explicitly with typed errors and real user-facing states — never crash on bad data or a missing file.
- Accessibility is a requirement, not a nice-to-have: VoiceOver labels and Dynamic Type support from the start.
- Conventional commits, small and focused. After each phase, do a self-review pass and tell me about any tech debt you're knowingly leaving.
- Don't use deprecated or soon-to-be-deprecated APIs. When unsure whether an API/library is still current best practice, check before committing to it and tell me what you found.

## Build & test commands
(To be filled in at Phase 4 once the project exists — use the command templates in `docs/claude-code-xcode-setup.md`.)

## About me (the developer)
Strong Python and general SWE fundamentals; zero prior Swift/SwiftUI/Xcode experience. The first time you introduce a new Swift/SwiftUI/Xcode concept, briefly explain what it does and why — like explaining to someone fluent in other languages but new to this one. Don't re-explain concepts already established earlier in the project. Prefer incremental steps I can run and understand over large drops of code.

## Out of scope for v1 (do not build)
Grammar lessons, pronunciation scoring, social features, a backend/server, multiple example sentences per word, bundled audio recordings (v1 is on-device TTS), additional push notifications beyond one optional daily reminder.
