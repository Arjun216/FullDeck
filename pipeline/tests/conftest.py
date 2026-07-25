from __future__ import annotations

import json
import re
from pathlib import Path

import pytest

from packgen.analyze import Token

REPO = Path(__file__).resolve().parents[2]
FIXTURES = REPO / "fixtures"
SCHEMA = REPO / "schema" / "language-pack.schema.json"


def load_pack(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class FakeAnalyzer:
    """Deterministic stand-in for spaCy over the fixture vocabulary.

    Unit tests must not download a model or depend on tagger drift, so the
    validator's rules are proved against a fixed lexicon here. That real spaCy
    agrees on these same sentences is a separate integration test.
    """

    # surface form (lowercased, apostrophe stripped) -> (lemma, POS)
    LEXICON = {
        "je": ("je", "PRON"),
        "j": ("je", "PRON"),
        "suis": ("être", "AUX"),
        "est": ("être", "AUX"),
        "été": ("être", "AUX"),
        "c": ("ce", "PRON"),
        "ai": ("avoir", "VERB"),
        "avoir": ("avoir", "VERB"),
        "un": ("un", "DET"),
        "chat": ("chat", "NOUN"),
        "noir": ("noir", "ADJ"),
        "paul": ("Paul", "PROPN"),
        "chien": ("chien", "NOUN"),
    }

    def analyze(self, sentence: str) -> list[Token]:
        tokens = []
        for raw in re.findall(r"\w+", sentence, flags=re.UNICODE):
            lemma, pos = self.LEXICON.get(raw.lower(), (raw.lower(), "X"))
            tokens.append(Token(raw, lemma, pos))
        return tokens


@pytest.fixture
def analyzer() -> FakeAnalyzer:
    return FakeAnalyzer()
