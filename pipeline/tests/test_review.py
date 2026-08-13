"""The human spot-check of example sentences (spec D4, Phase 13 item 5).

Logic, so tested first: which sentences a seed draws, and how a filled-in
verdict sheet is read back. The CLI wiring around it is glue and is covered in
`test_cli.py`.
"""

from __future__ import annotations

import pytest

from packgen import review


def pack(count: int = 20) -> dict:
    return {
        "language_code": "fr",
        "words": [
            {
                "id": f"fr:w{n}:NOUN",
                "lemma": f"w{n}",
                "display": f"w{n}",
                "pos": "NOUN",
                "rank": n,
                "gloss": f"gloss {n}",
                "example": f"Sentence {n}.",
            }
            for n in range(1, count + 1)
        ],
    }


def test_d4_the_same_seed_draws_the_same_sentences():
    first = review.sample(pack()["words"], count=5, seed=13)
    second = review.sample(pack()["words"], count=5, seed=13)
    assert [row["id"] for row in first] == [row["id"] for row in second]


def test_d4_a_different_seed_draws_a_different_sample():
    thirteen = {row["id"] for row in review.sample(pack(200)["words"], count=20, seed=13)}
    fourteen = {row["id"] for row in review.sample(pack(200)["words"], count=20, seed=14)}
    assert thirteen != fourteen


def test_d4_the_sample_is_ordered_by_rank_so_it_reads_like_the_pack():
    rows = review.sample(pack(100)["words"], count=10, seed=1)
    assert [row["rank"] for row in rows] == sorted(row["rank"] for row in rows)


def test_d4_asking_for_more_than_the_pack_holds_returns_the_whole_pack():
    rows = review.sample(pack(5)["words"], count=100, seed=1)
    assert len(rows) == 5


def test_d4_a_blank_verdict_is_unreviewed_not_approved():
    sheet = review.to_csv(review.sample(pack()["words"], count=3, seed=1))
    assert review.read_verdicts(sheet).unreviewed == 3
    assert review.read_verdicts(sheet).rejected == {}


def test_d4_rejections_carry_the_reviewers_note_to_the_retry_prompt():
    sheet = (
        "id,rank,display,pos,gloss,example,verdict,note\r\n"
        "fr:w1:NOUN,1,w1,NOUN,gloss 1,Sentence 1.,ok,\r\n"
        "fr:w2:NOUN,2,w2,NOUN,gloss 2,Sentence 2.,bad,no one says this\r\n"
    )
    verdicts = review.read_verdicts(sheet)
    assert verdicts.rejected == {"fr:w2:NOUN": "no one says this"}
    assert verdicts.accepted == 1
    assert verdicts.unreviewed == 0


def test_d4_a_rejection_without_a_note_still_counts():
    sheet = "id,rank,display,pos,gloss,example,verdict,note\r\nfr:w1:NOUN,1,w1,NOUN,g,S.,bad,\r\n"
    assert review.read_verdicts(sheet).rejected == {"fr:w1:NOUN": ""}


def test_d4_an_unrecognised_verdict_is_an_error_not_a_silent_pass():
    sheet = "id,rank,display,pos,gloss,example,verdict,note\r\nfr:w1:NOUN,1,w1,NOUN,g,S.,maybe,\r\n"
    with pytest.raises(review.SheetError, match="maybe"):
        review.read_verdicts(sheet)


def test_d4_verdicts_are_case_and_space_insensitive():
    sheet = (
        "id,rank,display,pos,gloss,example,verdict,note\r\n"
        "fr:w1:NOUN,1,w1,NOUN,g,S., OK ,\r\n"
        "fr:w2:NOUN,2,w2,NOUN,g,S.,Bad ,clunky\r\n"
    )
    verdicts = review.read_verdicts(sheet)
    assert verdicts.accepted == 1
    assert verdicts.rejected == {"fr:w2:NOUN": "clunky"}


def test_d4_reviewed_counts_only_what_a_person_actually_judged():
    sheet = (
        "id,rank,display,pos,gloss,example,verdict,note\r\n"
        "fr:w1:NOUN,1,w1,NOUN,g,S.,ok,\r\n"
        "fr:w2:NOUN,2,w2,NOUN,g,S.,bad,\r\n"
        "fr:w3:NOUN,3,w3,NOUN,g,S.,,\r\n"
    )
    assert review.read_verdicts(sheet).reviewed == 2


def test_d4_a_sheet_missing_the_verdict_column_is_an_error():
    with pytest.raises(review.SheetError, match="verdict"):
        review.read_verdicts("id,rank,display\r\nfr:w1:NOUN,1,w1\r\n")
