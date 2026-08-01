# packgen — the language-pack pipeline

Turns a language code into a schema-valid language pack: frequency-ranked lemmas from
[wordfreq](https://github.com/rspeer/wordfreq), one example sentence per word, validated against
every rule in [`docs/language-pack-schema.md`](../docs/language-pack-schema.md) §7 before it is
written out.

Adding a language is *running this*, not writing app code — measured across two languages, and
true: Hindi cost zero lines of app logic. Inside the pipeline the story is weaker than "a table
entry", and the second language is what showed it. See "Adding a language" below, and
[`docs/phase-12-verdict.md`](../docs/phase-12-verdict.md).

## Setup

```sh
brew install uv
uv sync --project pipeline
```

`uv` installs its own pinned Python 3.12 (spaCy has no 3.14 wheels), spaCy, wordfreq and the
French model — the model is a pinned wheel URL in `pyproject.toml`, so CI and your machine get the
same one.

## The stages

No API key, anywhere. Sentences come from Claude either through the **Claude Code CLI**
(`claude --print`, running on your existing subscription — the same mechanism as
`~/Projects/resume_pipeline/run.sh`) or by **pasting the prompts into claude.ai** by hand. Both
produce the same files, so you can mix them freely.

```sh
uv run packgen models hi     # pinned UDPipe model -> work/models/  (UDPipe languages only)
uv run packgen words fr      # wordfreq + spaCy   -> work/fr/candidates.json  (+ rejected.json)
uv run packgen prompts fr    # candidates         -> work/fr/prompts/NNN.md
uv run packgen generate fr   # prompts            -> work/fr/responses/NNN.json   [or paste by hand]
uv run packgen pack fr       # responses          -> packs/fr.pack.json       (validated)
uv run packgen validate <path>   # re-check any pack on demand
```

The whole thing, including the regeneration loop:

```sh
uv run packgen words fr && uv run packgen prompts fr && uv run packgen generate fr
until uv run packgen pack fr; do uv run packgen generate fr --retry || break; done
```

`generate` requires a logged-in `claude` CLI (`claude` → `/login` once). It is **resumable**: a
reply is only saved if it parses, and prompts that already have an answer are skipped — so an
interrupted run picks up where it stopped, and a re-run retries exactly the failures. Unusable
replies are kept as `NNN.json.bad` for inspection. Default model is `sonnet`; override with
`--model opus`.

**`words`** pulls ~3000 raw tokens for a 1200-lemma buffer above the 1000 the pack needs. wordfreq
returns *surface forms*, so this stage drops elision fragments (`l`, `d`, `qu`), non-alphabetic
junk and proper nouns, and collapses inflections onto their lemma (`est`/`sont`/`être` → one
entry at the best rank). Everything it drops is written to `rejected.json` with the reason.

**`prompts`** writes one prompt per batch of 50 words. Each prompt is self-contained: the target
words, the exact JSON return format, and the vocabulary the learner has already met — trimmed to
ranks at or above the batch, because offering a rarer word would be offering a §6 violation.

**`pack`** parses the replies (all-or-nothing per batch — a half-ingested batch is worse than a
re-ask), assembles the pack, and validates it. On failure it writes `work/fr/retry/NNN.md`,
batched like the first pass and quoting the rule that rejected each word, plus `targets.json`
recording which ranks each prompt covers. `generate --retry` answers those and splits the reply
into `work/fr/retry/answers/RRRR.json`, one file per rank — so an answer outlives the next round's
re-batching, and supersedes the batch answer for its word. The loop converges without regenerating
anything that already passed, and stops on its own once a round changes nothing.

The prompts also ask Claude to **correct** the lemma and POS, because tagging a bare word out of
context is unreliable — spaCy proposes `traval`/ADJ for *travaux* and `priver`/ADJ for *privé*.
The corrected values are what derive the entry `id` and `is_function_word`, and retry prompts
offer *those* as the learned vocabulary rather than the tagger's originals: `candidates.json`
still says `luire` where the word is `lui`, and offering that invites a sentence the pack cannot
satisfy.

## Documented §6 exceptions

At the very top of a frequency list the constraint can be genuinely unsatisfiable. `se` is the
25th most common French word, and every verb ranked above it is an auxiliary (`être` 5, `avoir` 9)
— a French reflexive needs a lexical verb, and the first is `faire` at 35. No valid sentence
exists, at any level of effort.

`work/<lang>/exceptions.json` maps an entry id to why §6 is waived for it:

```json
{ "fr:se:PRON": "no lexical verb ranked above it; 'Ça se fait.' misses by ten ranks" }
```

It is hand-authored and committed, because an exemption deserves a record and a reviewer. Only
**VR-10** can be waived — ids, ranks, duplicate detection and attribution are mechanical, and a
pack that breaks one of those is wrong rather than awkward. A waived violation is printed on every
`pack` run and listed by `validate --exceptions`, so it never goes quiet.

## Prompt size

The vocabulary list is most of a prompt, so it is split by how much the reader has to know about
each word. Everything ranked above the batch's first target is usable by every target in it, so
it is listed bare — no rank, no POS. Only the batch's own range is numbered, because there a word
is usable by some targets and not others. Retries are batched for the same reason: one prompt per
failing word re-sent the whole vocabulary 26 times over.

The *harness* around the prompt turned out to cost more than the prompt. A plain `claude --print`
ships this repo's `CLAUDE.md`, every skill, plugin, hook and MCP server, and the full built-in tool
schemas — ~38k prompt tokens per batch, measured, against ~2.4k for the average prompt itself. The
task fires no tool and needs no repo context, so `generate` passes `--safe-mode --tools ""`, which
measures ~5.3k instead. Note `--bare` looks like the same idea but is not usable here: it reads
auth strictly from `ANTHROPIC_API_KEY`, and this pipeline runs on the subscription precisely so no
key lives in this repo.

## Tests

```sh
uv run --project pipeline pytest        # includes the validator coverage floor
uv run --project pipeline ruff check .
```

The validator is built test-first against `fixtures/invalid/`: every rule has a fixture that
breaks exactly it, and the test asserts *which* rule fired (`fixtures/invalid/expected.json` is
the table). `fixtures/fr-mini.pack.json` is the positive control. `--cov-fail-under=95` covers the
validator and rule modules only — the IO-heavy stages have no coverage floor, since a percentage
there just invites tests written for the number.

Rule tests run against a fake analyzer with a fixed lexicon so they stay fast and deterministic;
`test_spacy_integration.py` separately proves the real French model agrees about `été → être`.

## Adding a language

**Step 0 decides how much work the rest is: does a POS-tagging model exist for the language?**
spaCy covers French. It publishes no Hindi pipeline with a tagger at all, so Hindi needed
`UDPipeAnalyzer` — a second backend class, not a table row. Check before promising anyone a
timeline.

1. **The model.** spaCy: a pinned wheel in `pyproject.toml` plus `SpacyAnalyzer.MODELS[code]`.
   UDPipe: a `RemoteModel` in `UDPipeAnalyzer.MODELS[code]` with its URL and SHA-256, fetched
   with `uv run packgen models <code>`. Neither exists for your language? That is a new backend
   implementing the `Analyzer` protocol, and it is the real cost.
2. `ANALYZERS[code]` — which backend the language uses. One row.
3. `LANGUAGE_RULES[code]` — the cleaning knobs (real one-letter words, elision suffixes). Start
   empty and read `rejected.json` to see what the language actually needs. Hindi found two
   script-level surprises there; both were invisible until that file was read.
4. `LANGUAGE_NAMES[code]` — the display name.
5. `LEMMA_NORMALIZERS[code]` — **only if** the tagger's lemma convention differs from the
   dictionary's. Tag one inflected sentence and read the lemmas: UD Hindi returns the bare verb
   stem `कर` where the pack cites the infinitive `करना`, and §6 compares those as strings. Left
   unreconciled it cost 333 violations on a 1000-word pack. French needs none of this, because
   spaCy's French lemma already is the infinitive.
6. Run the stages.

The measured cost of the second language is in
[`docs/phase-12-verdict.md`](../docs/phase-12-verdict.md): zero lines of app logic, one new
backend class in the pipeline, nine documented §6 waivers.
