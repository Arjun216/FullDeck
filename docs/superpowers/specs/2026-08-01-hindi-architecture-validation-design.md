# Hindi — Second Language & Architecture Validation

**Phase:** 12 (reordered ahead of Phase 11 on 2026-08-01)
**Date:** 2026-08-01
**Requirements:** FR-1 (multiple packs, lock state), ADR-004 (adding a language is
adding a data pack)
**Status:** approved; planned in
`docs/superpowers/plans/2026-08-01-hindi-architecture-validation.md`

> **Amended 2026-08-01, after the pre-plan spike.** Writing the plan meant running the
> model over the whole word list rather than the top 15, and three things changed:
>
> - **Two blockers this spec does not mention.** `words.py` rejects almost every
>   Devanagari word as `non-alphabetic` — matras and virama are Unicode *marks*, not
>   letters, so 293 of the top 3000 forms survive today against 2968 with the fix — and
>   UDPipe's `Pipeline` **segfaults** if its `Model` is garbage-collected. Both are
>   handled in the plan; neither was visible from the top-15 sample.
> - **Decision 4's premise is wrong.** "Hindi's head-of-list looks worse" was reasoned
>   from the top 15 forms. At n=100 the two languages are the same: French 56/100
>   closed-class, Hindi 57/100. Keep the machinery — run §6, count the waivers, treat
>   the count as a finding — but expect a French-scale handful, not tens.
> - **Pool size is fine.** A full simulation of the `words` stage yields 1842 candidates
>   from `--pool 3000`, against the 1200 the stage wants.

## What this builds

A real Hindi pack, generated through the existing pipeline, and an honest answer to
the question the phase exists for: **does adding a language actually cost zero app
code?**

The answer is measured, not asserted. Three numbers at the end (Decision 5).

## The blocker this phase starts from

The pipeline reads as though Hindi already works. `LANGUAGE_RULES` has an `"hi"`
entry and `SpacyAnalyzer.MODELS` maps `"hi"` to `xx_sent_ud_sm`. Both are traps:

- `xx-sent-ud-sm` is **absent from `pipeline/pyproject.toml`**, so `packgen words hi`
  fails on the "not installed" path before doing anything.
- `xx_sent_ud_sm` is a **sentence segmenter**. It has no POS tagger and no
  lemmatizer, while `words.py:82` reads `token.lemma_` and `token.pos_` off it.
  `pos` comes back empty, `words.py:83` rejects on `pos not in ENTRY_POS`, and
  **every single form is dropped**. Not a degraded pack — an empty one.

spaCy publishes no Hindi pipeline with POS at all, so this is a real gap rather than
a missing install.

## Decision 1 — UDPipe supplies Hindi lemma and POS

Add `ufal.udpipe` with the `hindi-hdtb-ud-2.5-191206` model.

### Why not stanza

Stanza scores higher on UD benchmarks and would also work. It pulls PyTorch into a
pipeline CI job that currently installs in about 70 seconds. That accuracy is not
worth buying here, for the reason in the next paragraph.

### Why tagger accuracy matters less than it looks

**No tagger is good at isolated words**, which is the only thing this pipeline asks
one to do. French uses `fr_core_news_md` — the `_md` model, chosen precisely because
`_sm` was not good enough — and *still* needs Claude to correct it (`traval`/ADJ for
*travaux*, `priver`/ADJ for *privé*). The prompts already ask Claude to correct lemma
and POS, and the corrected values are what derive the entry `id` and
`is_function_word`.

So the tagger's job is to get the candidate list *built* — plausible lemma, a POS
inside `ENTRY_POS` so the form is not dropped, and dedup of inflections. Claude
supplies the final quality either way. Buying PyTorch for a first pass that gets
overwritten is not a good trade.

### Verified, not assumed

Spiked on 2026-08-01 before this was written: `ufal.udpipe` installs on ARM macOS,
the model loads, and tagging the top 15 Hindi forms from `wordfreq.top_n_list('hi')`
gives:

| form | lemma | UPOS | assessment |
|---|---|---|---|
| के, में, को, ने | — | ADP | correct |
| है, हैं | है | AUX | correct |
| और | और | CCONJ | correct |
| भी, तो, नहीं | — | PART | correct |
| एक | एक | NUM | correct |
| की | का | VERB | wrong in the common reading (genitive marker, ADP) — but *is* also the perfective of करना |
| से | से | PART | should be ADP |
| पर | पर | CCONJ | ADP "on"; also "but" — genuinely ambiguous alone |

11 of 15 clean, and **all 15 land inside `ENTRY_POS`, so none are dropped.** Every
error is the isolated-word ambiguity class Claude already corrects for French. This
is the evidence the decision rests on.

## Decision 2 — the analyzer becomes a table, not a branch

`analyze.py` already declares an `Analyzer` protocol (`analyze(sentence) ->
list[Token]`) and the tests already have a `FakeAnalyzer`. `UDPipeAnalyzer`
implements the same protocol, so nothing downstream changes.

`cli.py` currently hardcodes `SpacyAnalyzer(lang)` in two places — `cmd_pack`
(`cli.py:274`) and `cmd_validate` (`cli.py:326` region). Both become
`make_analyzer(lang)`, backed by one table:

```python
ANALYZERS = {"fr": SpacyAnalyzer, "hi": UDPipeAnalyzer}
```

Adding a language stays a table entry. Adding a *new kind of NLP backend* is a class
— which happens once per backend, not once per language.

## Decision 3 — model distribution

The French model is a pinned wheel URL in `pyproject.toml`. UDPipe models are not
distributed as wheels, so they cannot be handled the same way.

A `packgen models <lang>` command downloads the pinned URL into `work/models/` and
verifies a SHA-256 before use.

| Field | Value |
|---|---|
| URL | `https://raw.githubusercontent.com/jwijffels/udpipe.models.ud.2.5/master/inst/udpipe-ud-2.5-191206/hindi-hdtb-ud-2.5-191206.udpipe` |
| Size | 25,857,814 bytes |
| SHA-256 | `d7a77399e6eccee9103d8df9b441ec25ba6ba9f4db453eed3f4ddb77acdd7f2a` |

**The 25 MB model is not committed to git.** Real-tagging tests skip when the model
is absent — the same shape as today's spaCy integration tests, which run because
their model is a pinned dependency. CI downloads it once and caches it on the
`models/` path.

The checksum is the point: a `raw.githubusercontent.com` URL on a third-party
mirror's `master` branch is a moving target, and a silently changed model would
change pack contents with no other signal.

## Decision 4 — §6 is the real risk, and its count is a finding

§6 requires every example sentence to use only words *more frequent* than its target.
French needed exactly one documented waiver: `se` is the 25th most common French
word and every verb above it is an auxiliary, so no valid sentence exists at any
level of effort.

**Hindi's head-of-list looks worse.** Of the 15 most frequent forms, fourteen are
function words — ADP, AUX, PART, CCONJ — and only एक (NUM) is not. A language whose
frequency list opens with that many closed-class items has a much smaller pool of
legal sentence material at the top.

The waiver machinery already exists (`_load_exceptions`, `report.waived`, and the
`§6 waived:` output in `cmd_validate`), so no new mechanism is needed.

**The plan is to run it and count.** The waiver count is treated as a *result*, not
as bookkeeping:

- **Comparable to French (a handful).** Document them the way `se` is documented and
  move on.
- **Large (tens of words).** That is a finding about the *rule*, not about Hindi.
  Stop and bring back a proposed relaxation — most likely allowing closed-class words
  from the same rank band, since a postposition is not "vocabulary" a learner is
  being asked to acquire in the way a noun is.

**Do not silently waive dozens of words to make the pack pass.** A validator that
waives everything is a validator that checks nothing.

## Decision 5 — the verdict is three measured numbers

This phase exists to test ADR-004: *adding a language means adding a data pack, never
writing new app code.* The verdict is not a paragraph of confidence; it is:

1. **Lines of app code changed** (`FullDeck/`, `Packages/`). Expected: **0**, apart
   from deleting the `comingSoon` constant from `LanguageSelectionView`, which is
   removal of a placeholder rather than support for a language.
2. **Lines of pipeline code changed.** Expected: one `UDPipeAnalyzer` class, one
   `ANALYZERS` table row, one `models` command, one `LANGUAGE_RULES` entry.
3. **§6 waiver count**, per Decision 4.

ADR-004 claims only the app layer. If (1) is zero and (2) is a new backend class,
ADR-004 holds as written — and the honest qualification to record is that the
*pipeline's* per-language story is weaker than the app's: it is "a table entry
**provided a UD model exists for your language**," which is a real precondition and
is not what the pipeline README currently implies.

## Scope

**In:** the tagger and its model plumbing, the full 1000-word Hindi pack, adding it
to `manifest.json` with `unlocked_by_default: false`, deleting the `comingSoon`
constant, the written verdict.

**Out:** Phase 11 monetization (still shelved —
`docs/superpowers/specs/2026-08-01-storekit-monetization-design.md`). Hindi remains
locked and unpurchasable when this phase ends; that is expected, and Phase 11
unshelves immediately after.

**Note on the locked-but-unbuyable state:** between this phase and Phase 11, Hindi
shows as locked with no way to unlock it. `LanguageSelectionViewModel.select`
already refuses locked packs (FR-1), so this is safe, but it is a worse user-facing
state than "coming soon" — the two phases should land close together.

## Risks

| Risk | Handling |
|---|---|
| §6 unsatisfiable for many Hindi words | Decision 4: count is a finding; stop and propose a rule change rather than mass-waiving |
| UDPipe mis-tags ambiguous forms (की, से, पर) | Claude's existing correction step, same as French. Spot-check the corrections on the real run |
| Third-party model URL changes or disappears | SHA-256 pinned in Decision 3; a changed model fails loudly rather than silently altering the pack |
| PyTorch-free choice proves too weak | Measured, not assumed — if Claude's correction rate on Hindi is far worse than French, revisit stanza with real numbers |
| Generation cost | `packgen generate` runs on the Claude Code CLI subscription, 20 batches of 50, resumable — an interrupted run resumes rather than restarting |

## Sources

- [UD_Hindi-HDTB](https://universaldependencies.org/treebanks/hi_hdtb/index.html) —
  16 of 17 UPOS tags, covering every tag in `CLOSED_CLASS` and `OPEN_CLASS`.
- [UDPipe 1 models](https://ufal.mff.cuni.cz/udpipe/1/models)
- [Universal Dependencies 2.5 Models for UDPipe](https://lindat.mff.cuni.cz/repository/xmlui/handle/11234/1-3131)
- [Stanza available models](https://stanfordnlp.github.io/stanza/available_models.html) —
  the rejected alternative.
