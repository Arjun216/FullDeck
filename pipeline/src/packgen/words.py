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

from dataclasses import dataclass

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
    "hi": LanguageRules(),
}


def build_candidates(
    language_code: str,
    *,
    nlp,
    pool: int = 3000,
    limit: int = 1000,
) -> tuple[list[Candidate], list[Rejection]]:
    """Return `limit` ranked candidates plus every form that was dropped, and why.

    `pool` is the buffer above `limit` -- roughly a third of the raw list is noise
    or a duplicate lemma, so 3000 raw forms comfortably yields 1000 lemmas.
    """
    from wordfreq import top_n_list

    rules = LANGUAGE_RULES.get(language_code, LanguageRules())
    forms = top_n_list(language_code, pool)

    candidates: list[Candidate] = []
    rejections: list[Rejection] = []
    seen: set[tuple[str, str]] = set()

    for form, doc in zip(forms, nlp.pipe(forms), strict=True):
        reason = _reject_reason(form, rules)
        if reason:
            rejections.append(Rejection(form, reason))
            continue

        token = doc[0]
        lemma, pos = token.lemma_.strip(), token.pos_
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


def _reject_reason(form: str, rules: LanguageRules) -> str | None:
    # Non-alphabetic first, so a stray digit is labelled for what it is rather
    # than swept up by the one-letter rule.
    if not all(ch.isalpha() or ch in "-'’" for ch in form):
        return "non-alphabetic"
    if len(form) == 1 and form not in rules.one_letter_words:
        return "elision-fragment"
    if rules.drop_suffixes and form.endswith(rules.drop_suffixes):
        return "elision-fragment"
    return None
