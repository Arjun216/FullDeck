"""Sentence analysis seam.

The §6 constraint needs every sentence tokenized, lemmatized and POS-tagged. That
is spaCy's job -- but the validator must stay fast, offline and deterministic in
unit tests, so it depends on this Protocol and never on spaCy directly.
"""

from __future__ import annotations

import functools
from dataclasses import dataclass
from pathlib import Path
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

    # Model per language. French uses _md because _sm measurably is not good enough:
    # on the first real 1000-word run it lemmatized the infinitive `vivre` to `vivr`
    # and tagged `hiver` as a VERB. Swapping _sm -> _md cut VR-10 failures from 15 to
    # 11 with the sentence rule already fixed, and removes the truncated-lemma class
    # (`parl`, `arriv`, `personn`) entirely.
    # No "hi" entry on purpose. It used to map to xx_sent_ud_sm, which made Hindi
    # read as supported: that model is a sentence segmenter with no tagger and no
    # lemmatizer, so pos_ came back empty and words.py dropped every single form.
    # spaCy publishes no Hindi pipeline with POS -- Hindi goes through UDPipe.
    MODELS = {"fr": "fr_core_news_md"}

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


@dataclass(frozen=True)
class RemoteModel:
    """A model file that is not distributed as a wheel, pinned by checksum."""

    filename: str
    url: str
    sha256: str


# UDPipe models are plain files, so they land beside the other working data
# rather than in site-packages. Not committed -- see `packgen models`.
MODELS_DIR = Path(__file__).resolve().parents[2] / "work" / "models"


def parse_conllu(conllu: str) -> list[Token]:
    """CoNLL-U text -> tokens. Pure, so the parsing rules are testable with no model.

    Skips comments, multiword-range rows (`1-2`) and empty nodes (`1.1`): those
    repeat material the plain rows already carry, and double-counting a word would
    corrupt the §6 check that reads these tokens.
    """
    tokens: list[Token] = []
    for line in conllu.splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < 4:
            continue
        index = fields[0]
        if "-" in index or "." in index:
            continue
        # `_` is CoNLL-U for "not annotated"; an empty lemma is what words.py
        # already knows how to reject.
        lemma = "" if fields[2] == "_" else fields[2]
        tokens.append(Token(text=fields[1], lemma=lemma, pos=fields[3]))
    return tokens


class UDPipeAnalyzer:
    """UDPipe 1 for languages spaCy has no POS model for.

    spaCy publishes no Hindi pipeline with a tagger at all, so the second language
    needed a second backend. UD 2.5's hindi-hdtb model covers 16 of the 17 UPOS
    tags, which is every tag in CLOSED_CLASS and OPEN_CLASS.

    Stanza would score higher on the benchmarks and would also pull PyTorch into a
    CI job that installs in ~70s. Not worth it here: the prompts already ask Claude
    to correct lemma and POS (French needs that too), so the tagger's job is only
    to get the candidate list built -- plausible lemma, a POS inside ENTRY_POS so
    the form is not dropped, and dedup of inflections.
    """

    MODELS = {
        "hi": RemoteModel(
            filename="hindi-hdtb-ud-2.5-191206.udpipe",
            url=(
                "https://raw.githubusercontent.com/jwijffels/udpipe.models.ud.2.5/"
                "master/inst/udpipe-ud-2.5-191206/hindi-hdtb-ud-2.5-191206.udpipe"
            ),
            sha256="d7a77399e6eccee9103d8df9b441ec25ba6ba9f4db453eed3f4ddb77acdd7f2a",
        )
    }

    def __init__(self, language_code: str, models_dir: Path = MODELS_DIR) -> None:
        self.language_code = language_code
        self.models_dir = models_dir

    @functools.cached_property
    def _pipeline(self):
        from ufal.udpipe import Model, Pipeline

        try:
            spec = self.MODELS[self.language_code]
        except KeyError:
            raise LookupError(
                f"no UDPipe model registered for {self.language_code!r}; "
                f"add one to UDPipeAnalyzer.MODELS"
            ) from None

        path = self.models_dir / spec.filename
        if not path.is_file():
            raise LookupError(
                f"UDPipe model {spec.filename!r} is not downloaded. "
                f"Run: uv run packgen models {self.language_code}"
            )
        model = Model.load(str(path))
        if model is None:
            raise LookupError(f"UDPipe could not load {path}")

        # Pipeline stores a raw C pointer to the model, NOT a Python reference.
        # Let the Model be garbage-collected and the next process() call segfaults
        # the interpreter -- no exception, no traceback. Holding it here is the fix.
        self._model = model
        return Pipeline(model, "tokenize", Pipeline.DEFAULT, Pipeline.DEFAULT, "conllu")

    def analyze(self, sentence: str) -> list[Token]:
        from ufal.udpipe import ProcessingError

        error = ProcessingError()
        conllu = self._pipeline.process(sentence, error)
        if error.occurred():
            raise RuntimeError(f"UDPipe failed on {sentence!r}: {error.message}")
        return parse_conllu(conllu)
