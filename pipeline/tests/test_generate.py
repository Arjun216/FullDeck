"""Prompt/ingest/assembly logic -- written before packgen.generate exists.

Sentences are produced by hand on claude.ai rather than through the API, so the
testable logic here is the seam either side of that copy-paste: what the prompt is
allowed to offer, and what the pack builder does with what comes back.
"""

from __future__ import annotations

import pytest

from packgen.generate import GeneratedEntry, assemble_pack, parse_response, render_prompt
from packgen.words import Candidate


def candidate(rank: int, lemma: str, pos: str = "NOUN") -> Candidate:
    return Candidate(
        lemma=lemma, pos=pos, rank=rank, is_function_word=pos == "DET", source_form=lemma
    )


CANDIDATES = [
    candidate(1, "le", "DET"),
    candidate(2, "être", "AUX"),
    candidate(3, "avoir", "VERB"),
    candidate(4, "chat"),
    candidate(5, "chien"),
    candidate(6, "maison"),
]


# --- prompt rendering -------------------------------------------------------


def test_prompt_lists_its_targets_and_their_allowed_vocabulary():
    """FR-6 a batch prompt offers exactly the words ranked above its last target."""
    prompt = render_prompt(
        language_name="Français",
        targets=CANDIDATES[3:5],  # chat(4), chien(5)
        vocabulary=CANDIDATES,
    )
    assert "chat" in prompt and "chien" in prompt
    # Nothing ranked below the batch is offered -- a sentence built from it could
    # never satisfy §6 for any target in this batch.
    assert "maison" not in prompt


def test_retry_prompt_states_why_the_previous_sentence_was_rejected():
    """FR-6 a regeneration prompt names the offending token, not just 'try again'."""
    prompt = render_prompt(
        language_name="Français",
        targets=CANDIDATES[3:4],
        vocabulary=CANDIDATES,
        rejections={4: "content word 'maison' (NOUN) is not more frequent than the target"},
    )
    assert "maison" in prompt


# --- response parsing -------------------------------------------------------


VALID_RESPONSE = """Here you go!
```json
[
  {"rank": 4, "lemma": "chat", "pos": "NOUN", "display": "le chat",
   "gloss": "cat", "register": "neutral", "example": "Le chat a été le chat."}
]
```
"""


def test_parses_a_fenced_json_response():
    """FR-6 a claude.ai reply is accepted with its prose and code fence around it."""
    entries, errors = parse_response(VALID_RESPONSE, expected_ranks={4})
    assert not errors
    assert entries == [
        GeneratedEntry(
            rank=4,
            lemma="chat",
            pos="NOUN",
            display="le chat",
            gloss="cat",
            register="neutral",
            example="Le chat a été le chat.",
        )
    ]


def test_rejects_entries_for_ranks_the_batch_did_not_ask_for():
    """NFR-10 a reply that answers the wrong word is an error, not silent corruption."""
    entries, errors = parse_response(VALID_RESPONSE, expected_ranks={7})
    assert not entries
    assert any("4" in e for e in errors)


def test_reports_missing_ranks_and_malformed_entries():
    """NFR-10 missing fields and missing ranks are reported, never defaulted."""
    entries, errors = parse_response('[{"rank": 4, "lemma": "chat"}]', expected_ranks={4, 5})
    assert not entries
    assert any("missing" in e for e in errors)
    assert [e for e in errors if "not answered" in e] == [
        "rank 4 was not answered",
        "rank 5 was not answered",
    ]


def test_unparseable_response_is_an_error_not_a_crash():
    """NFR-10 a reply with no JSON at all reports an error."""
    entries, errors = parse_response("sorry, I can't help with that", expected_ranks={4})
    assert not entries
    assert errors


# --- pack assembly ----------------------------------------------------------


def generated(rank, lemma, pos, **kw):
    return GeneratedEntry(
        rank=rank,
        lemma=lemma,
        pos=pos,
        display=kw.get("display", lemma),
        gloss=kw.get("gloss", "x"),
        register=kw.get("register", "neutral"),
        example=kw.get("example", f"Le {lemma}."),
    )


def test_assembled_pack_derives_ids_and_flags_from_the_confirmed_pos():
    """FR-6 the corrected lemma/POS drives id and is_function_word, not spaCy's guess."""
    # spaCy proposed travaux -> traval/ADJ; the generator corrects it to travail/NOUN.
    candidates = [candidate(1, "traval", "ADJ")]
    pack, _ = assemble_pack(
        "fr", "Français", candidates, [generated(1, "travail", "NOUN")], limit=1000
    )
    entry = pack["words"][0]
    assert entry["id"] == "fr:travail:NOUN"
    assert entry["lemma"] == "travail"
    assert entry["is_function_word"] is False


def test_assembly_reranks_contiguously_after_drops():
    """FR-6 ranks in the finished pack are contiguous from 1 (VR-18) even when entries drop out."""
    pack, drops = assemble_pack(
        "fr", "Français", CANDIDATES, [generated(1, "le", "DET"), generated(4, "chat", "NOUN")]
    )
    assert [w["rank"] for w in pack["words"]] == [1, 2]
    assert pack["word_count"] == 2
    assert len(drops) == 4  # the four candidates with no generated entry


def test_assembly_drops_a_lemma_the_generator_merged_into_an_earlier_entry():
    """FR-6 if a correction collides with an existing entry, the rarer one is dropped (VR-3)."""
    candidates = [candidate(1, "chat"), candidate(2, "chats")]
    pack, drops = assemble_pack(
        "fr", "Français", candidates, [generated(1, "chat", "NOUN"), generated(2, "chat", "NOUN")]
    )
    assert pack["word_count"] == 1
    assert any("chat" in d for d in drops)


def test_assembly_stops_at_the_limit():
    """FR-6 the candidate buffer above 1000 is trimmed to exactly the limit (VR-17)."""
    gen = [generated(c.rank, c.lemma, c.pos) for c in CANDIDATES]
    pack, _ = assemble_pack("fr", "Français", CANDIDATES, gen, limit=3)
    assert pack["word_count"] == 3


def test_assembled_pack_carries_the_wordfreq_attribution():
    """FR-16 every generated pack carries the CC-BY-SA 4.0 credit in its metadata."""
    pack, _ = assemble_pack("fr", "Français", CANDIDATES[:1], [generated(1, "le", "DET")])
    assert pack["source"]["name"] == "wordfreq"
    assert "CC-BY-SA 4.0" in pack["source"]["attribution"]


def test_assembled_pack_validates(analyzer):
    """FR-6 an assembled pack passes the Structural profile end to end."""
    from packgen.validate import validate_pack

    candidates = [candidate(1, "je", "PRON"), candidate(2, "chat")]
    gen = [
        generated(1, "je", "PRON", example="Je suis Paul.", display="je"),
        # not "J'ai un chat." -- avoir is not in this two-word pack, so §6 would reject it.
        generated(2, "chat", "NOUN", example="Je suis un chat.", display="le chat"),
    ]
    pack, _ = assemble_pack("fr", "Français", candidates, gen)
    report = validate_pack(pack, analyzer=analyzer)
    assert report.ok, [str(v) for v in report.violations]


@pytest.mark.parametrize("bad_pos", ["PROPN", "PUNCT", "BOGUS"])
def test_assembly_drops_a_generator_pos_outside_the_entry_set(bad_pos):
    """NFR-10 a corrected POS that is not entry-valid (§3) drops the word, never a bad pack."""
    pack, drops = assemble_pack(
        "fr", "Français", [candidate(1, "paul")], [generated(1, "Paul", bad_pos)]
    )
    assert pack["word_count"] == 0
    assert drops
