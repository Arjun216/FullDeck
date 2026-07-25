# Requirements Specification — "Top 1000 Words" (working title)

**Phase:** 1 (Requirements) · **Status:** Draft for review · **Date:** 2026-07-07

This is the contract later phases test against. It is deliberately implementation-agnostic:
it says *what* must be true, not *how*. Where a detail is settled elsewhere it cites the
source (`CLAUDE.md`, spec decisions D1–D6); where a detail is deliberately deferred to a
later phase, it names a stable parameter instead of guessing a value.

## 1. Definitions & parameters

- **Pack / language pack** — a self-contained, versioned data set for one language (frequency-ranked words, POS, register, one example sentence per word, optional audio reference). Schema is fixed in Phase 3.
- **Active language** — the single pack the user is currently studying.
- **Due review** — a word whose next-review date is on or before today.
- **New word** — a word in the active pack the learner has never been shown.
- **Session** — one sitting of studying cards for the active language.
- **`L` (learned threshold)** — the condition under which a single word counts as "learned". Defined precisely in **Phase 9**; treated here as a named parameter so this contract stays stable.
- **`G` (recall-grade scale)** — how the learner grades a recall attempt (4-level vs. binary). Chosen in **Phase 5**; referenced abstractly here.
- **`N` (daily new-word cap)** — max new words introduced per calendar day for the active language. User-adjustable; default **10**.

---

## 2. Functional requirements

Each requirement has a stable ID and a testable acceptance criterion. "The app" means the shipped v1 iOS app.

### FR-1 — Language selection
The app lists every bundled pack with its display name and a locked/unlocked state, and lets the user set the active language by choosing an unlocked pack.
**Acceptance:** Given ≥2 bundled packs, the selection screen shows each with correct lock state; selecting an unlocked pack makes it the active language for subsequent sessions. Selecting a locked pack does **not** start a session (see FR-14).

### FR-2 — Free launch language
French is bundled and unlocked by default; it requires no purchase.
**Acceptance:** On a first launch with no purchases, French appears unlocked and is fully studyable.

### FR-3 — Study session assembly
A session for the active language serves that language's due reviews plus new words (subject to FR-4), one card at a time.
**Acceptance:** Given a pack with `d` due reviews and available new words, starting a session presents due-review cards and new-word cards; every card belongs to the active language only.

### FR-4 — New-word daily cap (adjustable)
At most `N` new words are introduced per calendar day for the active language. Due reviews are **never** capped. `N` is user-adjustable (default 10).
**Acceptance:** With `N=k`, no more than `k` distinct new words appear across sessions in one day; due reviews beyond `k` still appear the same day. Changing `N` in settings takes effect for the next day's introductions.

### FR-5 — Active recall
A card does not reveal the answer until the learner has committed to an attempt; after reveal, the learner records a self-assessment (`G`) that feeds the scheduler. (Exact interaction — reveal-then-self-grade vs. selection/production — is chosen in Phase 8.)
**Acceptance:** The answer is not visible in a card's initial state; a user action is required to reveal it; the grading control is available only after reveal, and the recorded grade is passed to the scheduler (FR-8).

### FR-6 — One example sentence per card
Every card shows exactly one example sentence for its word. The pack contract guarantees each sentence uses only words more frequent than its target word (validated at pack-build time, Phase 3/6); the app displays whatever the validated pack provides.
**Acceptance:** Every card renders exactly one non-empty example sentence for the current word. (The frequency constraint is verified by pack validation, not at runtime.)

### FR-7 — Audio playback (on-device TTS)
On each card the learner can play spoken audio of the word and of the example sentence, produced by on-device TTS (spec D3) behind a speech protocol. If no TTS voice for the active language is installed, the app shows the text and a clear "audio unavailable" state and does not crash.
**Acceptance:** Invoking playback speaks the word / sentence via the TTS backend; with the language's voice uninstalled, playback is disabled or reports unavailability gracefully, and the session remains fully usable.

### FR-8 — Spaced-repetition scheduling
Grading a word updates its scheduling state (ease, interval, repetition count, next-review date) per the simplified SM-2-style engine (Phase 5). A failing grade resets the interval (reset-on-failure). Next-review date is always ≥ today.
**Acceptance:** For a first review, a passing grade schedules a future next-review date; a subsequent passing grade lengthens the interval; a failing grade shortens/resets it per the engine's rules. Behavior is deterministic given an injected "today" (no reliance on the wall clock in tests).

### FR-9 — State persistence across relaunch
Per-word review state and per-language progress survive app termination and relaunch.
**Acceptance:** Grade a word, terminate the app, relaunch — the word's next-review date and the language's progress reflect the grade.

### FR-10 — Progress: words learned
For the active language the app shows the count of learned words out of the pack total (1000). Counts are independent per language. Progress is limited to learning-helpful views (this FR plus FR-17 and FR-18); no activity/engagement dashboards (§4).
**Acceptance:** After a word meets `L`, the learned count increments by one; switching active language shows that language's own independent count.

### FR-11 — Completion ("done") state
When all 1000 words in the active language meet `L`, the app presents a distinct completion screen instead of serving new cards. (What the completion screen offers — e.g. review-only mode, prompt to unlock another language — is chosen from 2–3 options in Phase 9.)
**Acceptance:** With every word in a pack at `L`, entering study for that language shows the completion state rather than a new card; no further new words are introduced for that language.

### FR-12 — "Caught up" state
When no reviews are due and the daily new-word cap is exhausted, the app shows a clear "you're caught up" state (with the next review time if known) rather than an empty screen or error.
**Acceptance:** With zero due reviews and `N` new words already introduced today, starting study shows the caught-up state, not a blank/failed screen.

### FR-13 — Optional daily reminder
The learner may enable a single daily local notification at a time they choose. It is **off by default**. No other notifications exist.
**Acceptance:** Reminders default off; enabling and setting a time schedules exactly one repeating local notification at that time; disabling removes it. The app requests notification permission only when the learner enables the reminder.

### FR-14 — Purchase an additional language
Each non-free pack is a $0.99 one-time non-consumable unlock (StoreKit 2). A locked pack cannot be studied until purchased; a successful purchase unlocks it.
**Acceptance:** Selecting a locked pack offers purchase; on a successful $0.99 purchase the pack becomes selectable and studyable; on cancellation or failure it stays locked with a clear message and no charge.

### FR-15 — Restore purchases
The learner can restore previously purchased unlocks; entitlements are verified against StoreKit, not a local flag alone.
**Acceptance:** After reinstall or on a new device with the same Apple ID, restoring re-grants previously purchased packs with no additional charge.

### FR-16 — Attribution & credits
The app displays the `wordfreq` CC-BY-SA 4.0 attribution (spec D2) in an about/credits screen, and each pack carries its license note in metadata.
**Acceptance:** A credits screen reachable from the app shows the required `wordfreq` attribution text; each bundled pack's metadata contains its license note.

### FR-17 — Progress: learning-over-time trend
For the active language, the progress view shows how many words have moved into *learning* and into *learned* over time — an outcome trend (the cumulative climb toward 1000), reconstructed from each word's milestone dates, not from a study-activity log. Status buckets: *new* (never reviewed), *learning* (reviewed, below `L`), *learned* (≥ `L`).
**Acceptance:** Given words whose learning/learned milestones fall on known dates, the trend's cumulative counts at any past date match those milestones — e.g. "words learned in the last 7 days" equals the number whose learned-milestone is within 7 days. No study-activity metric (time spent, review counts) is shown.

### FR-18 — Progress: hardest words
For the active language, the progress view surfaces the words the learner finds hardest, ranked by the scheduler's per-word difficulty (ease factor; optionally a lapse count).
**Acceptance:** Words with a lower ease factor (more failures) rank higher; a word never failed is not surfaced as hard. Ranking derives from stored review state, not a separate event log.

---

## 3. Non-functional requirements

### NFR-1 — Offline-first
All core learning — language selection, studying, grading, scheduling, progress, completion, and TTS — functions with no network connectivity. The only features that use the network are StoreKit purchase and restore.
**Acceptance:** In airplane mode a full study session can be completed and its results persisted; only purchase/restore surfaces a network requirement.

### NFR-2 — Cold-launch performance
Cold launch to an interactive first screen is ≤ **2.0 s** on a supported baseline device.
**Acceptance:** Measured cold-launch time on the baseline device is ≤ 2.0 s (measured in Phase 13).

### NFR-3 — Card-advance latency
Revealing an answer and advancing to the next card each respond in ≤ **100 ms**, with no perceptible frame drops (target 60 fps) during normal session interaction.
**Acceptance:** Instrumented reveal/advance latency ≤ 100 ms; no sustained main-thread jank under profiling (Phase 13).

### NFR-4 — Accessibility: VoiceOver
Every interactive control and all card content expose meaningful accessibility labels; a full session is completable with VoiceOver.
**Acceptance:** A VoiceOver walkthrough completes a session end-to-end; no unlabeled or "button"-only controls on core screens.

### NFR-5 — Accessibility: Dynamic Type
All screens remain usable — no truncation, clipping, or overlap — at the largest accessibility text sizes.
**Acceptance:** At the maximum accessibility Dynamic Type size, every core screen renders all content without loss.

### NFR-6 — Accessibility: contrast
Text and controls meet WCAG 2.1 AA contrast (≥ 4.5:1 normal text, ≥ 3:1 large text/controls).
**Acceptance:** Core screens pass an AA contrast check in both light and dark appearance.

### NFR-7 — Privacy: local-only data
All user and learning data (review state, progress, settings, cached entitlements) is stored on-device. There is no user account and no data is transmitted off-device except StoreKit transactions handled by Apple.
**Acceptance:** No app-originated network request carries user or learning data; all state is present in on-device storage.

### NFR-8 — Privacy: no tracking
No third-party analytics, advertising, or tracking SDKs; no IDFA; no ad networks. (Any observability is decided in Phase 10 and must be local-only.)
**Acceptance:** Dependency and network audits show zero third-party trackers and zero analytics egress.

### NFR-9 — Supported platform & versions
Minimum **iOS 17.0**; iPhone; portrait orientation. iPad and macOS are not targeted in v1.
**Acceptance:** The app builds, runs, and passes its suite on the iOS 17.0 deployment target on iPhone; it is not required to adapt to iPad/landscape.

### NFR-10 — Robustness on bad data
A missing, unreadable, or schema-invalid pack produces a typed error and a user-facing state; the app never crashes on bad or missing data (`CLAUDE.md`).
**Acceptance:** Loading a corrupt/missing pack surfaces a handled error state; no crash, no fatal error.

### NFR-11 — Durability of progress
A graded result is not lost across normal backgrounding or termination.
**Acceptance:** A grade recorded immediately before backgrounding/termination is present on relaunch (overlaps FR-9; this is the durability guarantee).

### NFR-12 — UI localizability
The app's own interface strings are externalized in a localization catalog, separate from content packs, so the UI can be translated without code changes (proven in Phase 10).
**Acceptance:** UI chrome strings resolve through the localization catalog; adding a UI translation requires no code change.

---

## 4. Out of scope for v1

From `CLAUDE.md` (do not build):

- Grammar lessons.
- Pronunciation scoring.
- Social features (sharing, friends, leaderboards).
- Any backend / server; no user accounts or cloud sync.
- Multiple example sentences per word (exactly one).
- Bundled audio recordings (v1 is on-device TTS; schema keeps an *optional* audio-reference field for the future).
- Any push notification beyond the single optional daily reminder (FR-13).

From the design philosophy (deliberately excluded):

- Gamification of any kind: streaks, XP, levels, leaderboards, mascots, confetti, streak-guilt.
- Ads and subscriptions (monetization is one-time $0.99 per additional language only).
- Infinite content treadmill / dark patterns. The app has a deliberate ending (FR-11).
- Activity/engagement dashboards: time-spent tracking, review-count heatmaps, daily-streak chains. Progress stays outcome-focused only (FR-10, FR-17, FR-18).

Platform scope note: iPad-optimized layouts, macOS/Catalyst, and landscape are out of scope for v1 (NFR-9).

---

## 5. Key user flows

Short step sequences, not diagrams.

### 5.1 First launch
1. Learner opens the app for the first time.
2. Language selection shows French unlocked (FR-2) and other packs locked (FR-1).
3. Learner selects French; it becomes the active language.
4. First session starts with new words only (no reviews exist yet), capped at `N` (FR-3, FR-4).
5. Notifications are **not** requested; the daily reminder stays off until the learner enables it (FR-13).

### 5.2 A study session
1. Learner opens study for the active language.
2. App assembles due reviews + up to `N` new words (FR-3, FR-4). If none, it shows the caught-up state (FR-12).
3. A card appears showing the word and exactly one example sentence (FR-6); the answer is hidden (FR-5).
4. Learner optionally plays word/sentence audio (FR-7), attempts recall, then reveals.
5. Learner grades the attempt (`G`); the scheduler updates that word's next-review date (FR-8) and the result persists (FR-9).
6. Next card appears; repeat until the queue is empty, then the caught-up state (FR-12).
7. Progress reflects any newly learned words (FR-10).

### 5.3 Hitting the completion state
1. Over many sessions, the learner grades words until all 1000 in the active language meet `L`.
2. On the review that brings the last word to `L`, progress reads 1000 / 1000 (FR-10).
3. Entering study for that language now shows the completion screen instead of a new card (FR-11).
4. The learner takes whatever that screen offers (Phase 9 decides the options — e.g. review-only, or unlock another language).

### 5.4 Unlocking a second language
1. From language selection the learner picks a locked pack (FR-1).
2. The app offers the $0.99 one-time unlock (FR-14).
3. On successful purchase the pack unlocks and becomes selectable; on cancel/failure it stays locked with a clear message (FR-14).
4. The learner selects the now-unlocked language; its progress starts independently of any other language (FR-10).
5. On a later reinstall/new device, Restore re-grants the unlock with no new charge (FR-15).

---

## 6. Assumptions & deferred decisions

**Assumptions made here (flag if any are wrong):**

- **Baseline device** for NFR-2/NFR-3 targets ≈ iPhone SE (3rd gen) / iPhone 12 class; exact device fixed at Phase 13 measurement.
- **Audio is on-demand** via a control on the card; whether it also auto-plays on reveal is a Phase 8 UX detail, not a requirement.
- **Reminder** is a single repeating local notification at a user-chosen time, off by default; permission requested only on enable (FR-13).
- **Only network use** in the app is StoreKit purchase/restore (the Claude-API sentence generation is a build-time pipeline step, Phase 6, never in the shipped app).
- **"Caught up" allows no forced extra study** beyond due + `N` new; optional ahead-of-schedule practice is not required in v1 (can be revisited).
- **Default `N = 10`** new words/day, user-adjustable (from the pacing decision).
- **Progress trend is outcome-based** (FR-17): reconstructed from per-word milestone dates (`firstReviewedDate`, `learnedDate`), which assumes "learned" is a sticky milestone (settled with `L` in Phase 9). Study-activity/accuracy trends (review counts, time spent) are out of scope (§4) and would need an append-only review-event log — deferred (YAGNI).
- **"Hardest words"** (FR-18) ranks by SM-2 ease factor; an optional per-word `lapses` counter may be added in Phase 5 for a more intuitive signal — a single field, not an event log.

**Deferred to later phases (named as parameters above, not fixed here):**

- `L` — definition of "learned" (Phase 9).
- `G` — recall-grade scale, 4-level vs. binary (Phase 5).
- App name (Phase 4). *(Persistence settled in Phase 2 — [ADR-001](adr/ADR-001-persistence.md): SwiftData for progress, JSON for packs.)*
- What the completion screen offers (Phase 9, 2–3 options).
