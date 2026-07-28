# Phase 10 — Manual Verification & Decisions

## NFR-1 — Offline-first

Code audit:

```sh
grep -rn "URLSession\|URLRequest\|\.dataTask\|http://\|https://\|NWConnection" \
  FullDeck/FullDeck Packages/Domain/Sources Packages/Data/Sources
```

One match: `FullDeck/FullDeck/Resources/packs/fr.pack.json:10`, the pack's own
`source.url` attribution field (`https://github.com/rspeer/wordfreq`) — a string
in bundled data describing where the word-frequency data came from, not code
that makes a request. There is no networking code anywhere in the app target or
the Domain/Data packages — NFR-1 holds by construction, not by a runtime check
that could regress silently. The only feature that will ever touch the network
is Phase 11's StoreKit purchase/restore flow, which doesn't exist yet.

`AVSpeechSynthesizer` (on-device TTS, spec decision D3) has no documented
network fallback for on-device system voices — confirmed against Apple's
documentation, not just assumed.

**Manual confirmation (Arjun, on a device):**
- [ ] Enable Airplane Mode.
- [ ] Launch FullDeck, select a language, complete one full study session
      (reveal + grade every card until caught-up or complete).
- [ ] Confirm no error state appeared and the session's grades are still
      there after backgrounding and reopening.

## NFR-4/NFR-5/NFR-6 — Manual accessibility walkthrough

The automated audit (`FullDeckUITests.testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens`)
catches missing labels, contrast, and Dynamic-Type clipping mechanically —
it runs in CI on every push. It found and fixed several real issues while it
was being written (see the commit that added it): default Button/List-row
styling tinting several labels below the WCAG AA contrast threshold, three
`.secondary`-at-small-size contrast failures, and one Dynamic-Type clipping
risk on the card's position readout. What the audit *can't* judge is whether
a label is *meaningful* rather than merely present — that needs a human.

**VoiceOver walkthrough (Arjun, on a device or Simulator with VoiceOver on —
Settings → Accessibility → VoiceOver):**
- [ ] Languages tab: swipe through the list; each row announces its language
      name and lock/active state.
- [ ] Study tab: swipe through a card — word, part of speech, "Hear the
      word" — reveal it, swipe through the gloss, example sentence, "Hear
      the sentence," grade buttons, each announcing what it does.
- [ ] Progress tab: the learned/total readout announces as one combined
      phrase.
- [ ] Complete an entire study session using only VoiceOver gestures, no
      sighted assistance.

**Dynamic Type walkthrough** (Settings → Accessibility → Display & Text
Size → Larger Text → largest slider position, i.e. AX5):
- [ ] Languages, Study, and Progress tabs each render with no truncated,
      clipped, or overlapping text.

## NFR-7/NFR-8 — Observability decision

**Decision: no analytics, no crash reporting, no usage telemetry of any
kind. Local-only, by design, not a placeholder for "add it later."**

Rationale: `CLAUDE.md`'s design philosophy rejects "engagement/retention
theater," and NFR-8 already forbids third-party trackers, IDFA, and ad
networks outright. The app's only persisted data is what the product itself
needs to function (`ReviewState` — ease factor, interval, dates — via
`SwiftDataReviewStore`), already covered by NFR-7's local-only-storage
guarantee. Adding *any* collection layer — even first-party, even
aggregate-only — would be new surface area serving no v1 feature, in direct
tension with "does this help someone learn the 1000 words, or is it
engagement theater."

If a future need arises (e.g. diagnosing a crash reported by a user), the
bar is: local-only, on-device, no per-user identifier, no event stream — an
aggregate on-device log the user can inspect and clear themselves, never
anything transmitted. That bar is not met today, so nothing is implemented.

## NFR-12 — UI localization

Delivered in a later task of this phase: a `Localizable.xcstrings` String
Catalog with English (source) and Spanish translations for every UI-chrome
string, proven by an XCUITest that launches the app with the Spanish locale
and asserts translated text renders.
