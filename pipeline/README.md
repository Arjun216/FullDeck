# packgen — the language-pack pipeline

Turns a language code into a schema-valid language pack: frequency-ranked lemmas from
[wordfreq](https://github.com/rspeer/wordfreq), one example sentence per word, validated against
every rule in [`docs/language-pack-schema.md`](../docs/language-pack-schema.md) §7 before it is
written out.

Adding a language should be *running this*, not writing app code. The per-language knobs are a
table entry (`LANGUAGE_RULES` in `words.py`, `SpacyAnalyzer.MODELS`, `LANGUAGE_NAMES`); everything
else is language-agnostic.

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
re-ask), assembles the pack, and validates it. On failure it writes `work/fr/retry/NNNN.md`: one
prompt per failing word, quoting the rule that rejected it. `generate --retry` answers those, and
a retry answer supersedes the batch answer for its word — so the loop converges without
regenerating anything that already passed.

The prompts also ask Claude to **correct** the lemma and POS, because tagging a bare word out of
context is unreliable — spaCy proposes `traval`/ADJ for *travaux* and `priver`/ADJ for *privé*.
The corrected values are what derive the entry `id` and `is_function_word`.

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

1. `SpacyAnalyzer.MODELS[code]` — the spaCy model, added as a pinned wheel in `pyproject.toml`.
2. `LANGUAGE_RULES[code]` — the cleaning knobs (real one-letter words, elision suffixes). Start
   empty and read `rejected.json` to see what the language actually needs.
3. `LANGUAGE_NAMES[code]` — the display name.
4. Run the four stages.

Hindi is Phase 12, and is expected to need more work at step 2 than French did — weaker NLP
tooling and richer morphology is exactly why it was chosen as the architecture test.
