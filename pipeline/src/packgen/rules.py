"""Constants shared by every part of the pipeline.

Single source of truth for the tag sets in docs/language-pack-schema.md §3 and the
schema version the pipeline emits/accepts (§9). Kept dependency-free so the
validator can import it without dragging in spaCy.
"""

from __future__ import annotations

# §9: the highest schema_version this pipeline understands. A pack above this
# fails closed (VR-15) rather than being read with the wrong rules.
MAX_SCHEMA_VERSION = 1

# §3 Universal Dependencies tags. CLOSED_CLASS is "the function words" -- it drives
# both VR-7 (is_function_word == pos in CLOSED_CLASS) and the §6 exemption.
CLOSED_CLASS = frozenset({"DET", "ADP", "PRON", "AUX", "CCONJ", "SCONJ", "PART"})
OPEN_CLASS = frozenset({"NOUN", "VERB", "ADJ", "ADV", "NUM", "INTJ"})
ENTRY_POS = CLOSED_CLASS | OPEN_CLASS

# Tags that may appear in a sentence but never as a pack entry (§3).
PROPER_NOUN = "PROPN"
IGNORED_IN_SENTENCES = frozenset({"PUNCT", "SYM", "SPACE"})

# Shippable profile (VR-17/18).
SHIPPABLE_WORD_COUNT = 1000

# VR-14: a wordfreq-derived pack must carry the CC-BY-SA 4.0 credit (§11, FR-16).
WORDFREQ_LICENSE = "CC-BY-SA 4.0"


def derive_id(language_code: str, lemma: str, pos: str) -> str:
    """VR-4 / §8: ids are derived, never authored."""
    return f"{language_code}:{lemma}:{pos}"
