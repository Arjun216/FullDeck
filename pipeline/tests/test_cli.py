"""End-to-end wiring of the four stages.

Glue, not logic -- tested alongside rather than first (CLAUDE.md). It runs the real
wordfreq list and the real spaCy model over a three-word pack, so a broken path,
a bad rank offset or a mis-mapped retry shows up here rather than after 24 pastes.

The example sentences below are deliberately mechanical rather than good French:
this test is about the plumbing, and a three-word vocabulary cannot express much.
"""

from __future__ import annotations

import json

import pytest

from packgen import cli


@pytest.fixture
def workspace(tmp_path, monkeypatch):
    monkeypatch.setattr(cli, "WORK", tmp_path / "work")
    monkeypatch.setattr(cli, "PACKS", tmp_path / "packs")
    return tmp_path


def write_response(workspace, entries):
    path = workspace / "work" / "fr" / "responses" / "001.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(entries, ensure_ascii=False), encoding="utf-8")


VALID_ENTRIES = [
    # Only function words and the proper noun Paul, so every sentence satisfies §6
    # even with a three-word vocabulary.
    {
        "rank": 1,
        "lemma": "de",
        "pos": "ADP",
        "display": "de",
        "gloss": "of",
        "register": "neutral",
        "example": "C'est de Paul.",
    },
    {
        "rank": 2,
        "lemma": "le",
        "pos": "DET",
        "display": "le",
        "gloss": "the",
        "register": "neutral",
        "example": "C'est le Paul.",
    },
    {
        "rank": 3,
        "lemma": "et",
        "pos": "CCONJ",
        "display": "et",
        "gloss": "and",
        "register": "neutral",
        "example": "C'est Paul et Paul.",
    },
]


def test_words_then_prompts_then_pack(workspace, capsys):
    """FR-6 the four stages hand off to each other and produce a validated pack."""
    assert cli.main(["words", "fr", "--pool", "40", "--limit", "3"]) == 0
    candidates = json.loads((workspace / "work/fr/candidates.json").read_text(encoding="utf-8"))
    assert [c["rank"] for c in candidates] == [1, 2, 3]

    assert cli.main(["prompts", "fr", "--batch", "3"]) == 0
    prompt = (workspace / "work/fr/prompts/001.md").read_text(encoding="utf-8")
    assert all(c["lemma"] in prompt for c in candidates)

    write_response(workspace, VALID_ENTRIES)
    assert cli.main(["pack", "fr", "--batch", "3", "--limit", "3", "--profile", "structural"]) == 0

    pack = json.loads((workspace / "packs/fr.pack.json").read_text(encoding="utf-8"))
    assert pack["word_count"] == 3
    assert pack["words"][0]["id"] == "fr:de:ADP"
    assert "CC-BY-SA 4.0" in pack["source"]["attribution"]


def test_pack_writes_a_retry_prompt_for_the_word_that_failed(workspace, capsys):
    """FR-6 a §6 violation names the word and regenerates only that word."""
    assert cli.main(["words", "fr", "--pool", "40", "--limit", "3"]) == 0

    entries = [dict(e) for e in VALID_ENTRIES]
    entries[2]["example"] = "Le chat et le chien."  # chat/chien: content words, not in the pack
    write_response(workspace, entries)

    assert cli.main(["pack", "fr", "--batch", "3", "--limit", "3", "--profile", "structural"]) == 1
    assert not (workspace / "packs/fr.pack.json").exists()

    retry = (workspace / "work/fr/retry/0003.md").read_text(encoding="utf-8")
    assert "PREVIOUS ATTEMPT REJECTED" in retry
    assert "chat" in retry


def test_a_response_for_an_unasked_rank_is_refused(workspace):
    """NFR-10 a mismatched paste is refused outright, not half-ingested."""
    assert cli.main(["words", "fr", "--pool", "40", "--limit", "3"]) == 0
    write_response(workspace, [{**VALID_ENTRIES[0], "rank": 99}])
    assert cli.main(["pack", "fr", "--batch", "3", "--limit", "3", "--profile", "structural"]) == 1
    assert not (workspace / "packs/fr.pack.json").exists()


def test_validate_command_accepts_the_fixture_pack(capsys):
    """NFR-10 `packgen validate` re-checks any pack file on demand."""
    from .conftest import FIXTURES

    assert cli.main(["validate", str(FIXTURES / "fr-mini.pack.json")]) == 0
    assert cli.main(["validate", str(FIXTURES / "invalid" / "dup-id.pack.json")]) == 1
