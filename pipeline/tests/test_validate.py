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
