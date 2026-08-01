# Phase 12 verdict — does a second language cost app code?

**Date:** 2026-08-01
**Claim under test:** ADR-004 — *adding a language means adding a data pack, never
writing new app code.*
**Method:** build a real 1000-word Hindi pack through the existing pipeline and
measure what had to change. Not a paragraph of confidence; three numbers.

## 1. App code changed

**One file, +6 / −29 — and all six insertions are comment lines.**

```
FullDeck/FullDeck/Views/LanguageSelectionView.swift | 35 ++++------------------
1 file changed, 6 insertions(+), 29 deletions(-)
```

Of that:

- **29 deletions** remove the `comingSoon` placeholder the real pack replaces. That is
  removal of a stand-in, not support for a language.
- **1 behavioural line** deleted: `.disabled(!option.isUnlocked)`. See §4 — it is a
  pre-existing bug Hindi exposed rather than caused.
- Everything else is the comment explaining that deletion.

Nothing in `Packages/Domain`, nothing in `Packages/Data`, no new ViewModel, no new
view, no branch on `"hi"` anywhere. Lock state was already read from the manifest;
`select()` already refused a locked pack.

**Verdict for the app layer: ADR-004 holds as written.** Hindi arrived as a pack file
and a manifest row.

## 2. Pipeline code changed

**Three source files, +262 / −15.**

```
pipeline/src/packgen/analyze.py | 207 +++++++++++++++++++++++++++-
pipeline/src/packgen/cli.py     |  32 ++++-
pipeline/src/packgen/words.py   |  38 +++++-
```

That is: one new backend class (`UDPipeAnalyzer`), one `ANALYZERS` table, one
`packgen models` command, one lemma-convention reconciler, and two correctness fixes.

**This is where the honest qualification lives.** The README said adding a language
was four table entries. It is four table entries *provided a POS-tagging model exists
for your language* — and for Hindi, none did. spaCy publishes no Hindi pipeline with a
tagger at all, so the second language needed a second NLP backend before any table
entry meant anything.

Adding a *language* is a row. Adding a *kind of backend* is a class. Which one you are
doing is not your choice; it depends on what the NLP ecosystem happens to ship.

## 3. §6 waiver count

**Nine**, against French's one — and they are a different kind of exception.

French waived `fr:se:PRON` because §6 was genuinely **unsatisfiable**: no valid
sentence exists at any level of effort. None of Hindi's nine is unsatisfiable. They are
**unverifiable**: every sentence is correct Hindi that genuinely uses its target word,
and UDPipe simply cannot report a lemma matching the pack's headword.

| Words | Cause |
|---|---|
| `जुड़ना` `बढ़ना` `लड़ना` | The tagger deletes the nukta (U+093C) from the lemma while keeping it in the surface form, so `जुड़े` lemmatizes to `जुड` |
| `तोड़ना` `रहना` | The tokenizer drops the imperative from its output entirely, leaving nothing to match |
| `करवाना` | The causative collapses to its base `कर` |
| `लगना` | Shares its perfective form with `लगाना`, a different verb |
| `तू` `तुम्हारा` | Oblique and feminine forms that never reduce to the citation form |

Each is documented individually in `pipeline/work/hi/exceptions.json` and printed on
every `pack` run, so none goes quiet. The regeneration loop ran 333 → 55 → 11 → 9 and
then stopped itself, which is the stop rule working as designed.

**Nine is 0.9% of the pack.** It is not the "tens of words" that would have meant the
*rule* was wrong — §6 is fine. The tagger is the weak link, which is a different
problem with a different fix.

## 4. Three findings that were not in the spec

These are the ones the next language will hit too, and none was visible from the
15-word sample the design was written against.

**The candidate cleaner was Latin-script-specific.** `words.py` required every
character to satisfy `str.isalpha()`. Devanagari writes its vowels as combining *marks*
(`ा` is Mc, `्` is Mn), and `isalpha()` is `False` for those — so the rule threw away
**2707 of Hindi's top 3000 forms** before any tagger saw them, including `के`, the
single most frequent word in the language. Measured: **293 forms survived the old rule,
2968 survive the fix.** Fixed in the shared function, not behind a per-language knob:
it is a Unicode correctness bug, and decomposed Latin has the same shape.

**The tagger and the dictionary disagreed about what a lemma is.** UD Hindi lemmatizes
verbs to the bare stem (`कर`); dictionaries — and therefore the pack, and therefore
Claude's corrected lemma — cite the infinitive (`करना`). §6 compares those as strings.
So `"राम यह करता है।"` read as a sentence that did not contain `करना` **and** that used
`कर`, a word ranked nowhere in the pack: two failure classes, one cause. Reconciling
the conventions in the Hindi analyzer took the pack from **333 violations to 55**, and
let no new word into any sentence. French never hit this because spaCy's French lemma
already *is* the infinitive. The pipeline had silently assumed the two always agree.

**`.disabled()` fails WCAG on a warm background.** SwiftUI dims a disabled row. Measured
on the simulator, the locked `हिन्दी` label rendered at **3.33:1** against `AppBackground`
— under the 4.5:1 AA floor — while `Français` sat at 16.86:1. This was latent from
Phase 8: any locked pack would have hit it, and French is never locked, so nothing ever
did. The automated audit caught it the first time a locked row existed. Dropping
`.disabled()` restores 16.86:1; FR-1 is enforced in `select()`, where it belongs.

**A fourth, smaller one:** `suspicious_lemmas` flags `चाहना`, `चुकना` and `फैलना` —
all real verbs. It asks wordfreq how common the lemma is, and Hindi corpora carry
inflected forms rather than infinitives, so citation forms look rare. The check is
Latin-tuned too. It is a report, never a gate, so it was left alone.

## 5. What the next language needs

1. **A POS-tagging model.** Check this *first* — it decides whether the rest is a
   table row or a new backend class. spaCy for the languages it covers; UDPipe's UD 2.5
   models otherwise.
2. `ANALYZERS[code]` — which backend.
3. The model itself: a pinned wheel in `pyproject.toml` (spaCy) or a `RemoteModel`
   entry plus `packgen models <code>` (UDPipe).
4. `LANGUAGE_RULES[code]` — cleaning knobs. Start empty.
5. `LANGUAGE_NAMES[code]` — the display name.
6. `LEMMA_NORMALIZERS[code]` — **only if** the tagger's lemma convention differs from
   the dictionary's. Check by tagging one inflected sentence and reading the lemmas.
7. A manifest row in the app, and the pack file. Nothing else.
8. **Read `rejected.json` before trusting the candidate list.** Both script-level
   surprises this phase produced showed up there first.

## 6. Residual risk

- The nukta class (§3) will recur for every Devanagari language, and for any tagger
  that normalizes diacritics away. The durable fix is a nukta-insensitive lemma
  comparison in the validator; it was weighed and deferred, because it touches the
  gated, rejection-tested module to accommodate one tagger's lossy output, and nine
  documented waivers are cheaper and more honest than a validator that quietly matches
  more than it should.
- Hindi is **locked with no way to unlock it** until Phase 11 lands. `select()` refuses
  locked packs, so it is safe, but it is a worse user-facing state than "coming soon".
  The two phases should land close together.
- The pack has had a spot-check, not a full human read. 1000 sentences of generated
  Hindi are a Phase 13 review item.
