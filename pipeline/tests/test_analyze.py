"""CoNLL-U parsing rules -- pure text in, tokens out, no model on disk."""

from __future__ import annotations

import contextlib
import hashlib
import io

import pytest

from packgen.analyze import (
    RemoteModel,
    SpacyAnalyzer,
    UDPipeAnalyzer,
    download_model,
    make_analyzer,
    parse_conllu,
)

CONLLU = """\
# newdoc
# sent_id = 1
# text = यह एक घर है।
1\tयह\tयह\tPRON\tPRP\t_\t3\tnsubj\t_\t_
2\tएक\tएक\tNUM\tQC\t_\t3\tnummod\t_\t_
3\tघर\tघर\tNOUN\tNN\t_\t0\troot\t_\t_
4\tहै\tहै\tAUX\tVM\t_\t3\tcop\t_\t_
5\t।\t।\tPUNCT\tSYM\t_\t3\tpunct\t_\t_
"""


def test_fr6_comment_lines_are_not_tokens():
    """FR-6 CoNLL-U carries `# text =` metadata that is not part of the sentence."""
    tokens = parse_conllu(CONLLU)
    assert [t.text for t in tokens] == ["यह", "एक", "घर", "है", "।"]
    assert [t.pos for t in tokens] == ["PRON", "NUM", "NOUN", "AUX", "PUNCT"]


def test_fr6_multiword_ranges_and_empty_nodes_are_skipped():
    """FR-6 a `1-2` row repeats rows 1 and 2; counting it doubles a word in the §6 check."""
    text = (
        "1-2\tdel\t_\t_\t_\t_\t_\t_\t_\t_\n"
        "1\tde\tde\tADP\t_\t_\t_\t_\t_\t_\n"
        "2\tel\tel\tDET\t_\t_\t_\t_\t_\t_\n"
        "1.1\tghost\tghost\tNOUN\t_\t_\t_\t_\t_\t_\n"
    )
    assert [t.text for t in parse_conllu(text)] == ["de", "el"]


def test_nfr10_an_unspecified_lemma_is_empty_not_an_underscore():
    """NFR-10 CoNLL-U writes `_` for "not annotated"; carrying it through would put a
    literal underscore in the pack, and words.py would accept it as a real lemma."""
    assert parse_conllu("1\tfoo\t_\tNOUN\t_\t_\t_\t_\t_\t_\n")[0].lemma == ""


def test_fr6_the_analyzer_table_maps_each_language_to_its_backend():
    """FR-6 adding a language is a row in ANALYZERS, not a branch at three call sites.

    Neither call loads a model -- both backends resolve theirs lazily in a
    cached_property -- so this needs nothing on disk.
    """
    assert isinstance(make_analyzer("fr"), SpacyAnalyzer)
    assert isinstance(make_analyzer("hi"), UDPipeAnalyzer)


def test_nfr10_an_unregistered_language_says_what_to_add():
    """NFR-10 the failure names the table to edit rather than an AttributeError later."""
    with pytest.raises(LookupError, match="ANALYZERS"):
        make_analyzer("xx")


# --- pinned model downloads -------------------------------------------------


def fake_urlopen(payload: bytes):
    @contextlib.contextmanager
    def opener(url, *args, **kwargs):
        yield io.BytesIO(payload)

    return opener


def spec_for(payload: bytes) -> RemoteModel:
    return RemoteModel(
        filename="test.udpipe",
        url="https://example.invalid/test.udpipe",
        sha256=hashlib.sha256(payload).hexdigest(),
    )


def test_fr6_a_model_is_downloaded_to_the_models_directory(tmp_path, monkeypatch):
    """FR-6 the model UDPipe does not ship as a wheel is fetched on demand."""
    payload = b"pretend this is 25MB of model"
    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen(payload))

    path = download_model(spec_for(payload), tmp_path)

    assert path == tmp_path / "test.udpipe"
    assert path.read_bytes() == payload


def test_nfr10_a_model_whose_checksum_differs_is_refused(tmp_path, monkeypatch):
    """NFR-10 the URL is a mirror's master branch. A model that changed upstream must
    fail loudly, not quietly alter every pack generated afterwards."""
    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen(b"something else"))
    spec = spec_for(b"the real model")

    with pytest.raises(LookupError, match="SHA-256"):
        download_model(spec, tmp_path)

    assert list(tmp_path.iterdir()) == [], "a rejected download must leave nothing behind"


def test_nfr10_a_model_already_on_disk_is_not_downloaded_again(tmp_path, monkeypatch):
    """NFR-10 25 MB per run is not a no-op; the CI cache depends on this being cheap."""
    payload = b"pretend this is 25MB of model"
    (tmp_path / "test.udpipe").write_bytes(payload)

    def explode(*args, **kwargs):
        raise AssertionError("should not have downloaded")

    monkeypatch.setattr("urllib.request.urlopen", explode)
    assert download_model(spec_for(payload), tmp_path) == tmp_path / "test.udpipe"
