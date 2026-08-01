# Hindi — Second Language & Architecture Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a real 1000-word Hindi pack generated through the existing pipeline, and answer — with three measured numbers — whether adding a language costs zero app code (ADR-004).

**Architecture:** The pipeline's NLP seam already is a Protocol (`Analyzer`). Hindi adds a second implementation of it (`UDPipeAnalyzer`) behind a language→backend table, plus a `packgen models` command to fetch the model UDPipe does not distribute as a wheel. `words.py` stops speaking spaCy's `nlp.pipe` shape and speaks the Protocol instead, so both the `words` stage and the validator resolve their backend the same way. The app gets one manifest row and one pack file — no new app code.

**Tech Stack:** Python 3.12 + uv, `ufal.udpipe` 1.4.0.1, UDPipe UD 2.5 `hindi-hdtb` model, pytest, ruff. Swift 6 / SwiftUI on the app side (manifest + resource only).

## Global Constraints

- **Python:** `requires-python = ">=3.12,<3.13"` — unchanged. `ufal.udpipe` 1.4.0.1 publishes a `cp312` manylinux x86_64 wheel, so the Linux CI job needs no compiler.
- **Ruff:** `line-length = 100`, lint select `["E", "F", "I", "UP", "B", "SIM"]`. `ruff format --check .` is gated.
- **Coverage floor:** `--cov=packgen.validate --cov=packgen.rules --cov-fail-under=95`. New code in `analyze.py` / `cli.py` / `words.py` is outside the floor; do not lower it.
- **UDPipe model, pinned exactly:**
  - filename `hindi-hdtb-ud-2.5-191206.udpipe`
  - URL `https://raw.githubusercontent.com/jwijffels/udpipe.models.ud.2.5/master/inst/udpipe-ud-2.5-191206/hindi-hdtb-ud-2.5-191206.udpipe`
  - SHA-256 `d7a77399e6eccee9103d8df9b441ec25ba6ba9f4db453eed3f4ddb77acdd7f2a`
  - size 25,857,814 bytes — **never committed to git.**
- **Analyzer table:** `ANALYZERS = {"fr": SpacyAnalyzer, "hi": UDPipeAnalyzer}`.
- **Manifest entry for Hindi:** `"language_code": "hi"`, `"display_name": "हिन्दी"`, `"filename": "hi.pack.json"`, `"unlocked_by_default": false`.
- **Test naming:** every test display name starts with its requirement ID (`FR-6`, `NFR-10`, …).
- **Test determinism:** no `Date()`, no sleeps, no unseeded randomness.
- **§6 waivers:** only VR-10 may be waived, only via a committed `work/hi/exceptions.json` entry with a written reason. **Do not mass-waive to make the pack pass** (see Task 7's stop rule).

---

## Findings from the pre-plan spike (read before Task 1)

These were measured on 2026-08-01 by running the real model, and two of them are **not** in the spec:

1. **UDPipe's `Pipeline` holds a raw C pointer to the `Model`, not a Python reference.** If the `Model` object is garbage-collected, the next `process()` call **segfaults the interpreter** — exit 139, no exception, no traceback. Reproduced deliberately. Task 3 keeps the model alive on `self` and has a regression test.
2. **`words.py` currently rejects almost every Hindi word as `non-alphabetic`.** Devanagari vowel signs (`ा`), virama (`्`) and anusvara (`ं`) are Unicode *marks* (categories `Mc`/`Mn`), not letters, so `str.isalpha()` is `False` for them. Even `के`, the single most frequent Hindi word, fails. Measured over `top_n_list('hi', 3000)`: **293 forms pass today, 2968 pass once marks are allowed.** Task 2 fixes this.
3. **No script filter is needed.** wordfreq's Hindi list carries 80 Latin-script forms (`the`, `of`, `news`). The Hindi model tags every one of them `PROPN`, which the existing `ENTRY_POS` gate already drops. Verified, not assumed — do not add a per-language script knob.
4. **`--pool 3000` is enough.** A full simulation of the `words` stage over the top 3000 Hindi forms yields **1842 candidates** against the 1200 the stage wants. Rejections: `duplicate` 546, `pos:PROPN` 540, `non-alphabetic` 32, `elision-fragment` 30, `pos:X` 10.
5. **The spec's §6 alarm is overstated.** Decision 4 reasoned from the top *15* forms (14 closed-class) that Hindi has far less legal sentence material than French. At n=100 the two languages are the same: **French 56/100 closed-class, Hindi 57/100.** Keep Decision 4's machinery — count the waivers, treat the count as a finding — but expect a French-like handful, not tens.

---

## Task 1: `build_candidates` speaks the Analyzer protocol

`words.py` takes a spaCy-shaped `nlp` and calls `nlp.pipe(forms)`. UDPipe has no `.pipe`. Rather than teach `UDPipeAnalyzer` to imitate spaCy, the stage moves onto the `Analyzer` Protocol that already exists — one seam for both the `words` stage and the validator.

Pure refactor: no behavior change, French output identical.

**Files:**
- Modify: `pipeline/src/packgen/words.py:54-108` (`build_candidates`)
- Modify: `pipeline/src/packgen/cli.py:97-112` (`cmd_words`)
- Test: `pipeline/tests/test_words.py:13-31` (stub + `build` helper)

**Interfaces:**
- Consumes: `Analyzer` / `Token` from `packgen.analyze` (already exist).
- Produces: `build_candidates(language_code: str, *, analyzer: Analyzer, pool: int = 3000, limit: int = 1000) -> tuple[list[Candidate], list[Rejection]]`. The `nlp` keyword is gone.

- [ ] **Step 1: Write the failing test**

In `pipeline/tests/test_words.py`, add `from packgen.analyze import Token` to the import block
(`from packgen.words import build_candidates` is already there at line 10 — leave it), then
replace `StubToken` / `StubNLP` (lines 13-27) and the `build` helper (lines 29-31) with:

```python
class StubAnalyzer:
    """Stands in for a tagger: form -> (lemma, POS), one token per form.

    A form mapped to `None` produces no tokens at all -- what a real tokenizer
    does with a form it cannot segment.
    """

    def __init__(self, tags: dict[str, tuple[str, str] | None]) -> None:
        self.tags = tags

    def analyze(self, sentence: str) -> list[Token]:
        tagged = self.tags.get(sentence, (sentence, "NOUN"))
        if tagged is None:
            return []
        lemma, pos = tagged
        return [Token(sentence, lemma, pos)]


def build(monkeypatch, forms, tags, lang="fr", **kwargs):
    monkeypatch.setattr("wordfreq.top_n_list", lambda language, n: forms[:n])
    return build_candidates(lang, analyzer=StubAnalyzer(tags), pool=len(forms), **kwargs)
```

Then add this new test at the end of the file:

```python
def test_a_form_the_tagger_returns_nothing_for_is_rejected(monkeypatch):
    """NFR-10 an untokenizable form must be recorded, not crash on tokens[0].

    The form has to be one `_reject_reason` lets through, or this would prove the
    cleaning rules rather than the empty-token guard.
    """
    candidates, rejections = build(monkeypatch, ["vide", "chat"], {"vide": None})
    assert [c.lemma for c in candidates] == ["chat"]
    assert [r.reason for r in rejections] == ["no-tokens"]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --project pipeline pytest tests/test_words.py -v`
Expected: FAIL — `build_candidates() got an unexpected keyword argument 'analyzer'` on every test in the file.

- [ ] **Step 3: Write the implementation**

In `pipeline/src/packgen/words.py`, add the import at the top of the imports block:

```python
from packgen.analyze import Analyzer
```

Replace the signature and loop head of `build_candidates` (lines 54-84):

```python
def build_candidates(
    language_code: str,
    *,
    analyzer: Analyzer,
    pool: int = 3000,
    limit: int = 1000,
) -> tuple[list[Candidate], list[Rejection]]:
    """Return `limit` ranked candidates plus every form that was dropped, and why.

    `pool` is the buffer above `limit` -- roughly a third of the raw list is noise
    or a duplicate lemma, so 3000 raw forms comfortably yields 1000 lemmas.

    The tagger arrives as an `Analyzer`, not a spaCy pipeline: Hindi's backend is
    UDPipe, which has no `nlp.pipe`. One form at a time gives up spaCy's batching
    -- ponytail: a few tens of seconds on a stage that runs once per language,
    against a second code path forever.
    """
    from wordfreq import top_n_list

    rules = LANGUAGE_RULES.get(language_code, LanguageRules())
    forms = top_n_list(language_code, pool)

    candidates: list[Candidate] = []
    rejections: list[Rejection] = []
    seen: set[tuple[str, str]] = set()

    for form in forms:
        reason = _reject_reason(form, rules)
        if reason:
            rejections.append(Rejection(form, reason))
            continue

        tokens = analyzer.analyze(form)
        if not tokens:
            rejections.append(Rejection(form, "no-tokens"))
            continue

        token = tokens[0]
        lemma, pos = token.lemma.strip(), token.pos
        if pos not in ENTRY_POS:
            rejections.append(Rejection(form, f"pos:{pos}"))
            continue
```

Everything from `if not lemma:` (line 86) onward is unchanged.

In `pipeline/src/packgen/cli.py`, replace the first three lines of `cmd_words` (lines 97-102):

```python
def cmd_words(args) -> int:
    lang = args.language
    candidates, rejections = build_candidates(
        lang, analyzer=SpacyAnalyzer(lang), pool=args.pool, limit=args.limit
    )
```

(The `import spacy` line inside `cmd_words` goes away. `SpacyAnalyzer` is already imported at `cli.py:31`; Task 4 replaces this call with `make_analyzer`.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --project pipeline pytest tests/test_words.py tests/test_cli.py -v`
Expected: PASS. `test_cli.py` exercises the real French model through `cmd_words`, so this also proves the refactor did not change French behavior.

- [ ] **Step 5: Lint and commit**

```bash
cd pipeline && uv run ruff format . && uv run ruff check . && cd ..
git add pipeline/src/packgen/words.py pipeline/src/packgen/cli.py pipeline/tests/test_words.py
git commit -m "refactor: build candidates through the Analyzer protocol"
```

---

## Task 2: Devanagari survives the candidate cleaner

`_reject_reason` demands every character be `isalpha()`. Devanagari matras, virama and anusvara are Unicode marks, so 2707 of the top 3000 Hindi forms are thrown away as "non-alphabetic" before any tagger sees them.

This is a Unicode correctness fix in the shared function, not a per-language knob — decomposed (NFD) Latin has the same shape.

**Files:**
- Modify: `pipeline/src/packgen/words.py:134-143` (`_reject_reason`)
- Test: `pipeline/tests/test_words.py`

**Interfaces:**
- Consumes: `build` / `StubAnalyzer` from Task 1.
- Produces: no signature change. `_reject_reason` stays private.

- [ ] **Step 1: Write the failing test**

Add to `pipeline/tests/test_words.py`:

```python
def test_devanagari_words_are_not_mistaken_for_junk(monkeypatch):
    """FR-6 Devanagari vowel signs and virama are Unicode marks, not letters.

    `str.isalpha()` is False for `ा` (Mc) and `्` (Mn), so the plain-alpha test
    threw away 2707 of Hindi's top 3000 forms -- including `के`, the single most
    frequent word in the language.
    """
    forms = ["के", "अच्छा", "नहीं", "घर", "😂", "3"]
    candidates, rejections = build(monkeypatch, forms, {}, lang="hi")

    assert [c.source_form for c in candidates] == ["के", "अच्छा", "नहीं", "घर"]
    assert {r.form: r.reason for r in rejections} == {
        "😂": "non-alphabetic",
        "3": "non-alphabetic",
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `uv run --project pipeline pytest tests/test_words.py::test_devanagari_words_are_not_mistaken_for_junk -v`
Expected: FAIL — the candidate list comes back as `["घर"]` (the only form of the four with no combining mark), and the rejection dict carries three extra `non-alphabetic` entries.

- [ ] **Step 3: Write the implementation**

In `pipeline/src/packgen/words.py`, add to the imports:

```python
import unicodedata
```

Replace `_reject_reason`'s first check (lines 136-138):

```python
def _reject_reason(form: str, rules: LanguageRules) -> str | None:
    # Non-alphabetic first, so a stray digit is labelled for what it is rather
    # than swept up by the one-letter rule. "Alphabetic" has to include combining
    # marks: Devanagari writes its vowels as marks (`ा` Mc, `्` Mn), so a plain
    # isalpha() test rejects `के` -- the most frequent word in Hindi -- as junk.
    if not all(
        ch.isalpha() or unicodedata.category(ch) in ("Mn", "Mc") or ch in "-'’" for ch in form
    ):
        return "non-alphabetic"
```

The rest of the function is unchanged.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --project pipeline pytest tests/test_words.py -v`
Expected: PASS, including `test_elision_fragments_and_junk_are_dropped` — `3` and the emoji are still rejected, because digits and emoji are neither letters nor marks.

- [ ] **Step 5: Lint and commit**

```bash
cd pipeline && uv run ruff format . && uv run ruff check . && cd ..
git add pipeline/src/packgen/words.py pipeline/tests/test_words.py
git commit -m "fix: keep Devanagari words out of the non-alphabetic bin"
```

---

## Task 3: `UDPipeAnalyzer`

The second `Analyzer` implementation. spaCy publishes no Hindi pipeline with a POS tagger — `xx_sent_ud_sm` is a sentence segmenter, which is why the existing `SpacyAnalyzer.MODELS["hi"]` entry is a trap.

Split deliberately: `parse_conllu` is pure text→tokens and is tested first with no model; the model loading is an integration test that skips when the 25 MB file is absent, matching `test_spacy_integration.py`'s shape.

**Files:**
- Modify: `pipeline/src/packgen/analyze.py`
- Modify: `pipeline/pyproject.toml` (dependency)
- Create: `pipeline/tests/test_analyze.py`
- Create: `pipeline/tests/test_udpipe_integration.py`

**Interfaces:**
- Consumes: `Token`, `Analyzer` (`analyze.py`).
- Produces:
  - `RemoteModel(filename: str, url: str, sha256: str)` — frozen dataclass.
  - `MODELS_DIR: Path` — `pipeline/work/models`.
  - `parse_conllu(conllu: str) -> list[Token]`.
  - `UDPipeAnalyzer(language_code: str, models_dir: Path = MODELS_DIR)` with `.analyze(sentence) -> list[Token]` and class attribute `MODELS: dict[str, RemoteModel]`.

- [ ] **Step 1: Write the failing tests**

Create `pipeline/tests/test_analyze.py`:

```python
"""CoNLL-U parsing rules -- pure text in, tokens out, no model on disk."""

from __future__ import annotations

from packgen.analyze import parse_conllu

CONLLU = """\
# newdoc
# sent_id = 1
# text = यह एक घर है।
1\tयह\tयह\tPRON\tPRP\t_\t3\tnsubj\t_\t_
2\tएक\tएक\tNUM\tQC\t_\t3\tnummod\t_\t_
3\tघर\tघर\tNOUN\tNN\t_\t0\troot\t_\t_
4\tहै\tहै\tAUX\tVM\t_\t3\tcop\t_\t_
5\t।\t।\tPUNCT\tSYM\t_\t3\tpunct\t_\t_
"""


def test_fr6_comment_lines_are_not_tokens():
    """FR-6 CoNLL-U carries `# text =` metadata that is not part of the sentence."""
    tokens = parse_conllu(CONLLU)
    assert [t.text for t in tokens] == ["यह", "एक", "घर", "है", "।"]
    assert [t.pos for t in tokens] == ["PRON", "NUM", "NOUN", "AUX", "PUNCT"]


def test_fr6_multiword_ranges_and_empty_nodes_are_skipped():
    """FR-6 a `1-2` row repeats rows 1 and 2; counting it doubles a word in the §6 check."""
    text = (
        "1-2\tdel\t_\t_\t_\t_\t_\t_\t_\t_\n"
        "1\tde\tde\tADP\t_\t_\t_\t_\t_\t_\n"
        "2\tel\tel\tDET\t_\t_\t_\t_\t_\t_\n"
        "1.1\tghost\tghost\tNOUN\t_\t_\t_\t_\t_\t_\n"
    )
    assert [t.text for t in parse_conllu(text)] == ["de", "el"]


def test_nfr10_an_unspecified_lemma_is_empty_not_an_underscore():
    """NFR-10 CoNLL-U writes `_` for "not annotated"; carrying it through would put a
    literal underscore in the pack, and words.py would accept it as a real lemma."""
    assert parse_conllu("1\tfoo\t_\tNOUN\t_\t_\t_\t_\t_\t_\n")[0].lemma == ""
```

Create `pipeline/tests/test_udpipe_integration.py`:

```python
"""The real Hindi model. Skips when it is not downloaded -- it is 25 MB and not in git.

`packgen models hi` fetches it; CI caches it on its pinned checksum.
"""

from __future__ import annotations

import gc

import pytest

from packgen.analyze import UDPipeAnalyzer
from packgen.rules import ENTRY_POS


@pytest.fixture(scope="module")
def udpipe_hi() -> UDPipeAnalyzer:
    analyzer = UDPipeAnalyzer("hi")
    try:
        analyzer.analyze("घर")
    except LookupError as exc:  # model not downloaded -> skip, don't fail
        pytest.skip(str(exc))
    return analyzer


@pytest.mark.parametrize("form", ["के", "है", "में", "और", "एक", "नहीं", "को", "पर"])
def test_fr6_hindis_most_frequent_forms_tag_inside_entry_pos(udpipe_hi, form):
    """FR-6 a form tagged outside ENTRY_POS is dropped by words.py.

    The old `xx_sent_ud_sm` mapping tagged everything as nothing, so every Hindi
    form was dropped and the pack came out empty rather than merely degraded.
    """
    tokens = udpipe_hi.analyze(form)
    assert tokens, f"{form} produced no tokens"
    assert tokens[0].pos in ENTRY_POS, (form, tokens[0].pos)


def test_nfr10_the_pipeline_outlives_a_garbage_collection(udpipe_hi):
    """NFR-10 UDPipe's Pipeline holds a raw C pointer to the Model, not a Python
    reference. If the Model is collected, the next process() call segfaults the
    interpreter -- exit 139, no exception, nothing to catch."""
    udpipe_hi.analyze("घर")
    gc.collect()
    assert udpipe_hi.analyze("घर")[0].lemma == "घर"


def test_fr6_a_hindi_sentence_tokenizes_into_lemmas_and_tags(udpipe_hi):
    """FR-6 the §6 check needs lemma + POS for every word of a sentence."""
    tokens = [t for t in udpipe_hi.analyze("यह एक अच्छा घर है।") if t.pos != "PUNCT"]
    assert [t.lemma for t in tokens] == ["यह", "एक", "अच्छा", "घर", "है"]
    assert [t.pos for t in tokens] == ["PRON", "NUM", "ADJ", "NOUN", "AUX"]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --project pipeline pytest tests/test_analyze.py tests/test_udpipe_integration.py -v`
Expected: FAIL at collection — `ImportError: cannot import name 'parse_conllu' from 'packgen.analyze'`.

- [ ] **Step 3: Add the dependency**

In `pipeline/pyproject.toml`, add to `dependencies`:

```toml
    "ufal.udpipe>=1.4.0.1",
```

Then: `uv sync --project pipeline`

- [ ] **Step 4: Write the implementation**

In `pipeline/src/packgen/analyze.py`, extend the imports:

```python
import functools
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol
```

Append below `SpacyAnalyzer`:

```python
@dataclass(frozen=True)
class RemoteModel:
    """A model file that is not distributed as a wheel, pinned by checksum."""

    filename: str
    url: str
    sha256: str


# UDPipe models are plain files, so they land beside the other working data
# rather than in site-packages. Not committed -- see `packgen models`.
MODELS_DIR = Path(__file__).resolve().parents[2] / "work" / "models"


def parse_conllu(conllu: str) -> list[Token]:
    """CoNLL-U text -> tokens. Pure, so the parsing rules are testable with no model.

    Skips comments, multiword-range rows (`1-2`) and empty nodes (`1.1`): those
    repeat material the plain rows already carry, and double-counting a word would
    corrupt the §6 check that reads these tokens.
    """
    tokens: list[Token] = []
    for line in conllu.splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < 4:
            continue
        index = fields[0]
        if "-" in index or "." in index:
            continue
        # `_` is CoNLL-U for "not annotated"; an empty lemma is what words.py
        # already knows how to reject.
        lemma = "" if fields[2] == "_" else fields[2]
        tokens.append(Token(text=fields[1], lemma=lemma, pos=fields[3]))
    return tokens


class UDPipeAnalyzer:
    """UDPipe 1 for languages spaCy has no POS model for.

    spaCy publishes no Hindi pipeline with a tagger at all -- `xx_sent_ud_sm` is a
    sentence segmenter, so `token.pos_` comes back empty and words.py drops every
    single form. UD 2.5's hindi-hdtb model covers 16 of the 17 UPOS tags, which is
    every tag in CLOSED_CLASS and OPEN_CLASS.

    Stanza would score higher and would also pull PyTorch into a CI job that
    installs in ~70s. Not worth it here: the prompts already ask Claude to correct
    lemma and POS (French needs it too), so the tagger's job is only to get the
    candidate list built.
    """

    MODELS = {
        "hi": RemoteModel(
            filename="hindi-hdtb-ud-2.5-191206.udpipe",
            url=(
                "https://raw.githubusercontent.com/jwijffels/udpipe.models.ud.2.5/"
                "master/inst/udpipe-ud-2.5-191206/hindi-hdtb-ud-2.5-191206.udpipe"
            ),
            sha256="d7a77399e6eccee9103d8df9b441ec25ba6ba9f4db453eed3f4ddb77acdd7f2a",
        )
    }

    def __init__(self, language_code: str, models_dir: Path = MODELS_DIR) -> None:
        self.language_code = language_code
        self.models_dir = models_dir

    @functools.cached_property
    def _pipeline(self):
        from ufal.udpipe import Model, Pipeline

        try:
            spec = self.MODELS[self.language_code]
        except KeyError:
            raise LookupError(
                f"no UDPipe model registered for {self.language_code!r}; "
                f"add one to UDPipeAnalyzer.MODELS"
            ) from None

        path = self.models_dir / spec.filename
        if not path.is_file():
            raise LookupError(
                f"UDPipe model {spec.filename!r} is not downloaded. "
                f"Run: uv run packgen models {self.language_code}"
            )
        model = Model.load(str(path))
        if model is None:
            raise LookupError(f"UDPipe could not load {path}")

        # Pipeline stores a raw C pointer to the model, NOT a Python reference.
        # Let the Model be garbage-collected and the next process() call segfaults
        # the interpreter -- no exception, no traceback. Holding it here is the fix.
        self._model = model
        return Pipeline(model, "tokenize", Pipeline.DEFAULT, Pipeline.DEFAULT, "conllu")

    def analyze(self, sentence: str) -> list[Token]:
        from ufal.udpipe import ProcessingError

        error = ProcessingError()
        conllu = self._pipeline.process(sentence, error)
        if error.occurred():
            raise RuntimeError(f"UDPipe failed on {sentence!r}: {error.message}")
        return parse_conllu(conllu)
```

Also delete the dead `"hi": "xx_sent_ud_sm"` entry from `SpacyAnalyzer.MODELS` (`analyze.py:34`) — leaving it is what made the Hindi path look supported:

```python
    MODELS = {"fr": "fr_core_news_md"}
```

- [ ] **Step 5: Download the model and run the tests**

```bash
mkdir -p pipeline/work/models && curl -sL -o pipeline/work/models/hindi-hdtb-ud-2.5-191206.udpipe "https://raw.githubusercontent.com/jwijffels/udpipe.models.ud.2.5/master/inst/udpipe-ud-2.5-191206/hindi-hdtb-ud-2.5-191206.udpipe"
```

Run: `uv run --project pipeline pytest tests/test_analyze.py tests/test_udpipe_integration.py -v`
Expected: PASS, 13 tests (3 parsing + 8 parametrized forms + 2), none skipped. (Task 5 replaces
that `curl` with `packgen models hi`.)

- [ ] **Step 6: Lint and commit**

```bash
cd pipeline && uv run ruff format . && uv run ruff check . && cd ..
git add pipeline/src/packgen/analyze.py pipeline/pyproject.toml pipeline/uv.lock pipeline/tests/test_analyze.py pipeline/tests/test_udpipe_integration.py
git commit -m "feat: tag Hindi with UDPipe"
```

---

## Task 4: `make_analyzer` — the language→backend table

Three call sites hardcode `SpacyAnalyzer`. One table replaces all three, and it is the line ADR-004 gets judged on: adding a language is a row, adding a *kind* of backend is a class.

**Files:**
- Modify: `pipeline/src/packgen/analyze.py` (append)
- Modify: `pipeline/src/packgen/cli.py:31` (import), `cmd_words`, `cli.py:274` (`cmd_pack`), `cli.py:324` (`cmd_validate`)
- Test: `pipeline/tests/test_analyze.py`

**Interfaces:**
- Consumes: `SpacyAnalyzer`, `UDPipeAnalyzer`.
- Produces: `ANALYZERS: dict[str, type]` and `make_analyzer(language_code: str) -> Analyzer`.

- [ ] **Step 1: Write the failing test**

In `pipeline/tests/test_analyze.py`, extend the imports at the top of the file:

```python
import pytest

from packgen.analyze import SpacyAnalyzer, UDPipeAnalyzer, make_analyzer, parse_conllu
```

and append:

```python
def test_fr6_the_analyzer_table_maps_each_language_to_its_backend():
    """FR-6 adding a language is a row in ANALYZERS, not a branch at three call sites."""
    assert isinstance(make_analyzer("fr"), SpacyAnalyzer)
    assert isinstance(make_analyzer("hi"), UDPipeAnalyzer)


def test_nfr10_an_unregistered_language_says_what_to_add():
    """NFR-10 the failure names the table to edit rather than an AttributeError later."""
    with pytest.raises(LookupError, match="ANALYZERS"):
        make_analyzer("xx")
```

Neither call loads a model — both backends resolve theirs lazily in a
`cached_property` — so this test needs nothing on disk.

- [ ] **Step 2: Run the test to verify it fails**

Run: `uv run --project pipeline pytest tests/test_analyze.py -v`
Expected: FAIL — `ImportError: cannot import name 'make_analyzer'`.

- [ ] **Step 3: Write the implementation**

Append to `pipeline/src/packgen/analyze.py`:

```python
# The one place a language maps to an NLP backend. Adding a language is a row
# here; adding a *kind* of backend is a class -- which happens once per backend,
# not once per language.
ANALYZERS = {"fr": SpacyAnalyzer, "hi": UDPipeAnalyzer}


def make_analyzer(language_code: str) -> Analyzer:
    backend = ANALYZERS.get(language_code)
    if backend is None:
        raise LookupError(
            f"no analyzer registered for {language_code!r}; add one to ANALYZERS"
        )
    return backend(language_code)
```

In `pipeline/src/packgen/cli.py`, change the import at line 31:

```python
from packgen.analyze import UDPipeAnalyzer, make_analyzer
```

(`UDPipeAnalyzer` is for the `models` command in Task 5. If you are executing Task 4 alone, import only `make_analyzer` and add `UDPipeAnalyzer` in Task 5.)

Then replace the three construction sites:

- `cmd_words` — `analyzer=SpacyAnalyzer(lang)` becomes `analyzer=make_analyzer(lang)`
- `cmd_pack` (`cli.py:274`) — `analyzer=SpacyAnalyzer(lang)` becomes `analyzer=make_analyzer(lang)`
- `cmd_validate` (`cli.py:324`) — `analyzer=SpacyAnalyzer(pack.get("language_code", ""))` becomes `analyzer=make_analyzer(pack.get("language_code", ""))`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --project pipeline pytest -v`
Expected: PASS, whole suite. `test_cli.py` proves the French path still works end to end through the table.

- [ ] **Step 5: Lint and commit**

```bash
cd pipeline && uv run ruff format . && uv run ruff check . && cd ..
git add pipeline/src/packgen/analyze.py pipeline/src/packgen/cli.py pipeline/tests/test_analyze.py
git commit -m "refactor: resolve the analyzer from a language table"
```

---

## Task 5: `packgen models <lang>` and the CI cache

The French model is a pinned wheel URL in `pyproject.toml`. UDPipe publishes no wheels, so the model needs its own fetch — and the URL is a third-party mirror's `master` branch, which is a moving target. The checksum is the point: a model that silently changed would change pack contents with no other signal.

**Files:**
- Modify: `pipeline/src/packgen/analyze.py` (append `download_model`, `_sha256`)
- Modify: `pipeline/src/packgen/cli.py` (subparser + `cmd_models`)
- Modify: `.gitignore`
- Modify: `.github/workflows/ci.yml` (pipeline job)
- Test: `pipeline/tests/test_analyze.py`

**Interfaces:**
- Consumes: `RemoteModel`, `MODELS_DIR`, `UDPipeAnalyzer.MODELS` (Task 3).
- Produces: `download_model(spec: RemoteModel, directory: Path = MODELS_DIR) -> Path`.

- [ ] **Step 1: Write the failing tests**

In `pipeline/tests/test_analyze.py`, extend the existing import block (`pytest` is already
there from Task 4 — do not import it twice, ruff's `F811` will fail the build):

```python
import contextlib
import hashlib
import io
```

and extend the `packgen.analyze` import with `RemoteModel, download_model`. Then append:

```python
def fake_urlopen(payload: bytes):
    @contextlib.contextmanager
    def opener(url, *args, **kwargs):
        yield io.BytesIO(payload)

    return opener


def spec_for(payload: bytes) -> RemoteModel:
    return RemoteModel(
        filename="test.udpipe",
        url="https://example.invalid/test.udpipe",
        sha256=hashlib.sha256(payload).hexdigest(),
    )


def test_fr6_a_model_is_downloaded_to_the_models_directory(tmp_path, monkeypatch):
    """FR-6 the model UDPipe does not ship as a wheel is fetched on demand."""
    payload = b"pretend this is 25MB of model"
    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen(payload))

    path = download_model(spec_for(payload), tmp_path)

    assert path == tmp_path / "test.udpipe"
    assert path.read_bytes() == payload


def test_nfr10_a_model_whose_checksum_differs_is_refused(tmp_path, monkeypatch):
    """NFR-10 the URL is a mirror's master branch. A model that changed upstream must
    fail loudly, not quietly alter every pack generated afterwards."""
    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen(b"something else"))
    spec = spec_for(b"the real model")

    with pytest.raises(LookupError, match="SHA-256"):
        download_model(spec, tmp_path)

    assert list(tmp_path.iterdir()) == [], "a rejected download must leave nothing behind"


def test_nfr10_a_model_already_on_disk_is_not_downloaded_again(tmp_path, monkeypatch):
    """NFR-10 25 MB per run is not a no-op; the CI cache depends on this being cheap."""
    payload = b"pretend this is 25MB of model"
    (tmp_path / "test.udpipe").write_bytes(payload)

    def explode(*args, **kwargs):
        raise AssertionError("should not have downloaded")

    monkeypatch.setattr("urllib.request.urlopen", explode)
    assert download_model(spec_for(payload), tmp_path) == tmp_path / "test.udpipe"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --project pipeline pytest tests/test_analyze.py -v`
Expected: FAIL — `ImportError: cannot import name 'download_model'`.

- [ ] **Step 3: Write the implementation**

In `pipeline/src/packgen/analyze.py`, extend the top-level imports:

```python
import functools
import hashlib
import shutil
import urllib.request
```

Append:

```python
def download_model(spec: RemoteModel, directory: Path = MODELS_DIR) -> Path:
    """Fetch a pinned model, refusing anything whose SHA-256 does not match.

    Re-running is cheap: a file already on disk with the right digest is returned
    untouched, which is what makes the CI cache worth having.
    """
    directory.mkdir(parents=True, exist_ok=True)
    destination = directory / spec.filename
    if destination.is_file() and _sha256(destination) == spec.sha256:
        return destination

    # Download beside the destination, not onto it: an interrupted fetch must not
    # leave a truncated file that looks like a model.
    partial = destination.with_name(destination.name + ".partial")
    with urllib.request.urlopen(spec.url) as response, partial.open("wb") as out:
        shutil.copyfileobj(response, out)

    actual = _sha256(partial)
    if actual != spec.sha256:
        partial.unlink()
        raise LookupError(
            f"{spec.filename}: expected SHA-256 {spec.sha256}, got {actual}. "
            f"The pinned model changed upstream -- do not use it."
        )
    partial.replace(destination)
    return destination


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()
```

In `pipeline/src/packgen/cli.py`, add the subparser after `p_words` (around line 53):

```python
    p_models = sub.add_parser("models", help="download the pinned NLP model for a language")
    p_models.add_argument("language")
```

Add `"models": cmd_models,` to the dispatch dict in `main`, and add the stage:

```python
def cmd_models(args) -> int:
    lang = args.language
    spec = UDPipeAnalyzer.MODELS.get(lang)
    if spec is None:
        print(
            f"no downloadable model for {lang!r} "
            f"(spaCy languages install theirs from pyproject.toml)",
            file=sys.stderr,
        )
        return 1
    path = download_model(spec)
    print(f"{spec.filename} -> {path}")
    return 0
```

and extend the `cli.py:31` import:

```python
from packgen.analyze import UDPipeAnalyzer, download_model, make_analyzer
```

Update the module docstring's command list (`cli.py:3-7`) to include:

```
    packgen models hi       # download the pinned UDPipe model  -> work/models/
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
uv run --project pipeline pytest tests/test_analyze.py -v
rm -rf pipeline/work/models && uv run --project pipeline packgen models hi
uv run --project pipeline pytest tests/test_udpipe_integration.py -v
```
Expected: PASS; the `models` run prints the path, and the integration tests run rather than skip.

- [ ] **Step 5: Keep the 25 MB file out of git**

Add to `.gitignore` under the pipeline working-files block:

```
# The UDPipe model is 25 MB of binary, pinned by checksum and fetched with
# `packgen models <lang>`. Never committed.
pipeline/work/models/
```

Verify: `git status --short` shows nothing under `pipeline/work/models/`.

- [ ] **Step 6: Let CI download it once and cache it**

In `.github/workflows/ci.yml`, in the `pipeline` job, insert between "Sync dependencies (locked)" and "Ruff":

```yaml
      # The Hindi UDPipe model is 25 MB and not in git. Cache it on its pinned
      # checksum, so the real-tagging tests run here instead of skipping, and a
      # cache hit makes `packgen models hi` a checksum check with no download.
      - name: Cache the UDPipe Hindi model
        uses: actions/cache@v4
        with:
          path: pipeline/work/models
          key: udpipe-hi-d7a77399e6eccee9103d8df9b441ec25ba6ba9f4db453eed3f4ddb77acdd7f2a
      - name: Download the UDPipe Hindi model
        run: uv run packgen models hi
```

(The `pipeline` job sets `working-directory: pipeline`, so `run:` is already inside `pipeline/`; the `cache` action's `path` is repo-relative, hence `pipeline/work/models`.)

- [ ] **Step 7: Lint and commit**

```bash
cd pipeline && uv run ruff format . && uv run ruff check . && cd ..
git add pipeline/src/packgen/analyze.py pipeline/src/packgen/cli.py pipeline/tests/test_analyze.py .gitignore .github/workflows/ci.yml
git commit -m "feat: fetch pinned NLP models by checksum"
```

---

## Task 6: The Hindi candidate list

First stage of the real run. Deliverable: a committed `work/hi/candidates.json` whose rejections have been read, not assumed.

**Files:**
- Modify: `pipeline/src/packgen/words.py:48-51` (`LANGUAGE_RULES["hi"]`) — only if the review below calls for it
- Create (generated): `pipeline/work/hi/candidates.json`, `pipeline/work/hi/rejected.json`

**Interfaces:**
- Consumes: `make_analyzer` (Task 4), `packgen models` (Task 5).
- Produces: `work/hi/candidates.json` — the rank list every later stage reads.

- [ ] **Step 1: Build the candidates**

```bash
uv run --project pipeline packgen words hi
```

Expected: `1842 candidates, 1158 forms rejected -> .../work/hi` — and **no** `warning: wanted 1200; raise --pool`. If the candidate count is under 1200, stop and report; do not silently raise `--pool` past 3000 without saying so.

- [ ] **Step 2: Read the rejections before trusting the list**

```bash
uv run --project pipeline python -c "
import collections, json
r = json.load(open('pipeline/work/hi/rejected.json'))
print(collections.Counter(x['reason'] for x in r).most_common(10))
print([x['form'] for x in r if x['reason'] == 'elision-fragment'][:20])
"
```

Expected shape, measured in the spike: `duplicate` ~546, `pos:PROPN` ~540, `non-alphabetic` ~32, `elision-fragment` ~30, `pos:X` ~10.

Three things to check, each with a decision attached:

1. **`pos:PROPN` ~540 is correct, not a bug.** wordfreq's Hindi list carries 80 Latin-script forms (`the`, `of`, `news`) and the Hindi model tags them all `PROPN`. That is the gate doing its job.
2. **`elision-fragment` are single-codepoint forms.** Devanagari has no elision, so the label is a French inheritance. Of the single letters in the list, `न` (PART), `आ` (VERB), `व` (CCONJ) and `ए` (PART) tag inside `ENTRY_POS` and are arguably real words. **Only** if one of them would land inside the top 1200 by frequency, add it:
   ```python
   "hi": LanguageRules(one_letter_words=frozenset({"न", "आ", "व", "ए"})),
   ```
   Otherwise leave `LANGUAGE_RULES["hi"]` empty and note why in the commit message. Do not add a knob nothing consumes.
3. **`non-alphabetic` ~32 should be digits and emoji only.** If any Devanagari word appears here, Task 2's fix is incomplete — stop and fix it before generating 1000 sentences on a broken list.

- [ ] **Step 3: Sanity-check the head of the list**

```bash
uv run --project pipeline python -c "
import json
c = json.load(open('pipeline/work/hi/candidates.json'))
print(len(c)); print([(x['rank'], x['lemma'], x['pos']) for x in c[:20]])
"
```

Expected first entries: `के`/ADP, `है`/AUX, `में`/ADP, `का`/VERB, `से`/PART, `और`/CCONJ. `का` tagged VERB is a known isolated-word error (it is also the perfective of करना) — the prompts ask Claude to correct lemma and POS, which is where it gets fixed. Do not hand-edit `candidates.json`.

- [ ] **Step 4: Commit**

```bash
git add pipeline/work/hi/candidates.json pipeline/work/hi/rejected.json pipeline/src/packgen/words.py
git commit -m "feat: build the Hindi candidate list"
```

---

## Task 7: Generate and validate the Hindi pack

20 batches of 50 through the Claude Code CLI, then the regeneration loop until `pack` goes green. This is the long-running task; it is resumable by design.

**Files:**
- Create (generated): `pipeline/work/hi/responses/*.json`, `pipeline/packs/hi.pack.json`
- Create (hand-authored, only if needed): `pipeline/work/hi/exceptions.json`

**Interfaces:**
- Consumes: `work/hi/candidates.json` (Task 6).
- Produces: `pipeline/packs/hi.pack.json` — a schema-valid 1000-word pack, the input to Task 8.

- [ ] **Step 1: Write the prompts and generate**

```bash
uv run --project pipeline packgen prompts hi && uv run --project pipeline packgen generate hi
```

`generate` is resumable: only replies that parse are saved, and answered prompts are skipped, so an interrupted run is re-run with the same command. Unusable replies are kept as `NNN.json.bad`.

- [ ] **Step 2: Assemble, validate, and run the regeneration loop**

```bash
until uv run --project pipeline packgen pack hi; do uv run --project pipeline packgen generate hi --retry || break; done
```

The loop stops on its own when a round changes nothing (`_write_retry_prompts` returns False and `generate --retry` exits non-zero).

- [ ] **Step 3: Count the §6 waivers — this is a result, not bookkeeping**

When `pack` reports violations that regenerating will not fix, they are §6 (VR-10) cases where no legal sentence exists. Count them, then apply the rule from the spec's Decision 4:

- **A handful (French-scale — French needed exactly one, `fr:se:PRON`).** Document each in `pipeline/work/hi/exceptions.json`, mapping entry id to *why* no sentence exists, in the same shape as the French file:
  ```json
  { "hi:<lemma>:<POS>": "why §6 is unsatisfiable for this word, specifically" }
  ```
- **Tens of words.** **Stop.** That is a finding about the *rule*, not about Hindi. Report it with the count and the list, and propose a relaxation (most likely: allow closed-class words from the same rank band, since a postposition is not vocabulary a learner is being asked to acquire the way a noun is). Do not proceed by waiving them.

**Do not mass-waive to make the pack pass.** A validator that waives everything checks nothing. Record the final count — it is verdict number 3 in Task 9.

The spike measured Hindi's closed-class density at 57/100 in the first hundred candidates against French's 56/100, so expect the first branch. If it turns out to be the second, that is genuinely new information and worth the stop.

- [ ] **Step 4: Spot-check the content before shipping it**

```bash
uv run --project pipeline python -c "
import json
p = json.load(open('pipeline/packs/hi.pack.json'))
print(p['word_count'], p['language_code'], p['language_name'])
for w in p['words'][:10]: print(w['id'], '|', w['display'], '|', w['gloss'], '|', w['example'])
"
cat pipeline/work/hi/suspect-lemmas.json 2>/dev/null
```

Check by eye: the glosses are plausible English, the examples are real Hindi sentences, and `display` carries citation forms. `suspect-lemmas.json` lists lemmas wordfreq has never seen — those are tagger inventions and each one needs a look. This is the D4 human review, and it is the step that a green validator cannot do for you.

- [ ] **Step 5: Commit**

```bash
git add pipeline/packs/hi.pack.json pipeline/work/hi/responses pipeline/work/hi/exceptions.json
git commit -m "feat: generate the Hindi language pack"
```

---

## Task 8: Ship Hindi in the app

The ADR-004 moment. If this task needs anything beyond a resource file and a manifest row — plus deleting the placeholder the pack replaces — that is the leak the phase exists to find. Record whatever it needs; do not work around it quietly.

**Files:**
- Create: `FullDeck/FullDeck/Resources/packs/hi.pack.json` (copied)
- Modify: `FullDeck/FullDeck/Resources/packs/manifest.json`
- Modify: `FullDeck/FullDeck/Views/LanguageSelectionView.swift:39-64` (delete `comingSoon` + `comingSoonSection`)
- Modify: `FullDeck/FullDeck/Localizable.xcstrings` (drop the now-unused `"Coming soon"` key)
- Modify: `FullDeck/FullDeckUITests/FullDeckUITests.swift:117-134` (replace the coming-soon test)
- Test: `FullDeck/FullDeckTests/IntegrationTests.swift`

**Interfaces:**
- Consumes: `pipeline/packs/hi.pack.json` (Task 7).
- Produces: a second `PackDescriptor` from `availablePacks()`, `unlockedByDefault: false`.

- [ ] **Step 1: Write the failing tests**

Add to `FullDeck/FullDeckTests/IntegrationTests.swift`:

```swift
@Test("FR-1 the bundled Hindi pack loads and reports 1000 words")
@MainActor
func bundledHindiPackLoads() async throws {
    let dependencies = try AppDependencies.make(
        packsDirectory: AppDependencies.bundledPacksDirectory, inMemory: true)

    let pack = try await dependencies.packStore.loadPack(LanguageCode("hi"))

    #expect(pack.wordCount == 1000)
    #expect(pack.words.count == 1000)
}

@Test("FR-2 Hindi ships locked: the manifest, not app code, decides what is free")
@MainActor
func bundledHindiPackIsLocked() async throws {
    let dependencies = try AppDependencies.make(
        packsDirectory: AppDependencies.bundledPacksDirectory, inMemory: true)
    // A throwaway suite, matching LanguageSelectionViewModelTests: `select()`
    // persists, and this must not leak into the simulator's real defaults.
    let defaults = UserDefaults(suiteName: "com.fulldeck.tests.hindi.\(UUID().uuidString)")!
    let viewModel = LanguageSelectionViewModel(
        packStore: dependencies.packStore,
        entitlements: NoPurchasesEntitlementStore(),
        defaults: defaults)

    await viewModel.load()

    guard case .ready(let options) = viewModel.state else {
        Issue.record("expected .ready, got \(viewModel.state)")
        return
    }
    let hindi = try #require(options.first { $0.descriptor.languageCode == LanguageCode("hi") })
    #expect(!hindi.isUnlocked)
    // And selecting it must not start a session (FR-1).
    viewModel.select(hindi)
    #expect(viewModel.activeLanguage != LanguageCode("hi"))
}
```

In `FullDeck/FullDeckUITests/FullDeckUITests.swift`, replace `testComingSoonLanguageIsShownButNotSelectable` (lines 117-134) with:

```swift
    /// The Languages screen lists Hindi as a real, locked pack. It must be visible
    /// and must not be selectable — Phase 11 is what makes it buyable.
    @MainActor
    func testFR1LockedLanguageIsListedButNotSelectable() throws {
        let app = XCUIApplication()
        app.launch()

        let hindi = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "हिन्दी")).firstMatch
        XCTAssertTrue(
            hindi.waitForExistence(timeout: 15),
            "No Hindi row. Hierarchy:\n\(app.debugDescription)")
        XCTAssertFalse(hindi.isEnabled, "a locked pack must not be tappable")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: FAIL — `bundledHindiPackLoads` throws (no `hi.pack.json`), and the UI test finds no Hindi *button* (today's row is static text).

Confirm the count really ran, since `xcodebuild` can print `** TEST SUCCEEDED **` having executed nothing:
```bash
xcrun xcresulttool get test-results summary --path <path-to-.xcresult>
```

- [ ] **Step 3: Add the pack and the manifest row**

```bash
cp pipeline/packs/hi.pack.json FullDeck/FullDeck/Resources/packs/hi.pack.json
```

`FullDeck/FullDeck/Resources/packs/manifest.json` becomes:

```json
{
  "packs": [
    {
      "language_code": "fr",
      "display_name": "Français",
      "filename": "fr.pack.json",
      "unlocked_by_default": true
    },
    {
      "language_code": "hi",
      "display_name": "हिन्दी",
      "filename": "hi.pack.json",
      "unlocked_by_default": false
    }
  ]
}
```

No Xcode project edit: `FullDeck/FullDeck/` is a `PBXFileSystemSynchronizedRootGroup`, so a new file under it is picked up from disk.

- [ ] **Step 4: Delete the placeholder**

In `FullDeck/FullDeck/Views/LanguageSelectionView.swift`, delete the `comingSoon` constant and `comingSoonSection` (lines 39-64) and the `comingSoonSection` call inside the `List` (line 29), leaving:

```swift
        case .ready(let options):
            List {
                ForEach(options) { option in
                    languageRow(option)
                }
            }
            // A List paints its own background over the one set on the
            // NavigationStack content; hiding it lets the warm base show.
            .scrollContentBackground(.hidden)
```

In `FullDeck/FullDeck/Localizable.xcstrings`, remove the `"Coming soon"` entry (and its Spanish `"Próximamente"` translation) — nothing references it now. Validate the file after editing: `python3 -m json.tool FullDeck/FullDeck/Localizable.xcstrings > /dev/null`.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcrun simctl terminate booted arjunpathak.FullDeck 2>/dev/null || true
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: PASS, including `testNFR4NFR5NFR6AccessibilityAuditOnCoreScreens` — the audit now sees a second, locked row and must still find no contrast or label problems. Terminate any manually-launched instance first; a live app contends with the test runner and produces "Failed to get background assertion … Timed out".

- [ ] **Step 6: Look at it**

Launch the app in the simulator and confirm the Languages screen: two rows, Français with its checkmark, हिन्दी with a lock, Devanagari rendering correctly at default and at the largest Dynamic Type size. The audit cannot tell you the Devanagari looks right.

- [ ] **Step 7: Lint and commit**

```bash
swiftlint lint --strict
git add FullDeck/
git commit -m "feat: ship the Hindi pack, locked"
```

---

## Task 9: The verdict and the docs

The phase exists to test ADR-004. The answer is three measured numbers and an honest qualification, written down where the next person will find it.

**Files:**
- Create: `docs/phase-12-verdict.md`
- Modify: `pipeline/README.md` ("Adding a language", the stages list)
- Modify: `docs/build-plan.md`, `docs/next-task.md`

- [ ] **Step 1: Measure the three numbers**

```bash
BASE=$(git merge-base HEAD main)
echo "--- app code (expect 0 beyond deleting the placeholder) ---"
git diff --stat $BASE HEAD -- FullDeck/FullDeck FullDeck/FullDeckTests FullDeck/FullDeckUITests Packages | tail -1
echo "--- pipeline code ---"
git diff --stat $BASE HEAD -- pipeline/src pipeline/tests | tail -1
echo "--- data, not code ---"
git diff --stat $BASE HEAD -- pipeline/packs pipeline/work FullDeck/FullDeck/Resources | tail -1
```

Report the app number honestly. It will not be zero — the tests, the manifest row and the deleted `comingSoon` constant are all real lines. What matters for ADR-004 is the *kind* of change: a data row and a placeholder removal, or new logic that exists to support a language.

- [ ] **Step 2: Write `docs/phase-12-verdict.md`**

Cover, in this order:

1. **The three numbers**, with the diffstat that produced them.
2. **Verdict on ADR-004 for the app layer.** If the only app changes are the manifest row, the pack file, the deleted placeholder and their tests, ADR-004 holds as written — a language is a data pack.
3. **The qualification, stated plainly.** The *pipeline's* per-language story is weaker than the app's. It is "a table entry **provided a UD model exists for your language**" — a real precondition the README did not previously mention. Hindi needed a whole second NLP backend.
4. **The three findings that were not in the spec**, because they are what the next language will hit too:
   - `words.py`'s "alphabetic" test was Latin-script-specific; Devanagari needed Unicode marks allowed (293 → 2968 forms surviving out of 3000).
   - UDPipe's `Pipeline` segfaults if the `Model` is collected.
   - The spec's §6 alarm, reasoned from the top 15 forms, did not survive measurement: Hindi 57/100 closed-class vs French 56/100.
5. **The §6 waiver count** from Task 7, with the entries and their reasons.
6. **What the next language needs**, as a checklist: a UD model, a row in `ANALYZERS`, a row in `LANGUAGE_RULES`, a row in `LANGUAGE_NAMES`, a manifest entry — and a re-read of `rejected.json`, because that is where a script-specific assumption shows up.

- [ ] **Step 3: Correct the pipeline README**

In `pipeline/README.md`, add `packgen models` to the stages list, and rewrite "Adding a language" so it stops implying every language is four table rows:

```markdown
## Adding a language

1. **An NLP model that gives lemma and POS.** This is the real precondition. spaCy
   covers French; it publishes no Hindi pipeline with a tagger at all, so Hindi needed
   `UDPipeAnalyzer` — a second backend, not a table row. Check first.
2. `ANALYZERS[code]` — which backend. A row, once a backend exists for the model.
3. `UDPipeAnalyzer.MODELS[code]` (URL + SHA-256) for UDPipe languages, or a pinned
   wheel in `pyproject.toml` for spaCy ones. Then `uv run packgen models <code>`.
4. `LANGUAGE_RULES[code]` — the cleaning knobs. Start empty and read `rejected.json`:
   that file is where a script-specific assumption in the shared rules shows up.
5. `LANGUAGE_NAMES[code]` — the display name.
6. Run the stages.
```

Delete the closing "Hindi is Phase 12, and is expected to need more work at step 2" paragraph — it is now history, and the verdict doc carries it.

- [ ] **Step 4: Update the project docs**

- `docs/build-plan.md`: mark Phase 12 done, note that Phase 11 (StoreKit) is next and now has something to sell.
- `docs/next-task.md`: rewrite the "Right now" block to point at Phase 11 — unshelve `docs/superpowers/specs/2026-08-01-storekit-monetization-design.md` and **re-verify its StoreKit API notes first** (last checked 2026-08-01). Carry forward the two unresolved manual checklists in `docs/phase-10-verification.md` (airplane-mode session, VoiceOver/Dynamic Type walkthrough — both need a physical device) and the note that `StudyView.completionView` / `caughtUpView` are still unreached by the automated audit.
- Flag in `next-task.md`, prominently: **between this phase and Phase 11, Hindi shows as locked with no way to unlock it.** `LanguageSelectionViewModel.select` already refuses locked packs, so it is safe, but it is a worse user-facing state than "coming soon" — the two phases should land close together.

- [ ] **Step 5: Full gate run**

```bash
uv run --project pipeline pytest && uv run --project pipeline ruff format --check . && uv run --project pipeline ruff check .
swift test --package-path Packages/Domain && swift test --package-path Packages/Data
scripts/determinism-check.sh && swiftlint lint --strict
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add docs/ pipeline/README.md
git commit -m "docs: record the phase 12 architecture-validation verdict"
```

---

## Self-review notes

- **Spec coverage.** Decision 1 → Task 3. Decision 2 → Tasks 1 and 4 (the spec named only `cmd_pack` and `cmd_validate`; `cmd_words` hardcodes `spacy.load` too and is covered by Task 1). Decision 3 → Task 5. Decision 4 → Task 7 Step 3. Decision 5 → Task 9. Scope "delete the `comingSoon` constant" → Task 8 Step 4; "manifest with `unlocked_by_default: false`" → Task 8 Step 3; the locked-but-unbuyable note → Task 9 Step 4.
- **Two blockers the spec does not mention** are handled in Tasks 2 and 3, and both were found by running the model rather than reasoning about it.
- **One spec claim is contradicted by measurement** and is corrected in Task 7 Step 3 rather than silently followed: the §6 risk is French-scale, not worse.
