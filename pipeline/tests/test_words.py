"""Candidate-list cleaning rules.

wordfreq's raw list is surface tokens, and its noise is language-specific. spaCy
itself is not under test here -- a stub stands in for it so the *rules* (what gets
dropped, what gets merged, how ranks are assigned) are checked deterministically.
"""

from __future__ import annotations

from packgen.words import build_candidates


class StubToken:
    def __init__(self, lemma: str, pos: str) -> None:
        self.lemma_, self.pos_ = lemma, pos


class StubNLP:
    """Stands in for a loaded spaCy pipeline: form -> (lemma, POS)."""

    def __init__(self, tags: dict[str, tuple[str, str]]) -> None:
        self.tags = tags

    def pipe(self, forms):
        for form in forms:
            yield [StubToken(*self.tags.get(form, (form, "NOUN")))]


def build(monkeypatch, forms, tags, **kwargs):
    monkeypatch.setattr("wordfreq.top_n_list", lambda lang, n: forms[:n])
    return build_candidates("fr", nlp=StubNLP(tags), pool=len(forms), **kwargs)


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
