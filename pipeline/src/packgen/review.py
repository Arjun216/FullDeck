"""The human spot-check of example sentences (spec D4).

Every rule a machine can check is already checked — VR-1…VR-18 run on every
`pack`. What no rule catches is a sentence that is *valid and wrong*: correct
grammar, only permitted vocabulary, and nothing a French speaker would ever say.
That needs a person, and a person will not read 1000 sentences. So: draw a
sample, record verdicts beside it, and feed the rejects back into the same retry
loop the validator's own failures use.

The sheet is CSV rather than JSON or Markdown. It is the one format that opens
in Numbers, in Excel and in a text editor, and the reviewer is not a programmer
at the moment they are doing this.
"""

from __future__ import annotations

import csv
import io
import random
from dataclasses import dataclass, field

COLUMNS = ["id", "rank", "display", "pos", "gloss", "example", "verdict", "note"]

ACCEPT = {"ok", "y", "yes", "good"}
REJECT = {"bad", "n", "no", "reject"}


class SheetError(Exception):
    """The verdict sheet cannot be read. Never guessed around: a mis-parsed
    verdict either regenerates a sentence that was fine or, worse, keeps one the
    reviewer rejected."""


def sample(words: list[dict], count: int, seed: int) -> list[dict]:
    """`count` entries drawn without replacement, reproducibly.

    Seeded because a spot-check that cannot be re-drawn cannot be re-run: "the
    100 sentences we checked before the beta" has to still mean something after
    the pack is regenerated. Sorted by rank on the way out, so the sheet reads
    from the commonest word down rather than in shuffle order.
    """
    drawn = random.Random(seed).sample(words, min(count, len(words)))
    return sorted(drawn, key=lambda word: word["rank"])


def to_csv(words: list[dict]) -> str:
    """The sheet, with `verdict` and `note` left empty for the reviewer."""
    buffer = io.StringIO()
    # `lineterminator` because csv defaults to CRLF (RFC 4180) and this file is
    # committed — git rewrites the line endings on every checkout otherwise, and
    # a sheet full of verdicts should not show up as a whole-file diff.
    writer = csv.DictWriter(buffer, fieldnames=COLUMNS, extrasaction="ignore", lineterminator="\n")
    writer.writeheader()
    for word in words:
        writer.writerow({**{"verdict": "", "note": ""}, **word})
    return buffer.getvalue()


@dataclass(frozen=True)
class Verdicts:
    """What came back. `rejected` maps entry id to the reviewer's note, which is
    quoted into the retry prompt — "no one says this" tells the generator more
    than "rejected" does."""

    rejected: dict[str, str] = field(default_factory=dict)
    accepted: int = 0
    unreviewed: int = 0

    @property
    def reviewed(self) -> int:
        return self.accepted + len(self.rejected)


def read_verdicts(sheet: str) -> Verdicts:
    """Parse a filled-in sheet.

    A blank verdict is *unreviewed*, not approved — the difference matters when
    the question is "did we actually check 100 sentences". An unrecognised
    verdict raises rather than being treated as either: a typo that silently
    approves a sentence defeats the point of the exercise.
    """
    reader = csv.DictReader(io.StringIO(sheet))
    if reader.fieldnames is None or "verdict" not in reader.fieldnames:
        raise SheetError(f"no 'verdict' column in the sheet; columns are {reader.fieldnames}")

    rejected: dict[str, str] = {}
    accepted = 0
    unreviewed = 0
    for line, row in enumerate(reader, start=2):
        verdict = (row.get("verdict") or "").strip().lower()
        if not verdict:
            unreviewed += 1
        elif verdict in ACCEPT:
            accepted += 1
        elif verdict in REJECT:
            rejected[row["id"]] = (row.get("note") or "").strip()
        else:
            raise SheetError(
                f"line {line}: unrecognised verdict {verdict!r}. "
                f"Use one of {sorted(ACCEPT)} or {sorted(REJECT)}, or leave it blank."
            )
    return Verdicts(rejected=rejected, accepted=accepted, unreviewed=unreviewed)
