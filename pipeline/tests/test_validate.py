"""Validator rejection tests -- written before the validator exists (build-plan Phase 6.5).

Traceability convention (CLAUDE.md): each test's display name -- here, the first
line of its docstring -- starts with the requirement ID it verifies.

Why some assertions allow VR-1 alongside the expected rule: the JSON Schema
(schema/language-pack.schema.json) redundantly encodes a few semantic rules
(VR-7's function-word flag, the schema_version const). A pack breaking one of
those genuinely breaks both rules, so the assertion is "the specific rule fired,
and nothing beyond the schema echo did" -- a validator that returns every rule
still fails.
"""

from __future__ import annotations

import copy
import json

import pytest

from packgen.validate import Profile, Tier, validate_pack

from .conftest import FIXTURES, load_pack

EXPECTED = json.loads((FIXTURES / "invalid" / "expected.json").read_text(encoding="utf-8"))
REJECTION_CASES = sorted(EXPECTED["fixtures"].items())


@pytest.fixture
def valid_pack() -> dict:
    return load_pack(FIXTURES / "fr-mini.pack.json")


# --- positive control -------------------------------------------------------


def test_valid_fixture_passes_structural(valid_pack, analyzer):
    """FR-6 the fr-mini fixture is a valid Structural pack (positive control)."""
    report = validate_pack(valid_pack, analyzer=analyzer, profile=Profile.STRUCTURAL)
    assert report.ok, [str(v) for v in report.violations]


# --- rejection: one fixture per rule ---------------------------------------


@pytest.mark.parametrize(("filename", "case"), REJECTION_CASES, ids=[c[0] for c in REJECTION_CASES])
def test_invalid_fixture_reports_its_own_rule(filename, case, analyzer):
    """NFR-10 each fixture in fixtures/invalid/ fails for the exact rule it breaks."""
    pack = load_pack(FIXTURES / "invalid" / filename)
    report = validate_pack(pack, analyzer=analyzer, profile=Profile.STRUCTURAL)

    assert not report.ok, f"{filename} must be rejected"
    assert case["rule"] in report.rules, f"{filename}: expected {case['rule']}, got {report.rules}"
    assert report.rules <= {"VR-1", case["rule"]}, f"{filename}: over-reported {report.rules}"


def test_future_schema_version_fails_closed(analyzer):
    """NFR-10 a pack newer than MAX_SCHEMA_VERSION reports VR-15 alone and is not read further."""
    pack = load_pack(FIXTURES / "invalid" / "future-schema-version.pack.json")
    report = validate_pack(pack, analyzer=analyzer, profile=Profile.STRUCTURAL)
    assert report.rules == {"VR-15"}


def test_wordfreq_pack_requires_cc_by_sa_attribution(analyzer):
    """FR-16 a wordfreq-derived pack whose attribution omits CC-BY-SA 4.0 is rejected."""
    pack = load_pack(FIXTURES / "invalid" / "wordfreq-attribution.pack.json")
    report = validate_pack(pack, analyzer=analyzer, profile=Profile.STRUCTURAL)
    assert "VR-14" in report.rules


# --- §6 constraint: tiers ---------------------------------------------------


def test_sentence_tiers_match_worked_examples(valid_pack, analyzer):
    """FR-6 each sentence is tiered STRICT/RELAXED per schema §6.3, with its exempted tokens."""
    report = validate_pack(valid_pack, analyzer=analyzer, profile=Profile.STRUCTURAL)
    tiers = {t.entry_id: t for t in report.tiers}

    # "J'ai été." -- je(1) and être(2) are both in-pack and more frequent: no exemption.
    assert tiers["fr:avoir:VERB"].tier is Tier.STRICT
    assert tiers["fr:avoir:VERB"].exempted == ()

    # "J'ai un chat." -- un is a DET not in the pack: rescued by the class exemption.
    assert tiers["fr:chat:NOUN"].tier is Tier.RELAXED
    assert "un" in tiers["fr:chat:NOUN"].exempted

    # "Je suis Paul." -- être(AUX) and Paul(PROPN) are both exempt for a rank-1 target.
    assert tiers["fr:je:PRON"].tier is Tier.RELAXED
    assert report.relaxed_fraction == pytest.approx(4 / 5)


def test_content_word_rarer_than_target_is_never_exempt(valid_pack, analyzer):
    """FR-6 an open-class word rarer than the target is a hard fail, not an exemption."""
    pack = copy.deepcopy(valid_pack)
    pack["words"][0]["example"] = "Je suis un chat."  # target je(1), chat is NOUN rank 4
    report = validate_pack(pack, analyzer=analyzer, profile=Profile.STRUCTURAL)
    assert "VR-10" in report.rules


def test_content_word_absent_from_pack_is_never_exempt(valid_pack, analyzer):
    """FR-6 an open-class word with no pack entry at all is a hard fail (rank = infinity)."""
    pack = copy.deepcopy(valid_pack)
    pack["words"][4]["example"] = "J'ai un chien noir."  # chien: NOUN, not in the pack
    report = validate_pack(pack, analyzer=analyzer, profile=Profile.STRUCTURAL)
    assert "VR-10" in report.rules


def test_homograph_takes_the_best_rank(valid_pack, analyzer):
    """FR-6 a sentence token's rank is the minimum over pack entries sharing its lemma (§6.1)."""
    pack = copy.deepcopy(valid_pack)
    # A second, much rarer 'chat' entry must not make chat(4) unusable in noir(5)'s sentence.
    pack["words"].append(
        {
            "id": "fr:chat:VERB",
            "lemma": "chat",
            "display": "chatter",
            "pos": "VERB",
            "rank": 99,
            "register": "casual",
            "is_function_word": False,
            "example": "J'ai un chat.",
            "aliases": [],
        }
    )
    pack["word_count"] = 6
    report = validate_pack(pack, analyzer=analyzer, profile=Profile.STRUCTURAL)
    assert report.ok, [str(v) for v in report.violations]


# --- rules with no fixture of their own -------------------------------------


def test_untrimmed_text_is_rejected(valid_pack, analyzer):
    """NFR-10 VR-9: lemma/display/example must be trimmed and NFC-normalized."""
    pack = copy.deepcopy(valid_pack)
    pack["words"][3]["display"] = " le chat "
    report = validate_pack(pack, analyzer=analyzer, profile=Profile.STRUCTURAL)
    assert "VR-9" in report.rules


def test_gloss_requires_base_language(valid_pack, analyzer):
    """NFR-10 VR-11: a pack with glosses must declare base_language."""
    pack = copy.deepcopy(valid_pack)
    del pack["base_language"]
    report = validate_pack(pack, analyzer=analyzer, profile=Profile.STRUCTURAL)
    assert "VR-11" in report.rules


def test_alias_colliding_with_a_current_id_is_rejected(valid_pack, analyzer):
    """NFR-10 VR-13: aliases must be unique and must not shadow a live id."""
    pack = copy.deepcopy(valid_pack)
    pack["words"][3]["aliases"] = ["fr:je:PRON"]
    report = validate_pack(pack, analyzer=analyzer, profile=Profile.STRUCTURAL)
    assert "VR-13" in report.rules


def test_resolvable_audio_reference_passes(valid_pack, analyzer, tmp_path):
    """NFR-10 VR-12 rejects only *unresolvable* audio, not the presence of audio."""
    pack = copy.deepcopy(valid_pack)
    pack["words"][3]["audio"] = {"word": "fr/chat.m4a"}
    (tmp_path / "fr").mkdir()
    (tmp_path / "fr" / "chat.m4a").write_bytes(b"")

    assert validate_pack(pack, analyzer=analyzer, assets_root=tmp_path).ok
    assert "VR-12" in validate_pack(pack, analyzer=analyzer, assets_root=None).rules


# --- shippable profile ------------------------------------------------------


def test_shippable_profile_requires_1000_contiguous_ranks(valid_pack, analyzer):
    """NFR-10 VR-17/VR-18 apply to launch packs only; fixtures pass Structural."""
    report = validate_pack(valid_pack, analyzer=analyzer, profile=Profile.SHIPPABLE)
    assert report.rules == {"VR-17", "VR-18"}


# --- VR-10 vs. the tagger ---------------------------------------------------
#
# Regression tests for the false positives that stalled the real French run: 63
# of 1000 sentences were rejected and all but ~4 were correct French. The cause
# is that spaCy's *contextual* lemma and the pack's *dictionary* lemma are
# different authorities. Each case below is a real (sentence, spaCy output) pair
# taken from that run, so the scripted analyzer is not a hypothetical.


class ScriptedAnalyzer:
    """Replays exactly what spaCy said about each sentence, mistakes included.

    Keyed by sentence so a multi-entry pack does not get one entry's tokens for
    every card; unscripted sentences fall back to the shared fixture lexicon.
    """

    def __init__(self, script: dict[str, list[tuple[str, str, str]]]) -> None:
        self.script = script

    def analyze(self, sentence: str) -> list:
        from packgen.analyze import Token

        from .conftest import FakeAnalyzer

        if sentence not in self.script:
            return FakeAnalyzer().analyze(sentence)
        return [Token(*t) for t in self.script[sentence]]


def one_word_pack(lemma: str, pos: str, example: str, **over) -> dict:
    """A single-entry pack whose only job is to carry one sentence to VR-10."""
    return {
        "schema_version": 1,
        "pack_version": "0.1.0",
        "language_code": "fr",
        "language_name": "Français",
        "base_language": "en",
        "word_count": 1,
        "source": {
            "name": "hand-authored test fixture",
            "license": "CC0-1.0",
            "attribution": "Hand-authored fixture for TopWords tests; not derived from wordfreq.",
        },
        "words": [
            {
                "id": f"fr:{lemma}:{pos}",
                "lemma": lemma,
                "display": lemma,
                "pos": pos,
                "rank": 1,
                "register": "neutral",
                "is_function_word": pos in {"DET", "ADP", "PRON", "AUX", "CCONJ", "SCONJ", "PART"},
                "example": example,
                "aliases": [],
                **over,
            }
        ],
    }


def test_target_found_when_spacy_lemmatizes_it_to_another_word():
    """FR-6 'C'est ça.' contains ça even though spaCy lemmatizes it to 'cela'."""
    pack = one_word_pack("ça", "PRON", "C'est ça.")
    said = {"C'est ça.": [("C", "ce", "PRON"), ("est", "être", "AUX"), ("ça", "cela", "PRON")]}
    report = validate_pack(pack, analyzer=ScriptedAnalyzer(said))
    assert report.ok, [str(v) for v in report.violations]


def test_target_found_through_case_and_a_dropped_infinitive_r():
    """FR-6 'Écoute, ...' is a form of écouter -- spaCy returns 'Écoute', capital and all."""
    pack = one_word_pack("écouter", "VERB", "Écoute, Paul.")
    said = {"Écoute, Paul.": [("Écoute", "Écoute", "VERB"), ("Paul", "Paul", "PROPN")]}
    report = validate_pack(pack, analyzer=ScriptedAnalyzer(said))
    assert report.ok, [str(v) for v in report.violations]


def test_target_found_in_its_own_inflected_form():
    """FR-6 'Il a les cheveux longs.' is the example for cheveu -- plural is still the word."""
    pack = one_word_pack("cheveu", "NOUN", "Paul a les cheveux.")
    said = {
        "Paul a les cheveux.": [
            ("Paul", "Paul", "PROPN"),
            ("a", "avoir", "AUX"),
            ("les", "le", "DET"),
            ("cheveux", "cheveux", "ADJ"),
        ]
    }
    report = validate_pack(pack, analyzer=ScriptedAnalyzer(said))
    assert report.ok, [str(v) for v in report.violations]


def test_the_target_is_never_its_own_foreign_content_word():
    """FR-6 a target matched by surface form must be skipped, not flagged as an offender."""
    pack = one_word_pack("monsieur", "NOUN", "C'est monsieur.")
    # spaCy agrees on the surface but gives no lemma the pack would recognise.
    # Every other token is closed-class, so the target is the only thing that
    # could be flagged -- which is exactly what this test forbids.
    said = {
        "C'est monsieur.": [
            ("C", "ce", "PRON"),
            ("est", "être", "AUX"),
            ("monsieur", "Monsieur", "NOUN"),
        ]
    }
    report = validate_pack(pack, analyzer=ScriptedAnalyzer(said))
    assert report.ok, [str(v) for v in report.violations]


def test_punctuation_tagged_as_a_content_word_is_ignored():
    """FR-6 the hyphen in 'es-tu' is tagged NOUN by spaCy; a token with no letters is not a word."""
    pack = one_word_pack("où", "ADV", "Où es-tu ?")
    said = {
        "Où es-tu ?": [
            ("Où", "où", "ADV"),
            ("es", "être", "AUX"),
            ("-", "-", "NOUN"),
            ("tu", "tu", "PRON"),
        ]
    }
    report = validate_pack(pack, analyzer=ScriptedAnalyzer(said))
    assert report.ok, [str(v) for v in report.violations]


def test_the_pack_outranks_the_tagger_on_function_words():
    """FR-6 a pack entry flagged is_function_word stays exempt when spaCy mistags it.

    The rank check must not be what rescues it: `pour` here is *rarer* than the
    target, so only the class exemption can pass this sentence -- and spaCy has
    called it a NOUN. The pack's POS was corrected and reviewed; the tagger's was
    not, so the pack wins.
    """
    pack = one_word_pack("ça", "PRON", "C'est pour ça.")
    pack["word_count"] = 2
    pack["words"].append(
        {
            "id": "fr:pour:ADP",
            "lemma": "pour",
            "display": "pour",
            "pos": "ADP",
            "rank": 2,
            "register": "neutral",
            "is_function_word": True,
            "example": "C'est pour ça.",
            "aliases": [],
        }
    )
    said = {
        "C'est pour ça.": [
            ("C", "ce", "PRON"),
            ("est", "être", "AUX"),
            ("pour", "pour", "NOUN"),
            ("ça", "cela", "PRON"),
        ]
    }
    report = validate_pack(pack, analyzer=ScriptedAnalyzer(said))
    assert report.ok, [str(v) for v in report.violations]


def test_a_genuinely_rarer_content_word_still_fails(valid_pack):
    """FR-6 the tagger-tolerance above must not rescue a real §6 violation."""
    pack = copy.deepcopy(valid_pack)
    pack["words"][0]["example"] = "Je suis un chat."  # target je(1), chat is NOUN rank 4
    said = {
        "Je suis un chat.": [
            ("Je", "je", "PRON"),
            ("suis", "être", "AUX"),
            ("un", "un", "DET"),
            ("chat", "chat", "NOUN"),
        ]
    }
    report = validate_pack(pack, analyzer=ScriptedAnalyzer(said))
    assert [v.entry_id for v in report.violations] == ["fr:je:PRON"]


def test_an_already_met_word_survives_a_mangled_lemma():
    """FR-6 a word the learner has met stays met when spaCy mangles *its* lemma too.

    The tagger that drops `rester`'s final -r on the target does it to every other
    word in the sentence as well. `rester` is in the pack and more frequent than
    the target, so this sentence satisfies §6 -- only the lemma spelling differs.
    """
    pack = one_word_pack("tandis", "SCONJ", "Je reste tandis qu'il part.")
    pack["word_count"] = 2
    pack["words"][0]["rank"] = 2
    pack["words"].append(
        {
            "id": "fr:rester:VERB",
            "lemma": "rester",
            "display": "rester",
            "pos": "VERB",
            "rank": 1,
            "register": "neutral",
            "is_function_word": False,
            "example": "Je reste.",
            "aliases": [],
        }
    )
    said = {
        "Je reste tandis qu'il part.": [
            ("Je", "je", "PRON"),
            ("reste", "reste", "VERB"),  # spaCy: `reste`, not `rester`
            ("tandis", "tandis", "SCONJ"),
            ("qu", "que", "SCONJ"),
            ("il", "il", "PRON"),
        ],
        "Je reste.": [("Je", "je", "PRON"), ("reste", "reste", "VERB")],
    }
    report = validate_pack(pack, analyzer=ScriptedAnalyzer(said))
    assert report.ok, [str(v) for v in report.violations]


# --- documented §6 exceptions -----------------------------------------------
#
# At the very top of a frequency list the constraint can be genuinely
# unsatisfiable: `se` is the 25th most common French word, and every verb ranked
# above it is an auxiliary, so no reflexive sentence can be built. A human may
# waive §6 for a named entry; nothing else is waivable.


def test_an_exception_waives_the_sentence_rule_for_its_entry():
    """FR-6 a documented §6 exception lets a named entry through."""
    pack = one_word_pack("se", "PRON", "Ça se fait.")
    said = {
        "Ça se fait.": [("Ça", "cela", "PRON"), ("se", "se", "PRON"), ("fait", "faire", "VERB")]
    }
    analyzer = ScriptedAnalyzer(said)
    assert "VR-10" in validate_pack(pack, analyzer=analyzer).rules

    report = validate_pack(pack, analyzer=analyzer, exceptions={"fr:se:PRON": "no lexical verb"})
    assert report.ok, [str(v) for v in report.violations]


def test_a_waived_violation_is_still_reported():
    """NFR-10 an exception is a record, not a silence -- the waived rule stays visible."""
    pack = one_word_pack("se", "PRON", "Ça se fait.")
    said = {
        "Ça se fait.": [("Ça", "cela", "PRON"), ("se", "se", "PRON"), ("fait", "faire", "VERB")]
    }
    report = validate_pack(
        pack, analyzer=ScriptedAnalyzer(said), exceptions={"fr:se:PRON": "no lexical verb"}
    )
    assert [v.rule for v in report.waived] == ["VR-10"]
    assert report.waived[0].entry_id == "fr:se:PRON"


def test_an_exception_waives_nothing_but_the_sentence_rule(valid_pack, analyzer):
    """NFR-10 §6 is a judgment call; ids, ranks and attribution are not."""
    pack = copy.deepcopy(valid_pack)
    pack["words"][3]["display"] = " le chat "  # VR-9, on the same entry
    report = validate_pack(
        pack, analyzer=analyzer, exceptions={"fr:chat:NOUN": "waive the sentence rule only"}
    )
    assert "VR-9" in report.rules


def test_an_exception_does_not_cover_a_different_entry(valid_pack, analyzer):
    """NFR-10 an exception names one entry and excuses only that one."""
    pack = copy.deepcopy(valid_pack)
    pack["words"][0]["example"] = "Je suis un chat."  # target je(1) fails on chat(4)
    report = validate_pack(pack, analyzer=analyzer, exceptions={"fr:chat:NOUN": "unrelated"})
    assert "VR-10" in report.rules
