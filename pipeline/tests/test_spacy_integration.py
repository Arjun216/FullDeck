"""The fake analyzer's word for it is not enough.

test_validate.py proves the *rules* against a fixed lexicon. This proves the rules
still hold when the lemmas come from the real French model -- i.e. that the fake
isn't quietly disagreeing with spaCy about `été -> être` or `J'` -> `je`.
"""

from __future__ import annotations

import pytest

from packgen.analyze import SpacyAnalyzer
from packgen.validate import Tier, validate_pack

from .conftest import FIXTURES, FakeAnalyzer, load_pack

FIXTURE_SENTENCES = [
    "Je suis Paul.",
    "C'est Paul.",
    "J'ai été.",
    "J'ai un chat.",
    "J'ai un chat noir.",
]


@pytest.fixture(scope="module")
def spacy_fr() -> SpacyAnalyzer:
    analyzer = SpacyAnalyzer("fr")
    try:
        analyzer.analyze("test")
    except LookupError as exc:  # model not installed -> skip, don't fail
        pytest.skip(str(exc))
    return analyzer


@pytest.mark.parametrize("sentence", FIXTURE_SENTENCES)
def test_fake_analyzer_agrees_with_spacy_on_lemmas(spacy_fr, sentence):
    """FR-6 the unit-test fake reports the same lemma sequence real spaCy does.

    Lemmas only: spaCy flips between AUX and VERB for `avoir`/`être` depending on
    whether they head the clause, and §6 already treats both as passing here. The
    tier assertions below are what pin the POS-sensitive behavior.
    """
    real = [t.lemma for t in spacy_fr.analyze(sentence) if t.pos != "PUNCT"]
    assert [t.lemma for t in FakeAnalyzer().analyze(sentence)] == real


def test_valid_pack_passes_under_real_spacy(spacy_fr):
    """FR-6 fr-mini validates with real French lemmatization, not just the fake."""
    report = validate_pack(load_pack(FIXTURES / "fr-mini.pack.json"), analyzer=spacy_fr)
    assert report.ok, [str(v) for v in report.violations]
    tiers = {t.entry_id: t.tier for t in report.tiers}
    assert tiers["fr:avoir:VERB"] is Tier.STRICT


@pytest.mark.parametrize(
    "filename", ["sentence-content-violation.pack.json", "sentence-missing-target.pack.json"]
)
def test_sentence_fixtures_are_rejected_under_real_spacy(spacy_fr, filename):
    """FR-6 the §6 violations are caught by real lemmatization too."""
    report = validate_pack(load_pack(FIXTURES / "invalid" / filename), analyzer=spacy_fr)
    assert "VR-10" in report.rules
