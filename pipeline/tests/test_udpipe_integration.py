"""The real Hindi model. Skips when it is not downloaded -- it is 25 MB and not in git.

`packgen models hi` fetches it; CI caches it on its pinned checksum.
"""

from __future__ import annotations

import gc

import pytest

from packgen.analyze import UDPipeAnalyzer
from packgen.rules import ENTRY_POS


@pytest.fixture(scope="module")
def udpipe_hi() -> UDPipeAnalyzer:
    analyzer = UDPipeAnalyzer("hi")
    try:
        analyzer.analyze("घर")
    except LookupError as exc:  # model not downloaded -> skip, don't fail
        pytest.skip(str(exc))
    return analyzer


@pytest.mark.parametrize("form", ["के", "है", "में", "और", "एक", "नहीं", "को", "पर"])
def test_fr6_hindis_most_frequent_forms_tag_inside_entry_pos(udpipe_hi, form):
    """FR-6 a form tagged outside ENTRY_POS is dropped by words.py.

    The old `xx_sent_ud_sm` mapping tagged everything as nothing, so every Hindi
    form was dropped and the pack came out empty rather than merely degraded.
    """
    tokens = udpipe_hi.analyze(form)
    assert tokens, f"{form} produced no tokens"
    assert tokens[0].pos in ENTRY_POS, (form, tokens[0].pos)


def test_nfr10_the_pipeline_outlives_a_garbage_collection(udpipe_hi):
    """NFR-10 UDPipe's Pipeline holds a raw C pointer to the Model, not a Python
    reference. If the Model is collected, the next process() call segfaults the
    interpreter -- exit 139, no exception, nothing to catch."""
    udpipe_hi.analyze("घर")
    gc.collect()
    assert udpipe_hi.analyze("घर")[0].lemma == "घर"


def test_fr6_a_hindi_sentence_tokenizes_into_lemmas_and_tags(udpipe_hi):
    """FR-6 the §6 check needs lemma + POS for every word of a sentence.

    `है` comes back as `होना`, not `है`: UD Hindi lemmatizes to the bare stem and
    the pack cites the infinitive, so the analyzer reconciles the two. See
    normalize_lemma.
    """
    tokens = [t for t in udpipe_hi.analyze("यह एक अच्छा घर है।") if t.pos != "PUNCT"]
    assert [t.lemma for t in tokens] == ["यह", "एक", "अच्छा", "घर", "होना"]
    assert [t.pos for t in tokens] == ["PRON", "NUM", "ADJ", "NOUN", "AUX"]
