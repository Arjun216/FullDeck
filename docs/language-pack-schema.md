# Language-Pack Data Contract & Schema

**Phase:** 3 (Data Contract) · **Status:** Draft for review · **Date:** 2026-07-13

This is the versioned, validated **interface** every language pack must satisfy. Its whole job is
to keep "add a language" a *content* task, not an *engineering* task (`CLAUDE.md`; proven in
Phase 12). The app reads packs generically; the Phase 6 Python pipeline emits them; both validate
against the same rules defined here. No app code lives in this phase.

Related decisions this builds on: [ADR-004](adr/ADR-004-language-pack-format.md) (JSON container,
manifest discovery, `Codable` loading), spec decisions **D2** (`wordfreq` source, CC-BY-SA 4.0),
**D3** (optional audio), **D4** (sentence frequency constraint), and requirements **FR-6** (one
example sentence), **FR-16** (attribution), **NFR-10** (never crash on bad data).

---

## 1. Container, discovery & loading (recap)

Fixed in ADR-004; restated so this contract stands alone:

- **One JSON file per language**, e.g. `fr.pack.json`, loaded via `Codable` behind the `PackStore` port.
- A bundled **`manifest.json`** lists available packs (`language_code`, `display name`, `filename`,
  `unlockedByDefault`) so language selection (FR-1) is fully data-driven — dropping in a new pack +
  manifest line makes it appear, no code change.
- Packs ship as **app-bundle resources**; updates ride app releases (no over-the-air packs in v1).
- The loader checks `schema_version` and returns a **typed error** on an unknown/newer version
  rather than silently misreading (§9, NFR-10).

---

## 2. Word entry

Each pack contains a `words` array of entries. One entry = one **lemma** (dictionary form), never
one per inflected spelling (§10).

| Field | Type | Req | Meaning |
|---|---|:--:|---|
| `id` | string | ✓ | Unique, opaque **review-state key**. Derived `{language_code}:{lemma}:{pos}`, e.g. `fr:chat:NOUN`. Policy in §8. |
| `lemma` | string | ✓ | Canonical dictionary form from the lemmatizer. Non-empty, NFC-normalized, trimmed. The linguistic key. |
| `display` | string | ✓ | Learner-facing form. May carry a per-language citation convention (e.g. noun + article, `le chat`). Non-empty. Not schema-constrained beyond that (§10). |
| `pos` | enum | ✓ | Universal POS tag. Allowed entry set in §3. |
| `rank` | integer | ✓ | Frequency rank, `1` = most frequent. `≥ 1`, unique within the pack. **Never** the `id`. |
| `register` | enum | ✓ | `casual` \| `neutral` \| `formal`. Advisory metadata only (§10). |
| `is_function_word` | boolean | ✓ | Content-vs-function flag. Must equal `pos ∈ CLOSED_CLASS` (§3). |
| `gloss` | string | – | Target-word meaning in the pack's `base_language` (e.g. English `cat`). Optional in the schema; **populated for French v1** (it is the card's recall answer until Phase 8 says otherwise). |
| `example` | string | ✓ | **Exactly one** sentence, containing the target word, obeying the constraint in §6. Non-empty. |
| `audio` | object | – | `{ "word"?: string, "sentence"?: string }` — asset references. **Absent in all v1 packs** (on-device TTS, D3). Present-but-unresolvable is a validation failure (§7). Exists so future recordings need no schema change. |
| `aliases` | string[] | – | Prior `id`s this entry supersedes, for cross-version review-state migration (§8). Empty/absent in v1. |

### Annotated example entry

```jsonc
{
  "id": "fr:chat:NOUN",       // opaque key; your saved progress hangs off this
  "lemma": "chat",            // dictionary form
  "display": "le chat",       // what the learner sees (French nouns shown with article)
  "pos": "NOUN",
  "rank": 4,                  // 4th most frequent word in this pack
  "register": "neutral",
  "is_function_word": false,  // a content word
  "gloss": "cat",             // meaning, in base_language (en)
  "example": "J'ai un chat.", // one sentence, obeys §6
  "aliases": []               // no prior ids
  // "audio" omitted — v1 speaks via TTS
}
```

---

## 3. Allowed parts of speech & the function-word class

POS uses the **Universal Dependencies** tag set (what spaCy emits).

**Valid as entries** — open-class `NOUN`, `VERB`, `ADJ`, `ADV`, `NUM`, `INTJ`; closed-class
`DET`, `ADP`, `PRON`, `AUX`, `CCONJ`, `SCONJ`, `PART`.

**Never valid as entries** — `PROPN` (proper nouns aren't taught vocabulary), `PUNCT`, `SYM`, `X`,
`SPACE`.

```
CLOSED_CLASS = { DET, ADP, PRON, AUX, CCONJ, SCONJ, PART }   // the "function words"
```

`is_function_word` must equal `pos ∈ CLOSED_CLASS`. (`NUM`, `INTJ` therefore count as content.)
This same `CLOSED_CLASS` set drives the constraint exemption in §6.

---

## 4. Pack metadata

Top-level fields alongside `words`.

| Field | Type | Req | Meaning |
|---|---|:--:|---|
| `schema_version` | integer | ✓ | Major version of *this contract*. Loader compatibility gate (§9). |
| `pack_version` | string | ✓ | Semver of *this pack's content* (`1.0.0`), independent of `schema_version`; tracks sentence regenerations / fixes. |
| `language_code` | string | ✓ | BCP-47 (`fr`, `hi`). Must match the manifest entry and every `id` prefix. |
| `language_name` | string | ✓ | Display name for the UI (`Français`). |
| `base_language` | string | cond. | Language the `gloss` values are written in (`en`). **Required if any entry has a `gloss`.** |
| `word_count` | integer | ✓ | Must equal the actual entry count; `= 1000` for a shippable pack (§7). |
| `source` | object | ✓ | Attribution + license. Carries the **wordfreq CC-BY-SA 4.0** requirement (§11, FR-16). |
| `generator` | object | – | Provenance `{ "tool"?, "model"?, "created"? }`. Cheap aid for debugging ID churn (§8) — records which build produced which ids. |

`source` shape:

```jsonc
"source": {
  "name": "wordfreq",
  "url": "https://github.com/rspeer/wordfreq",
  "license": "CC-BY-SA 4.0",
  "attribution": "Word-frequency data from the wordfreq project (Robyn Speer), licensed CC-BY-SA 4.0.",
  "notes": "ShareAlike covers the derived word-frequency list only; app code and generated example sentences are not derivative works of wordfreq."
}
```

---

## 5. Pack file shape

```jsonc
{
  "schema_version": 1,
  "pack_version": "1.0.0",
  "language_code": "fr",
  "language_name": "Français",
  "base_language": "en",
  "word_count": 1000,
  "source": { /* §4 */ },
  "generator": { "tool": "topwords-pipeline", "created": "2026-07-13" },
  "words": [ /* 1000 entries, §2 */ ]
}
```

---

## 6. The example-sentence frequency constraint (the core rule)

**Intent (spec D4):** every example sentence uses only words the learner has *already met* — words
more frequent than the sentence's target — so each sentence doubles as review and never contains a
word harder than the one being taught.

**Policy (this project's refinement): strict by default; class-based exemption is a narrow
fallback, never a licence for content words.** In practice function words cluster at the very top
of the frequency list, so "strictly more frequent + in-pack" *already* admits `le / de / être / à
/ et` for any target below ~rank 50 — the exemption only actually fires for the lowest-rank targets
and for rare glue.

This is a **formal, machine-checked rule**, not a guideline.

### 6.1 Algorithm (per sentence)

```
Given target entry T at rank r_T:

  tokens ← tokenize + lemmatize(sentence)         # spaCy
  drop PUNCT, SYM, SPACE tokens
  require: some token's lemma == T.lemma           # the sentence must contain the target

  lemma_rank(tok) = min( rank of pack entries sharing tok's lemma )   # ∞ if not in pack

  for each non-target token tok:
      if lemma_rank(tok) < r_T:        PASS  (strict — more frequent AND in-pack)
      elif pos(tok) ∈ CLOSED_CLASS
           or pos(tok) == PROPN:       EXEMPT (function word / proper noun rescue)
      else:                            HARD FAIL → pack invalid

  tier(sentence) = STRICT if no token needed EXEMPT, else RELAXED
```

- A **content** word (open-class) that is rarer than the target, or absent from the pack, can
  **never** be exempted → hard fail. That boundary is the non-negotiable core.
- The exemption only ever rescues a **function word or proper noun** that strictness couldn't place
  — matching "exempt by word class *only* where a strict sentence is impossible."
- **Homograph rule:** a sentence token's rank is the *minimum* rank among pack entries sharing its
  lemma (i.e. if the learner has met the lemma in any sense, it counts as met). `ponytail:` lemma-level
  min; tighten to POS-matched rank only if a language ever needs it.

### 6.2 Reporting (how "prefer strict" is enforced beyond the hard boundary)

A validator cannot judge "was a natural strict sentence *possible* here?" — that is a generation-time
call. So the split of responsibility is:

- **Pipeline (Phase 6)** generates under the strict tier and relaxes to an exemption only when it
  cannot otherwise form a natural sentence.
- **Validator (here)** enforces the hard boundary (content words never exempt) and **records each
  sentence's tier**, emitting a pack-level tally of RELAXED sentences and the exact tokens exempted.
  That tally feeds the D4 human spot-check gate. An optional, configurable warning fires if the
  RELAXED fraction is unexpectedly high — a **warning, never a validation failure**.

### 6.3 Worked examples (from the §12 fixture)

- `avoir` (rank 3, content) — *"J'ai été."* → `je`(1) PASS, `été→être`(2) PASS. No exemptions →
  **STRICT**.
- `chat` (rank 4, content) — *"J'ai un chat."* → `je`(1) PASS, `avoir`(3) PASS, `un` is `DET` →
  EXEMPT, `chat` = target. One exemption → **RELAXED**, valid.
- Counter-example (**invalid**): for target `je` (rank 1), *"Je suis un chat."* — `chat` is a
  `NOUN` (content) rarer than the target → **HARD FAIL**, no exemption possible.

---

## 7. Validation rules

A pack is **valid** iff every rule below holds. Two profiles:

- **Structural** — every pack, including test fixtures.
- **Shippable** — a real launch pack; adds the 1000-word rules on top of Structural.

### Structural profile

| ID | Rule |
|---|---|
| VR-1 | Parses as JSON and conforms to the JSON Schema (types, required fields, enum membership). |
| VR-2 | `word_count` equals the actual number of entries. |
| VR-3 | Every `id` is unique. |
| VR-4 | Every `id` equals its derivation `{language_code}:{lemma}:{pos}` (integrity check; see §8). |
| VR-5 | Every `rank` is `≥ 1` and unique within the pack. |
| VR-6 | Every `pos` is in the allowed **entry** set (§3) — no `PROPN/PUNCT/SYM/X/SPACE` entries. |
| VR-7 | `is_function_word` equals `pos ∈ CLOSED_CLASS` for every entry. |
| VR-8 | `register` ∈ `{casual, neutral, formal}`. |
| VR-9 | `lemma`, `display`, `example` are non-empty, NFC-normalized, trimmed. |
| VR-10 | Every `example` satisfies the §6 constraint (contains its target; no content word breaks strictness). |
| VR-11 | If an entry has `gloss`, the pack declares `base_language`. |
| VR-12 | Every present `audio.word` / `audio.sentence` reference resolves to an existing asset. |
| VR-13 | `aliases` values are globally unique and collide with no current `id`. |
| VR-14 | `source.license` and `source.attribution` are present and non-empty; a `wordfreq`-derived pack carries the CC-BY-SA 4.0 attribution (§11). |
| VR-15 | `schema_version` is present and `≤` the app/pipeline's max supported version (§9). |
| VR-16 | `language_code` is well-formed BCP-47 and matches the manifest entry and every `id` prefix. |

### Shippable profile (adds)

| ID | Rule |
|---|---|
| VR-17 | `word_count == 1000`. |
| VR-18 | `rank` values are exactly the set `{1 … 1000}` (contiguous, no gaps). |

Fixtures pass **Structural only** (VR-17/18 are waived — a fixture is intentionally tiny).

---

## 8. Word ID policy — *derived, not frozen*

`id = {language_code}:{lemma}:{pos}` (e.g. `fr:aller:VERB`). Human-readable, diffable, and
recomputed from the entry every build (VR-4). No ledger, no freeze-check CI — the deliberately
lazy choice.

**Accepted residual risk:** because the id is derived, a future pipeline change that re-normalizes a
lemma or re-tags a POS will *change that word's id*. Since saved review state (SwiftData) is keyed
on the id, the affected word's history orphans (that one word re-enters as "new"). Bounded (one word,
no crash, no other data touched), low-frequency (packs update only on app release), and explicitly
accepted for v1.

**Escape hatch (`aliases`):** if such a change ever happens, list the old id in the new entry's
`aliases`. On load, the review store remaps state from any alias to the current id, so history
survives without a schema change. Empty in v1; costs nothing to carry. The optional `generator`
metadata (§4) records the toolchain/model behind a pack's ids, so a churn event is diagnosable.

Upgrade path if churn ever proves common: freeze ids against the previously shipped pack in CI
(the old pack becomes the ledger). Not built now — `ponytail:` add when measured, not before.

---

## 9. Schema versioning policy

`schema_version` is a single integer, bumped only on **breaking** changes.

| Change | Bump? |
|---|---|
| Add a new **optional** field | No |
| Add a new **enum value** old packs don't use | No |
| Make an optional field required, remove/rename a field, change a field's type, or tighten a rule old packs would now fail | **Yes** |

**Loader contract (ADR-004, NFR-10):** the app declares the max `schema_version` it understands.

- pack `schema_version ≤ max` → load;
- pack `schema_version > max` (newer than the app), or a version the app has dropped → **typed
  error** `unsupportedSchemaVersion`, surfaced as a user-facing state. Never crash, never
  silently misread — **fail closed**.

Every breaking bump ships with a one-paragraph migration note in this doc's changelog.

---

## 10. Modeling tradeoffs (decisions that affect every future pack)

### Lemma vs. inflected forms — *pack is lemma-keyed*
One entry per dictionary form (`aller`), not per surface form (`vais/vas/allons`). Inflected forms
appear only *inside* example sentences and are resolved back to lemma-rank by the validator (§6).

- **Why:** a top-1000 *lemma* list is the meaningful learning unit; a top-1000 *surface-form* list
  would waste slots on inflections of the same word and fragment a learner's progress across
  spellings.
- **Cost — morphologically rich languages (Hindi, Phase 12):** many surface forms collapse onto one
  lemma, so pack quality depends on lemmatizer accuracy. A lemmatizer error either mis-keys an entry
  or wrongly merges two words. Mitigations already in the schema: `display` is decoupled from `lemma`
  so the citation form stays natural regardless of the key; `pos` disambiguates homographic lemmas
  (distinct ids `fr:être:AUX` vs a hypothetical `fr:être:NOUN`). This is the honest reason Hindi is
  the Phase 12 architecture test — the *format* holds, but each language is real pipeline work.

### Display form — *separate field, per-language convention*
`display` exists so "the word we teach" (`le chat`) needn't equal the linguistic key (`chat`). The
schema does not dictate the convention (article on nouns? infinitive marker on verbs?); each pipeline
picks one. Keeps morphology/orthography choices out of the contract.

### Register — *advisory, not enforced*
Tagged `casual/neutral/formal` but never gated on beyond enum membership (VR-8). A lemma's register
shifts with sense and context; forcing one tag is lossy, so we record the dominant register as a hint
(future UI/filtering) and never fail a pack over it. Sense-level register, if a language ever needs
it, is an additive change (§9).

---

## 11. Attribution & licensing

`wordfreq` data is **CC-BY-SA 4.0** (spec D2): commercial use permitted **with attribution**;
ShareAlike applies to the derived word-frequency list only — app code and LLM-generated sentences
are not derivative works of wordfreq and stay proprietary.

- Every wordfreq-derived pack carries the attribution in `source` (VR-14).
- The app surfaces it in an about/credits screen (FR-16).
- `source.notes` states the ShareAlike scope so the boundary is explicit in the data itself.

---

## 12. Example fixture (`fixtures/fr-mini.pack.json`)

A hand-authored 5-entry French pack — **illustrative, not pipeline output**; ranks are chosen to
demonstrate the rules, not claimed as real French frequencies. It is the fixture the Data-layer tests
already reference, and it deliberately exercises both constraint tiers, both exemption kinds (proper
noun + out-of-pack function word), and in-pack strict passes. Validates under the **Structural**
profile (VR-17/18 waived). It is the **positive control** for validator tests.

**Rejection fixtures (`fixtures/invalid/`):** the rules above are only trustworthy if the validator
*rejects* violations — an all-valid corpus can't tell a real validator from one that returns "valid"
unconditionally. So each rule class has a minimal pack that breaks exactly that rule, catalogued in
`fixtures/invalid/expected.json` (fixture → the VR it violates). Both validators consume this set:
the Phase 6 Python validator and the Phase 7 Swift loader must reject each one *for its specific
rule*. Coverage: VR-2, VR-3, VR-4, VR-5, VR-7, VR-10 (both branches — rarer content word and missing
target), VR-12, VR-14, VR-15. Not yet covered (documented in `expected.json`): VR-13 (packs ship
empty `aliases`), VR-16 (needs the pack manifest, Phase 4/7), VR-17/18 (waived for fixtures).

```jsonc
{
  "schema_version": 1,
  "pack_version": "0.1.0",
  "language_code": "fr",
  "language_name": "Français",
  "base_language": "en",
  "word_count": 5,
  "source": {
    "name": "hand-authored test fixture",
    "license": "CC0-1.0",
    "attribution": "Hand-authored fixture for TopWords tests; not derived from wordfreq.",
    "notes": "Ranks are illustrative, not real frequencies."
  },
  "words": [
    {
      "id": "fr:je:PRON", "lemma": "je", "display": "je", "pos": "PRON",
      "rank": 1, "register": "neutral", "is_function_word": true,
      "gloss": "I", "example": "Je suis Paul.", "aliases": []
      // RELAXED: être(AUX) exempt, Paul(PROPN) exempt
    },
    {
      "id": "fr:être:AUX", "lemma": "être", "display": "être", "pos": "AUX",
      "rank": 2, "register": "neutral", "is_function_word": true,
      "gloss": "to be", "example": "C'est Paul.", "aliases": []
      // RELAXED: ce(PRON) exempt, Paul(PROPN) exempt
    },
    {
      "id": "fr:avoir:VERB", "lemma": "avoir", "display": "avoir", "pos": "VERB",
      "rank": 3, "register": "neutral", "is_function_word": false,
      "gloss": "to have", "example": "J'ai été.", "aliases": []
      // STRICT: je(1) and été→être(2) both more frequent and in-pack; no exemption
    },
    {
      "id": "fr:chat:NOUN", "lemma": "chat", "display": "le chat", "pos": "NOUN",
      "rank": 4, "register": "neutral", "is_function_word": false,
      "gloss": "cat", "example": "J'ai un chat.", "aliases": []
      // RELAXED: je(1), avoir(3) strict; un(DET) exempt
    },
    {
      "id": "fr:noir:ADJ", "lemma": "noir", "display": "noir", "pos": "ADJ",
      "rank": 5, "register": "neutral", "is_function_word": false,
      "gloss": "black", "example": "J'ai un chat noir.", "aliases": []
      // RELAXED: je(1), avoir(3), chat(4) strict; un(DET) exempt
    }
  ]
}
```

---

## 13. Open items / deferred

- **Card "answer" (Phase 8):** `gloss` is provided as the recall answer for v1; Phase 8 may choose a
  different card interaction. If it does, `gloss` stays a harmless optional field.
- **Numbers (`NUM`) in sentences** are treated as content words (no exemption). If this proves too
  strict for natural sentences, exempting small numerals is an additive rule change — deferred (YAGNI).
- **POS-matched homograph ranking** (§6.1) — deferred behind the lemma-level-min rule until a language needs it.
- **Machine-readable JSON Schema** (`schema/language-pack.schema.json`) and the standalone fixture
  file are produced in this phase's implementation step, mirroring §2–§7 and §12 exactly.
