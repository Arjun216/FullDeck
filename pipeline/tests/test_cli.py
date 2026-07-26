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

    retry = (workspace / "work/fr/retry/001.md").read_text(encoding="utf-8")
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


def test_prompts_clears_stale_batches(workspace):
    """NFR-10 re-running with a different --batch does not leave mis-aligned prompts."""
    assert cli.main(["words", "fr", "--pool", "40", "--limit", "3"]) == 0
    assert cli.main(["prompts", "fr", "--batch", "1"]) == 0
    assert len(list((workspace / "work/fr/prompts").glob("*.md"))) == 3

    assert cli.main(["prompts", "fr", "--batch", "3"]) == 0
    assert [p.name for p in (workspace / "work/fr/prompts").glob("*.md")] == ["001.md"]


# --- automated generation via the Claude Code CLI ---------------------------


def fake_claude(monkeypatch, replies):
    """Stand in for `claude --print`. `replies` is a list consumed per invocation."""
    calls = []

    def run(argv, **kwargs):
        calls.append(argv[-1])  # the prompt is the last argv element
        import subprocess

        return subprocess.CompletedProcess(argv, 0, replies.pop(0), "")

    monkeypatch.setattr("subprocess.run", run)
    return calls


def test_generate_writes_replies_where_pack_reads_them(workspace, monkeypatch):
    """FR-6 `generate` answers each prompt and drops it in responses/, like a paste would."""
    assert cli.main(["words", "fr", "--pool", "40", "--limit", "3"]) == 0
    assert cli.main(["prompts", "fr", "--batch", "3"]) == 0

    calls = fake_claude(monkeypatch, [json.dumps(VALID_ENTRIES)])
    assert cli.main(["generate", "fr", "--batch", "3"]) == 0

    assert len(calls) == 1 and "de" in calls[0]  # the prompt text was passed through
    assert (workspace / "work/fr/responses/001.json").exists()
    assert cli.main(["pack", "fr", "--batch", "3", "--limit", "3", "--profile", "structural"]) == 0


def test_generate_skips_prompts_already_answered(workspace, monkeypatch):
    """FR-6 a re-run resumes instead of re-asking -- 24 batches must survive an interruption."""
    assert cli.main(["words", "fr", "--pool", "40", "--limit", "3"]) == 0
    assert cli.main(["prompts", "fr", "--batch", "3"]) == 0
    write_response(workspace, VALID_ENTRIES)

    calls = fake_claude(monkeypatch, [])
    assert cli.main(["generate", "fr", "--batch", "3"]) == 0
    assert calls == []


def test_generate_keeps_only_replies_that_parse(workspace, monkeypatch):
    """NFR-10 a truncated reply is quarantined, not saved as if it were an answer."""
    assert cli.main(["words", "fr", "--pool", "40", "--limit", "3"]) == 0
    assert cli.main(["prompts", "fr", "--batch", "3"]) == 0

    fake_claude(monkeypatch, ["I'm afraid I can't do that."])
    assert cli.main(["generate", "fr", "--batch", "3"]) == 1

    assert not (workspace / "work/fr/responses/001.json").exists()
    assert (workspace / "work/fr/responses/001.json.bad").exists()


def test_generate_reports_a_failing_cli_without_dying(workspace, monkeypatch):
    """NFR-10 a `claude` failure on one batch does not abort the other 23."""
    assert cli.main(["words", "fr", "--pool", "40", "--limit", "3"]) == 0
    assert cli.main(["prompts", "fr", "--batch", "1"]) == 0

    import subprocess

    def run(argv, **kwargs):
        # "- rank 1:" appears only in the first prompt's target list; every prompt
        # mentions `de`, since it heads the shared vocabulary list.
        if "- rank 1:" in argv[-1]:
            return subprocess.CompletedProcess(argv, 1, "", "Not logged in")
        return subprocess.CompletedProcess(argv, 0, json.dumps([VALID_ENTRIES[1]]), "")

    monkeypatch.setattr("subprocess.run", run)
    assert cli.main(["generate", "fr", "--batch", "1"]) == 1

    assert not (workspace / "work/fr/responses/001.json").exists()
    assert (workspace / "work/fr/responses/002.json").exists()  # later batches still ran


def test_a_word_that_fails_twice_stops_the_regeneration_loop(workspace, monkeypatch):
    """NFR-10 an unsatisfiable word must not spin the retry loop forever."""
    assert cli.main(["words", "fr", "--pool", "40", "--limit", "3"]) == 0

    broken = [dict(e) for e in VALID_ENTRIES]
    broken[2]["example"] = "Le chat et le chien."  # content words not in the pack
    write_response(workspace, broken)
    pack_args = ["pack", "fr", "--batch", "3", "--limit", "3", "--profile", "structural"]

    assert cli.main(pack_args) == 1
    assert (workspace / "work/fr/retry/001.md").exists()

    # The retry answered, but no better -- the same word fails again.
    (workspace / "work/fr/retry/answers").mkdir(parents=True, exist_ok=True)
    (workspace / "work/fr/retry/answers/0003.json").write_text(
        json.dumps([broken[2]]), encoding="utf-8"
    )
    assert cli.main(pack_args) == 1
    assert list((workspace / "work/fr/retry").glob("*.md")) == []

    # With no prompt left, `generate --retry` exits non-zero and `|| break` fires.
    assert cli.main(["generate", "fr", "--retry"]) == 1


def test_a_retry_answer_overrides_the_batch_answer(workspace, monkeypatch):
    """FR-6 the regenerated word wins over the batch reply it is fixing."""
    assert cli.main(["words", "fr", "--pool", "40", "--limit", "3"]) == 0

    broken = [dict(e) for e in VALID_ENTRIES]
    broken[2]["example"] = "Le chat et le chien."  # content words not in the pack
    write_response(workspace, broken)
    assert cli.main(["pack", "fr", "--batch", "3", "--limit", "3", "--profile", "structural"]) == 1

    fixed = json.dumps([VALID_ENTRIES[2]])
    (workspace / "work/fr/retry/answers").mkdir(parents=True, exist_ok=True)
    (workspace / "work/fr/retry/answers/0003.json").write_text(fixed, encoding="utf-8")
    assert cli.main(["pack", "fr", "--batch", "3", "--limit", "3", "--profile", "structural"]) == 0

    pack = json.loads((workspace / "packs/fr.pack.json").read_text(encoding="utf-8"))
    assert pack["words"][2]["example"] == "C'est Paul et Paul."


def test_running_pack_twice_is_not_mistaken_for_a_stuck_loop(workspace, monkeypatch):
    """NFR-10 only a word that was regenerated and still fails counts as stuck."""
    assert cli.main(["words", "fr", "--pool", "40", "--limit", "3"]) == 0

    broken = [dict(e) for e in VALID_ENTRIES]
    broken[2]["example"] = "Le chat et le chien."
    write_response(workspace, broken)
    pack_args = ["pack", "fr", "--batch", "3", "--limit", "3", "--profile", "structural"]

    assert cli.main(pack_args) == 1
    assert (workspace / "work/fr/retry/001.md").exists()

    # Nothing was regenerated in between, so the prompt must survive a second look.
    assert cli.main(pack_args) == 1
    assert (workspace / "work/fr/retry/001.md").exists()


def test_failing_words_share_one_retry_prompt(workspace):
    """FR-6 retries are batched: the vocabulary list is sent once, not once per word.

    One prompt per failing word re-sent the whole vocabulary each time -- 84k
    tokens to fix 26 sentences on the first real run.
    """
    assert cli.main(["words", "fr", "--pool", "40", "--limit", "3"]) == 0

    broken = [dict(e) for e in VALID_ENTRIES]
    broken[1]["example"] = "Le chat."  # chat: content word, not in the pack
    broken[2]["example"] = "Le chien."  # chien too, and no form of `et`
    write_response(workspace, broken)

    assert cli.main(["pack", "fr", "--batch", "3", "--limit", "3", "--profile", "structural"]) == 1

    prompts = sorted((workspace / "work/fr/retry").glob("*.md"))
    assert [p.name for p in prompts] == ["001.md"]
    manifest = json.loads((workspace / "work/fr/retry/targets.json").read_text(encoding="utf-8"))
    assert manifest == {"001": [2, 3]}


def test_a_batched_retry_reply_is_split_into_per_rank_answers(workspace, monkeypatch):
    """FR-6 one prompt may fix several words; each answer is stored under its own rank.

    Prompts are re-batched every round, so an answer keyed to a prompt would be
    orphaned as soon as the failing set changed. Keyed to its rank, it survives.
    """
    assert cli.main(["words", "fr", "--pool", "40", "--limit", "3"]) == 0

    broken = [dict(e) for e in VALID_ENTRIES]
    broken[1]["example"] = "Le chat."
    broken[2]["example"] = "Le chien."
    write_response(workspace, broken)
    pack_args = ["pack", "fr", "--batch", "3", "--limit", "3", "--profile", "structural"]
    assert cli.main(pack_args) == 1

    fake_claude(monkeypatch, [json.dumps([VALID_ENTRIES[1], VALID_ENTRIES[2]])])
    assert cli.main(["generate", "fr", "--retry"]) == 0

    answers = workspace / "work/fr/retry/answers"
    assert sorted(p.name for p in answers.glob("*.json")) == ["0002.json", "0003.json"]

    # And those answers are what `pack` picks up.
    assert cli.main(pack_args) == 0
    pack = json.loads((workspace / "packs/fr.pack.json").read_text(encoding="utf-8"))
    assert pack["words"][2]["example"] == "C'est Paul et Paul."


def test_retry_prompts_offer_the_corrected_lemmas(workspace):
    """FR-6 the retry vocabulary uses the lemmas the generator confirmed, not the tagger's.

    candidates.json holds spaCy's raw lemmas, and on French those include real
    errors -- `lui` arrives as `luire`, `ça` as `cela`. Offering those as "words
    already learned" invites a sentence the pack cannot satisfy.
    """
    assert cli.main(["words", "fr", "--pool", "40", "--limit", "3"]) == 0

    entries = [dict(e) for e in VALID_ENTRIES]
    entries[1]["lemma"] = "les"  # the generator corrects rank 2's lemma
    entries[2]["example"] = "Le chien."  # and rank 3 fails, so it gets a retry prompt
    write_response(workspace, entries)

    assert cli.main(["pack", "fr", "--batch", "3", "--limit", "3", "--profile", "structural"]) == 1
    retry = (workspace / "work/fr/retry/001.md").read_text(encoding="utf-8")
    safe = retry.split("## Words already learned")[1]
    assert "les" in safe.split()
