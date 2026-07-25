"""Sentence analysis seam.

The §6 constraint needs every sentence tokenized, lemmatized and POS-tagged. That
is spaCy's job -- but the validator must stay fast, offline and deterministic in
unit tests, so it depends on this Protocol and never on spaCy directly.
"""

from __future__ import annotations

import functools
from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class Token:
    text: str
    lemma: str
    pos: str  # Universal POS tag


class Analyzer(Protocol):
    def analyze(self, sentence: str) -> list[Token]: ...


class SpacyAnalyzer:
    """The real one. Loads a spaCy pipeline lazily so importing this module is cheap."""

    # Model per language. sm is enough for lemma+POS on high-frequency vocabulary;
    # ponytail: bump to _md only if Phase 13's spot-check blames the tagger.
    MODELS = {"fr": "fr_core_news_sm", "hi": "xx_sent_ud_sm"}

    def __init__(self, language_code: str) -> None:
        self.language_code = language_code

    @functools.cached_property
    def _nlp(self):
        import spacy

        try:
            model = self.MODELS[self.language_code]
        except KeyError:
            raise LookupError(
                f"no spaCy model registered for {self.language_code!r}; "
                f"add one to SpacyAnalyzer.MODELS"
            ) from None
        try:
            return spacy.load(model, disable=["ner", "parser"])
        except OSError:
            raise LookupError(
                f"spaCy model {model!r} is not installed. Run: uv run spacy download {model}"
            ) from None

    def analyze(self, sentence: str) -> list[Token]:
        return [Token(t.text, t.lemma_, t.pos_) for t in self._nlp(sentence)]
