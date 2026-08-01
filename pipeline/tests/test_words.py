"""Candidate-list cleaning rules.

wordfreq's raw list is surface tokens, and its noise is language-specific. spaCy
itself is not under test here -- a stub stands in for it so the *rules* (what gets
dropped, what gets merged, how ranks are assigned) are checked deterministically.
"""

from __future__ import annotations

from packgen.analyze import Token
from packgen.words import build_candidates


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


def test_elision_fragments_and_junk_are_dropped(monkeypatch):
    """FR-6 wordfreq's French list carries elision fragments that are not words."""
    forms = ["de", "l", "d", "qu", "jusqu", "3", "chat"]
    candidates, rejections = build(monkeypatch, forms, {"de": ("de", "ADP")})

    assert [c.lemma for c in candidates] == ["de", "chat"]
    assert {r.form: r.reason for r in rejections} == {
        "l": "elision-fragment",
        "d": "elision-fragment",
        "qu": "elision-fragment",
        "jusqu": "elision-fragment",
        "3": "non-alphabetic",
    }


def test_real_one_letter_words_survive(monkeypatch):
    """FR-6 `a`, `à` and `y` are real French words, not fragments."""
    candidates, _ = build(
        monkeypatch, ["à", "y", "a", "z"], {"à": ("à", "ADP"), "y": ("y", "PRON")}
    )
    assert [c.source_form for c in candidates] == ["à", "y", "a"]


def test_inflections_collapse_onto_one_lemma_keeping_the_best_rank(monkeypatch):
    """FR-6 the pack is lemma-keyed (§10): est/sont/être are one entry at the best rank."""
    tags = {"est": ("être", "AUX"), "sont": ("être", "AUX"), "être": ("être", "AUX")}
    candidates, rejections = build(monkeypatch, ["est", "sont", "être", "chat"], tags)

    assert [(c.rank, c.lemma, c.source_form) for c in candidates] == [
        (1, "être", "est"),
        (2, "chat", "chat"),
    ]
    assert [r.reason for r in rejections] == ["duplicate:être", "duplicate:être"]


def test_non_entry_pos_is_dropped(monkeypatch):
    """FR-6 PROPN/X/PUNCT are never teachable entries (§3)."""
    tags = {"paris": ("Paris", "PROPN"), "xyz": ("xyz", "X"), "chat": ("chat", "NOUN")}
    candidates, rejections = build(monkeypatch, ["paris", "xyz", "chat"], tags)

    assert [c.lemma for c in candidates] == ["chat"]
    assert sorted(r.reason for r in rejections) == ["pos:PROPN", "pos:X"]


def test_function_word_flag_is_derived_from_pos(monkeypatch):
    """FR-6 is_function_word is derived (VR-7), never guessed per word."""
    tags = {"de": ("de", "ADP"), "chat": ("chat", "NOUN")}
    candidates, _ = build(monkeypatch, ["de", "chat"], tags)
    assert [c.is_function_word for c in candidates] == [True, False]


def test_ranks_are_contiguous_from_one_and_stop_at_the_limit(monkeypatch):
    """FR-6 ranks number the surviving lemmas 1..limit with no gaps where junk was."""
    forms = ["de", "l", "chat", "chien", "maison"]
    candidates, _ = build(monkeypatch, forms, {"de": ("de", "ADP")}, limit=3)
    assert [c.rank for c in candidates] == [1, 2, 3]
    assert [c.lemma for c in candidates] == ["de", "chat", "chien"]


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


def test_a_form_the_tagger_returns_nothing_for_is_rejected(monkeypatch):
    """NFR-10 an untokenizable form must be recorded, not crash on tokens[0].

    The form has to be one `_reject_reason` lets through, or this would prove the
    cleaning rules rather than the empty-token guard.
    """
    candidates, rejections = build(monkeypatch, ["vide", "chat"], {"vide": None})
    assert [c.lemma for c in candidates] == ["chat"]
    assert [r.reason for r in rejections] == ["no-tokens"]


def test_invented_lemmas_are_flagged_for_review():
    """FR-6 a lemma the corpus has never seen is reported -- no §7 rule can catch it."""
    from packgen.words import suspicious_lemmas

    pack = {
        "language_code": "fr",
        "words": [
            {"id": "fr:travail:NOUN", "lemma": "travail"},
            {"id": "fr:traval:ADJ", "lemma": "traval"},  # the lemmatizer's invention
        ],
    }
    assert suspicious_lemmas(pack) == ["fr:traval:ADJ"]
