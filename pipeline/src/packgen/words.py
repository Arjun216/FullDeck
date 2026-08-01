"""wordfreq -> a ranked, de-duplicated lemma list.

wordfreq hands back *surface tokens*, ordered by corpus frequency, with plenty of
noise: elision fragments (French `l`, `d`, `qu`), inflections of one lemma spread
across many entries (`est`/`sont`/`être`), and proper nouns. This module turns that
into the lemma-keyed candidate list the pack contract wants (schema §10), and
records *why* each rejected form was dropped so the result is reviewable.

The per-language knobs live in LANGUAGE_RULES below -- adding a language should be
a table entry, not a new code path.
"""

from __future__ import annotations

import unicodedata
from dataclasses import dataclass

from packgen.analyze import Analyzer
from packgen.rules import CLOSED_CLASS, ENTRY_POS


@dataclass(frozen=True)
class Candidate:
    lemma: str
    pos: str
    rank: int
    is_function_word: bool
    source_form: str  # the wordfreq token that first produced this lemma


@dataclass(frozen=True)
class Rejection:
    form: str
    reason: str


@dataclass(frozen=True)
class LanguageRules:
    """Per-language cleaning knobs. A new language adds an entry, not a code path."""

    # Real one-letter words. Everything else of length 1 is an elision fragment
    # (French `l'`, `d'`, `j'` arrive from wordfreq as bare letters).
    one_letter_words: frozenset[str] = frozenset()
    # Longer elision fragments the lemmatizer does not fold back into their lemma:
    # French `qu`, `jusqu`, `lorsqu`, `puisqu` all end in `qu`, and no real French
    # word does.
    drop_suffixes: tuple[str, ...] = ()


LANGUAGE_RULES = {
    "fr": LanguageRules(one_letter_words=frozenset({"a", "à", "y"}), drop_suffixes=("qu",)),
    # Devanagari has no elision, so the length-1 rule is inherited from French and
    # fires on real letters. Of the 12 single-codepoint forms inside the top 1200,
    # only these two are unambiguously words: `न` (not/nor, raw rank 46) and `व`
    # (and, formal, raw rank 115). The rest are bare letters, and the tagger cannot
    # tell the difference -- it calls `ई` a NOUN and `ह` a NUM. `आ` and `ए` are
    # left out on purpose: `आ` is an inflected form whose real lemma (`आना`) is
    # already a candidate, and `ए` is more often the letter's name than the
    # vocative particle.
    "hi": LanguageRules(one_letter_words=frozenset({"न", "व"})),
}


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
        if not lemma:
            rejections.append(Rejection(form, "empty-lemma"))
            continue

        key = (lemma, pos)
        if key in seen:
            rejections.append(Rejection(form, f"duplicate:{lemma}"))
            continue
        seen.add(key)

        candidates.append(
            Candidate(
                lemma=lemma,
                pos=pos,
                rank=len(candidates) + 1,
                is_function_word=pos in CLOSED_CLASS,
                source_form=form,
            )
        )
        if len(candidates) == limit:
            break

    return candidates, rejections


# A word in a top-1000 pack whose lemma is rarer than this is a contradiction in
# terms -- in practice it means the lemmatizer invented the form. Measured on French:
# 40 of 1200 candidates fall below it, and they are all real errors (`musiqu`,
# `écrir`, `traval` -- spaCy dropping a final `e`). Testing for *zero* frequency
# would catch only 11 of them, because the inventions turn up as corpus typos too.
SUSPECT_FREQUENCY_FLOOR = 1e-6


def suspicious_lemmas(pack: dict) -> list[str]:
    """Entry ids whose lemma is too rare to plausibly be one of a language's top words.

    Nothing in §7 can catch an invented lemma -- it is still non-empty, trimmed and
    NFC. So this is a *report*, run after assembly, to aim the human review (D4) at
    the entries most likely to be wrong.
    """
    from wordfreq import word_frequency

    code = pack["language_code"]
    return [
        w["id"] for w in pack["words"] if word_frequency(w["lemma"], code) < SUSPECT_FREQUENCY_FLOOR
    ]


def _reject_reason(form: str, rules: LanguageRules) -> str | None:
    # Non-alphabetic first, so a stray digit is labelled for what it is rather
    # than swept up by the one-letter rule. "Alphabetic" has to include combining
    # marks: Devanagari writes its vowels as marks (`ा` Mc, `्` Mn), so a plain
    # isalpha() test rejects `के` -- the most frequent word in Hindi -- as junk.
    if not all(
        ch.isalpha() or unicodedata.category(ch) in ("Mn", "Mc") or ch in "-'’" for ch in form
    ):
        return "non-alphabetic"
    if len(form) == 1 and form not in rules.one_letter_words:
        return "elision-fragment"
    if rules.drop_suffixes and form.endswith(rules.drop_suffixes):
        return "elision-fragment"
    return None
