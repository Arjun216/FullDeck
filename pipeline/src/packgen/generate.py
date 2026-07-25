"""The generation seam: prompt out, JSON back, pack assembled.

Sentences (and the confirmed lemma/POS/display/gloss/register that come with them)
are produced by hand on claude.ai, so this module owns the two sides of that
copy-paste and nothing in between. No API client, no key.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any

from packgen.rules import CLOSED_CLASS, ENTRY_POS, MAX_SCHEMA_VERSION, derive_id
from packgen.words import Candidate


@dataclass(frozen=True)
class GeneratedEntry:
    rank: int  # the candidate rank this answers
    lemma: str
    pos: str
    display: str
    gloss: str
    register: str
    example: str


def render_prompt(
    *,
    language_name: str,
    targets: list[Candidate],
    vocabulary: list[Candidate],
    rejections: dict[int, str] | None = None,
) -> str:
    """A self-contained prompt for one batch, ready to paste into claude.ai."""
    rejections = rejections or {}
    horizon = max(t.rank for t in targets)
    # Offering a word ranked below the batch would be offering a §6 violation.
    offered = [c for c in vocabulary if c.rank <= horizon]

    target_lines = "\n".join(
        f"- rank {t.rank}: `{t.source_form}` (proposed lemma `{t.lemma}`, POS `{t.pos}`)"
        + (f"\n  PREVIOUS ATTEMPT REJECTED: {rejections[t.rank]}" if t.rank in rejections else "")
        for t in targets
    )
    vocab_lines = "\n".join(f"{c.rank}. {c.lemma} ({c.pos})" for c in offered)

    return PROMPT_TEMPLATE.format(
        language_name=language_name,
        count=len(targets),
        target_lines=target_lines,
        vocab_lines=vocab_lines,
        horizon=horizon,
        retry_note=RETRY_NOTE if rejections else "",
    )


RETRY_NOTE = (
    "\nSome of these were rejected on a previous attempt; the reason is stated with the word. "
    "Fix exactly that problem.\n"
)

PROMPT_TEMPLATE = """You are building one flashcard entry per word for a {language_name} \
vocabulary app that teaches the 1000 most frequent words in frequency order.

## The words ({count})

{target_lines}
{retry_note}
## The hard rule

Each example sentence may use ONLY:
- words from the numbered vocabulary list below whose number is **strictly smaller** than the \
target word's own rank (the learner has already met those), plus
- function words (determiners, prepositions, pronouns, auxiliaries, conjunctions, particles) and \
proper nouns, which are exempt.

Any other content word — a noun, verb, adjective, adverb, numeral or interjection that is not in \
the list above the target's rank — makes the sentence invalid. Prefer sentences that need no \
exemption at all. Keep sentences short, natural and everyday; inflected forms of an allowed lemma \
are fine.

## Also confirm the linguistics

The proposed lemma and POS come from an automatic tagger and are sometimes wrong (it has produced \
`traval`/ADJ for *travaux* and `priver`/ADJ for *privé*). Return the CORRECT dictionary lemma and \
Universal-Dependencies POS for the word as it is actually used at that frequency. Allowed POS: \
NOUN VERB ADJ ADV NUM INTJ DET ADP PRON AUX CCONJ SCONJ PART. If the word is really a proper noun \
or not a teachable word, return its POS as `PROPN` and it will be dropped.

Other fields:
- `display`: the learner-facing citation form ({language_name} nouns with their article, e.g. \
`le chat`; verbs in the infinitive).
- `gloss`: the English meaning, a few words at most.
- `register`: one of `casual`, `neutral`, `formal`.

## Return format

Return ONLY a JSON array, one object per word above, no commentary:

```json
[
  {{"rank": 4, "lemma": "chat", "pos": "NOUN", "display": "le chat", "gloss": "cat", \
"register": "neutral", "example": "J'ai un chat."}}
]
```

## Vocabulary the learner has met (ranks 1–{horizon})

{vocab_lines}
"""

REQUIRED_KEYS = ("rank", "lemma", "pos", "display", "gloss", "register", "example")


def parse_response(text: str, expected_ranks: set[int]) -> tuple[list[GeneratedEntry], list[str]]:
    """Parse a claude.ai reply into entries, or into errors. Never partially trusts."""
    payload = _extract_json_array(text)
    if payload is None:
        return [], ["no JSON array found in the response"]

    entries: list[GeneratedEntry] = []
    errors: list[str] = []
    answered: set[int] = set()

    for i, raw in enumerate(payload):
        if not isinstance(raw, dict) or any(k not in raw for k in REQUIRED_KEYS):
            errors.append(f"entry {i} is missing one of {', '.join(REQUIRED_KEYS)}: {raw!r}")
            continue
        if raw["rank"] not in expected_ranks:
            errors.append(f"entry answers rank {raw['rank']}, which this batch did not ask for")
            continue
        answered.add(raw["rank"])
        entries.append(
            GeneratedEntry(
                **{k: (raw[k] if k == "rank" else str(raw[k]).strip()) for k in REQUIRED_KEYS}
            )
        )

    for rank in sorted(expected_ranks - answered):
        errors.append(f"rank {rank} was not answered")

    # All-or-nothing: a half-ingested batch is worse than a re-paste.
    return ([], errors) if errors else (entries, [])


def _extract_json_array(text: str) -> list | None:
    start, end = text.find("["), text.rfind("]")
    if start == -1 or end < start:
        return None
    try:
        payload = json.loads(text[start : end + 1])
    except json.JSONDecodeError:
        return None
    return payload if isinstance(payload, list) else None


def assemble_pack(
    language_code: str,
    language_name: str,
    candidates: list[Candidate],
    generated: list[GeneratedEntry],
    *,
    limit: int = 1000,
    pack_version: str = "1.0.0",
    created: str = "",
    model: str = "",
) -> tuple[dict[str, Any], list[str]]:
    """Build a pack dict from candidates + their generated entries, plus a drop log."""
    by_rank = {g.rank: g for g in generated}
    words: list[dict[str, Any]] = []
    drops: list[str] = []
    seen: set[tuple[str, str]] = set()

    for candidate in sorted(candidates, key=lambda c: c.rank):
        if len(words) == limit:
            break
        entry = by_rank.get(candidate.rank)
        if entry is None:
            drops.append(f"rank {candidate.rank} ({candidate.lemma}): no generated entry")
            continue
        if entry.pos not in ENTRY_POS:
            drops.append(f"rank {candidate.rank} ({entry.lemma}): POS {entry.pos} is not teachable")
            continue

        key = (entry.lemma, entry.pos)
        if key in seen:
            drops.append(
                f"rank {candidate.rank}: lemma {entry.lemma!r} was merged into an earlier entry"
            )
            continue
        seen.add(key)

        # Re-ranking preserves every `<` relation between surviving words, so a
        # sentence that satisfied §6 before the drops still satisfies it after.
        words.append(
            {
                "id": derive_id(language_code, entry.lemma, entry.pos),
                "lemma": entry.lemma,
                "display": entry.display,
                "pos": entry.pos,
                "rank": len(words) + 1,
                "register": entry.register,
                "is_function_word": entry.pos in CLOSED_CLASS,
                "gloss": entry.gloss,
                "example": entry.example,
                "aliases": [],
            }
        )

    pack = {
        "schema_version": MAX_SCHEMA_VERSION,
        "pack_version": pack_version,
        "language_code": language_code,
        "language_name": language_name,
        "base_language": "en",
        "word_count": len(words),
        "source": WORDFREQ_SOURCE,
        "generator": {"tool": "packgen", "model": model, "created": created},
        "words": words,
    }
    return pack, drops


# §4/§11, FR-16: the attribution every wordfreq-derived pack must carry.
WORDFREQ_SOURCE = {
    "name": "wordfreq",
    "url": "https://github.com/rspeer/wordfreq",
    "license": "CC-BY-SA 4.0",
    "attribution": (
        "Word-frequency data from the wordfreq project (Robyn Speer), licensed CC-BY-SA 4.0."
    ),
    "notes": (
        "ShareAlike covers the derived word-frequency list only; app code and generated example "
        "sentences are not derivative works of wordfreq."
    ),
}
