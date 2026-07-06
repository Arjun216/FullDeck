# Top 1000 Words — Feasibility Assessment & Design Decisions

**Date:** 2026-07-06
**Status:** Approved
**Scope:** Feasibility verdict for the "Top 1000 Words" iOS app, plus the decisions and plan amendments that resolve the open risks in the 14-phase build plan (the prompt library). This spec does not replace the phase prompts — it patches them.

## Verdict

**Green light.** The app is a low-risk, well-trodden archetype: a spaced-repetition vocabulary app with no backend, built on stable Apple frameworks (SwiftUI, StoreKit 2, local persistence). SM-2 is a decades-old, fully documented algorithm. The developer's zero Swift experience is offset by strong general SWE fundamentals, Python skills (used directly in the content pipeline), and Claude Code driving the build.

The two real feasibility risks were never in the code — they were **content production** (1,000 example sentences + audio per language) and **data licensing**. Both are resolved by the decisions below. Commercial upside is modest (crowded category, $0.99-per-language pricing) and accepted: the stated goal is learning iOS while shipping a real, polished App Store app.

## Product summary (unchanged from CLAUDE.md draft)

A SwiftUI iOS app that teaches the ~1000 highest-frequency words in a language using spaced repetition, and nothing else. No gamification, no ads, no subscriptions. First language free; each additional language a $0.99 one-time unlock. Layered architecture (presentation → domain → data), self-contained versioned language packs, offline-first, local-only data.

## Decisions

### D1 — Goal: learn iOS + ship something real
Optimize for learning pace and shipped quality, not revenue. The 14-phase structure is kept in full; its one-concept-per-phase pacing is a feature for a first iOS project, not overhead.

### D2 — Word list source: `wordfreq`
- Frequency data from the `wordfreq` Python package (data license **CC-BY-SA 4.0**; code Apache 2.0). Commercial use is permitted with attribution. ShareAlike applies to the derived word-list data only — app code and generated sentences remain proprietary.
- **Leipzig Corpora Collection is rejected** (non-commercial restrictions — unsuitable for a paid app). Remove it as a candidate from the Phase 6 prompt.
- Hermit Dave's FrequencyWords (OpenSubtitles-derived, CC-BY-SA 3.0) is the cross-check/fallback source.
- Note: `wordfreq` stopped receiving updates in 2024; irrelevant at top-1000 granularity.
- Raw lists are token lists (inflected forms, names, noise). The Phase 6 pipeline cleans, lemmatizes, and POS-tags via spaCy (MIT license).

### D3 — Audio: on-device TTS for v1
- Word and sentence audio via `AVSpeechSynthesizer`. Zero cost, zero licensing risk, works offline, nothing bundled — packs stay small.
- The pack schema keeps an **optional** audio-reference field so future packs can ship real recordings without a schema change.
- The presentation layer wraps speech behind a protocol so bundled audio files can swap in behind the same interface later.

### D4 — Example sentences: LLM-generated with a review gate
- One sentence per word, generated via the Claude API as a Phase 6 pipeline step (~a few dollars per language).
- **Pedagogical constraint, enforced programmatically:** every sentence uses only words more frequent than its target word (plus proper nouns/function words as defined by the validation rules). This is a formal pack validation rule, not just a prompt instruction. Every sentence therefore doubles as review of already-known words.
- Quality gate: spot-check ~100 random sentences before beta; TestFlight testers (French/heritage learners) explicitly asked to flag unnatural sentences.
- Generated sentences are owned outright — no attribution or ShareAlike obligations.
- Rejected alternatives: Tatoeba-only (uncontrolled difficulty, uneven coverage, per-sentence CC-BY attribution burden); hybrid Tatoeba+LLM (two sourcing code paths for marginal v1 gain — it is the upgrade path if beta feedback demands it).

### D5 — Languages: French first, Hindi as the architecture test
- **French** is the free launch language: strongest spaCy support, high-quality Apple TTS voices, large learner market, easy reviewer/tester recruiting.
- **Hindi** is the Phase 12 second-language validation — deliberately harder (weaker NLP tooling, morphologically richer), so surviving it genuinely proves the "add a language = add a data pack" claim.

### D6 — Plan shape: keep all 14 phases, patched
The phase prompts stand as written except for the amendments below.

## Plan amendments

| Phase | Change |
|-------|--------|
| 3 — Schema | Audio reference becomes **optional**. Add the sentence-vocabulary constraint (D4) as a formal validation rule. Document the wordfreq CC-BY-SA attribution requirement in pack metadata. |
| 6 — Pipeline | Source is `wordfreq`, named explicitly; delete the Leipzig option (licensing pre-answered, D2). Add a sentence-generation step (Claude API) with automated constraint validation. Remove audio-file generation entirely. |
| 8 — Presentation | "Plays the word audio" → a small speech protocol wrapping `AVSpeechSynthesizer` (D3), injectable and fake-able in tests. |
| 13 — QA | Add the ~100-sentence spot-check and "flag odd sentences" to the TestFlight feedback checklist. Replace the "no-audio-file fallback" edge case with "TTS voice unavailable/uninstalled". |
| 14 — Release | wordfreq attribution appears in the app's about/credits screen and in each pack's license note. |

## Costs & timeline

- **Fixed costs:** Apple Developer Program $99/year; a few dollars of Claude API per language pack; no other spend (no backend, no audio licensing).
- **Timeline (solo, part-time, Claude Code-driven):** phases 1–9 (working, tested, single-language app) ≈ 4–8 weeks; through App Store submission ≈ 2–3 months. One phase per session, as the plan prescribes.

## Residual risks (accepted)

1. **Generated-sentence quality** — mitigated by the automated vocabulary constraint plus human spot-check and beta flagging (D4); upgrade path is the Tatoeba hybrid.
2. **TTS voice quality** — decent but robotic; accepted for v1, upgrade path preserved by the optional audio-reference field (D3).
3. **Pipeline per-language variance** — "add a language = data pack" holds for app code, but each new language is real pipeline/content work (NLP model quality varies, e.g. Hindi). Accepted; Phase 12 measures it honestly.
4. **Discoverability/revenue** — no marketing plan; accepted under D1 (learning-first goal).

## Open items (deliberately deferred to their phases)

- App name (needed by Phase 4 scaffolding).
- Recall-grade scale (4-level vs binary) — Phase 5 decides with reasoning.
- Persistence technology — Phase 2 ADR decides.
- Definition of "learned" (N successful intervals) — Phase 9 decides.
- Minimum iOS version — Phase 1/2 decide; note Xcode 26-era toolchain assumed (see `docs/claude-code-xcode-setup.md`).

## Next step

Feed this spec plus the phase prompt library into the writing-plans process when implementation begins. Phase 1 (requirements) is the first session.
