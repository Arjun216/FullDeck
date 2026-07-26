"""Language-pack validator -- the machine-checked half of docs/language-pack-schema.md §7.

Pure logic (no IO beyond reading the JSON Schema file), so it is built test-first
against fixtures/invalid/: every rule has a fixture that breaks exactly it.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any
from unicodedata import normalize

import jsonschema

from packgen.analyze import Analyzer
from packgen.rules import (
    CLOSED_CLASS,
    IGNORED_IN_SENTENCES,
    MAX_SCHEMA_VERSION,
    PROPER_NOUN,
    SHIPPABLE_WORD_COUNT,
    WORDFREQ_LICENSE,
    derive_id,
)

# A lemma with no pack entry is "infinitely rare" -- never a strict pass (§6.1).
_RANK_INFINITY = float("inf")


class Profile(Enum):
    STRUCTURAL = "structural"
    SHIPPABLE = "shippable"


class Tier(Enum):
    STRICT = "strict"
    RELAXED = "relaxed"


@dataclass(frozen=True)
class Violation:
    rule: str  # "VR-3"
    message: str
    entry_id: str | None = None

    def __str__(self) -> str:
        where = f" [{self.entry_id}]" if self.entry_id else ""
        return f"{self.rule}{where}: {self.message}"


@dataclass(frozen=True)
class SentenceTier:
    entry_id: str
    tier: Tier
    exempted: tuple[str, ...] = ()


@dataclass
class Report:
    violations: list[Violation] = field(default_factory=list)
    tiers: list[SentenceTier] = field(default_factory=list)
    # §6 violations a human has waived: not blocking, but never silent.
    waived: list[Violation] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.violations

    @property
    def rules(self) -> set[str]:
        return {v.rule for v in self.violations}

    @property
    def relaxed_fraction(self) -> float:
        if not self.tiers:
            return 0.0
        return sum(t.tier is Tier.RELAXED for t in self.tiers) / len(self.tiers)


SCHEMA_PATH = Path(__file__).resolve().parents[3] / "schema" / "language-pack.schema.json"


def validate_pack(
    pack: dict[str, Any],
    *,
    analyzer: Analyzer,
    profile: Profile = Profile.STRUCTURAL,
    assets_root: Path | None = None,
    schema_path: Path = SCHEMA_PATH,
    exceptions: dict[str, str] | None = None,
) -> Report:
    """Check `pack` against every rule in §7 for the given profile.

    `exceptions` maps an entry id to why §6 is waived for it. Only VR-10 can be
    waived: at the top of a frequency list the constraint is sometimes genuinely
    unsatisfiable -- `se` is the 25th most common French word and every verb above
    it is an auxiliary, so no reflexive sentence exists. Every other rule is
    mechanical, and a pack that breaks one is wrong rather than awkward.
    """
    report = Report()

    # VR-15 first, and alone: a pack from a newer contract must not be read with
    # this contract's rules. §9 fail-closed -- stop here rather than emit noise.
    version = pack.get("schema_version")
    if not isinstance(version, int) or version > MAX_SCHEMA_VERSION:
        report.violations.append(
            Violation("VR-15", f"schema_version {version!r} > supported {MAX_SCHEMA_VERSION}")
        )
        return report

    _check_schema(pack, report, schema_path)

    # Everything below reads fields the schema check may have just condemned, so it
    # works off the entries that are structurally usable and lets VR-1 speak for the rest.
    words = [w for w in pack.get("words", []) if _usable(w)]

    _check_pack_level(pack, words, report)
    _check_entries(pack, words, report, assets_root)
    _check_sentences(words, report, analyzer)

    if profile is Profile.SHIPPABLE:
        _check_shippable(pack, words, report)

    waivable = exceptions or {}
    report.waived = [v for v in report.violations if v.rule == "VR-10" and v.entry_id in waivable]
    if report.waived:
        blocking = set(map(id, report.waived))
        report.violations = [v for v in report.violations if id(v) not in blocking]

    return report


def _usable(entry: Any) -> bool:
    return isinstance(entry, dict) and all(
        isinstance(entry.get(k), t)
        for k, t in (("id", str), ("lemma", str), ("pos", str), ("rank", int), ("example", str))
    )


def _check_pack_level(pack: dict[str, Any], words: list[dict], report: Report) -> None:
    all_words = pack.get("words", [])
    if pack.get("word_count") != len(all_words):
        report.violations.append(
            Violation("VR-2", f"word_count {pack.get('word_count')!r} != {len(all_words)} entries")
        )

    for dup in _duplicates(w["id"] for w in words):
        report.violations.append(Violation("VR-3", "duplicate id", dup))
    for dup in _duplicates(w["rank"] for w in words):
        report.violations.append(Violation("VR-5", f"duplicate rank {dup}"))

    if any("gloss" in w for w in words) and not pack.get("base_language"):
        report.violations.append(
            Violation("VR-11", "entries carry a gloss but base_language is unset")
        )

    _check_attribution(pack.get("source") or {}, report)

    code = pack.get("language_code")
    for w in words:
        if not w["id"].startswith(f"{code}:"):
            report.violations.append(
                Violation("VR-16", f"id prefix != language_code {code!r}", w["id"])
            )
    # ponytail: VR-16's manifest half needs the pack manifest, which lands with the
    # Swift loader in Phase 7. Checked there, not here.


def _check_attribution(source: dict[str, Any], report: Report) -> None:
    """VR-14 / §11 / FR-16."""
    for field_name in ("license", "attribution"):
        if not str(source.get(field_name) or "").strip():
            report.violations.append(Violation("VR-14", f"source.{field_name} is missing or empty"))

    derived_from_wordfreq = "wordfreq" in str(source.get("name", "")).lower()
    attribution = str(source.get("attribution", ""))
    if derived_from_wordfreq and WORDFREQ_LICENSE not in attribution:
        report.violations.append(
            Violation(
                "VR-14",
                f"wordfreq-derived pack must credit {WORDFREQ_LICENSE} in source.attribution",
            )
        )


def _check_entries(
    pack: dict[str, Any], words: list[dict], report: Report, assets_root: Path | None
) -> None:
    code = str(pack.get("language_code", ""))
    seen_aliases: set[str] = set()
    live_ids = {w["id"] for w in words}

    for w in words:
        expected = derive_id(code, w["lemma"], w["pos"])
        if w["id"] != expected:
            report.violations.append(
                Violation("VR-4", f"id is not its derivation {expected!r}", w["id"])
            )

        if w.get("is_function_word") != (w["pos"] in CLOSED_CLASS):
            report.violations.append(
                Violation(
                    "VR-7",
                    f"is_function_word must be {w['pos'] in CLOSED_CLASS} for {w['pos']}",
                    w["id"],
                )
            )

        for field_name in ("lemma", "display", "example"):
            text = w.get(field_name)
            if isinstance(text, str) and (text != text.strip() or text != normalize("NFC", text)):
                report.violations.append(
                    Violation("VR-9", f"{field_name} is not trimmed and NFC-normalized", w["id"])
                )

        for ref in (w.get("audio") or {}).values():
            if assets_root is None or not (assets_root / ref).exists():
                report.violations.append(
                    Violation("VR-12", f"audio reference {ref!r} does not resolve", w["id"])
                )

        for alias in w.get("aliases") or []:
            if alias in seen_aliases or alias in live_ids:
                report.violations.append(
                    Violation(
                        "VR-13",
                        f"alias {alias!r} collides with a live id or another alias",
                        w["id"],
                    )
                )
            seen_aliases.add(alias)


def _deinflect(word: str) -> str:
    """Drop one plural/feminine ending so a surface form meets its own lemma.

    French marks these with -s, -e or -x (`cheveu`/`cheveux`, `demi`/`demie`).
    Short words are left alone: at three letters or fewer the ending usually *is*
    the word.
    """
    return word[:-1] if len(word) > 3 and word[-1] in "sex" else word


def _is_target(token, lemma: str) -> bool:
    """Is this token an occurrence of the entry's own word?

    Lemma equality alone is not enough. spaCy reports a *contextual* lemma while
    the pack carries the *dictionary* lemma Claude confirmed, and on French they
    disagree constantly -- `ça`->`cela`, `lui`->`luire`, `sous`->`sou`. Believing
    only the tagger rejected 48 of 1000 correct sentences on the first real run.

    So the target is matched on any cheap agreement between the two. This is
    deliberately generous: it decides both "does the sentence use its word" and
    "which token is the target and therefore exempt", and those must stay the
    same predicate or a word gets flagged as its own foreign content word.
    """
    text, lem, target = token.text.casefold(), token.lemma.casefold(), lemma.casefold()
    if target in (text, lem):
        return True
    # spaCy routinely drops a French infinitive's final -r: `rester` -> `reste`.
    if target.endswith("r") and lem == target[:-1]:
        return True
    if _deinflect(text) == _deinflect(target) or _deinflect(lem) == _deinflect(target):
        return True
    # Hyphenated and multiword lemmas tokenize either way: `week-end` arrives as
    # `week` + `end`, while `delà` arrives inside `au-delà`.
    return text in target.replace("-", " ").split() or target in text.replace("-", " ").split()


def _spellings(lemma: str) -> set[str]:
    """A pack lemma plus the spellings a tagger is apt to return instead of it."""
    lemma = lemma.casefold()
    keys = {lemma, _deinflect(lemma)}
    if lemma.endswith("r"):
        keys.add(lemma[:-1])
    return keys


def _met_rank(token, index: dict[str, int]) -> float:
    """The best pack rank this token could be, or infinity if it is not in the pack.

    The mirror of _is_target: the tagger that mangles a target's lemma mangles
    every other word in the sentence too, so a word the learner has already met
    must not be counted as unmet because spaCy returned `reste` where the pack
    says `rester`. Matching on both the lemma and the surface form, each also
    de-inflected, is what keeps the two halves of this rule consistent.
    """
    keys = {token.lemma.casefold(), token.text.casefold()}
    keys |= {_deinflect(k) for k in keys} | {k + "r" for k in keys}
    return min((index[k] for k in keys if k in index), default=_RANK_INFINITY)


def _check_sentences(words: list[dict], report: Report, analyzer: Analyzer) -> None:
    """VR-10 -- the §6 example-sentence frequency constraint."""
    best_rank: dict[str, int] = {}
    function_words: set[str] = set()
    for w in words:
        for key in _spellings(w["lemma"]):
            best_rank[key] = min(best_rank.get(key, w["rank"]), w["rank"])
        if w.get("is_function_word"):
            function_words.add(w["lemma"].casefold())

    for w in words:
        tokens = [
            t
            for t in analyzer.analyze(w["example"])
            # A token with no letters is not a word: spaCy tags the hyphen in
            # `es-tu` as a NOUN, which no amount of rephrasing would fix.
            if t.pos not in IGNORED_IN_SENTENCES and any(ch.isalpha() for ch in t.text)
        ]
        lemma = w["lemma"]
        present = any(_is_target(t, lemma) for t in tokens) or (
            lemma.casefold() in w["example"].casefold()
        )
        if not present:
            report.violations.append(
                Violation("VR-10", f"sentence contains no form of {lemma!r}", w["id"])
            )
            continue

        exempted: list[str] = []
        failed = False
        for t in tokens:
            if _is_target(t, lemma):
                continue  # the target itself
            if _met_rank(t, best_rank) < w["rank"]:
                continue  # strict pass: in-pack and more frequent
            if t.pos in CLOSED_CLASS or t.pos == PROPER_NOUN:
                exempted.append(t.text)
                continue
            # The pack's POS was corrected by the generator and is reviewed; the
            # tagger's in-sentence POS is the unreliable one. Where they differ on
            # a word the pack already calls a function word, the pack wins.
            if t.lemma.casefold() in function_words or t.text.casefold() in function_words:
                exempted.append(t.text)
                continue
            report.violations.append(
                Violation(
                    "VR-10",
                    f"content word {t.text!r} ({t.pos}) is not more frequent than the target",
                    w["id"],
                )
            )
            failed = True

        if not failed:
            report.tiers.append(
                SentenceTier(w["id"], Tier.RELAXED if exempted else Tier.STRICT, tuple(exempted))
            )


def _check_shippable(pack: dict[str, Any], words: list[dict], report: Report) -> None:
    if pack.get("word_count") != SHIPPABLE_WORD_COUNT:
        report.violations.append(
            Violation(
                "VR-17",
                f"a shippable pack has {SHIPPABLE_WORD_COUNT} words, not {pack.get('word_count')}",
            )
        )
    if {w["rank"] for w in words} != set(range(1, SHIPPABLE_WORD_COUNT + 1)):
        report.violations.append(
            Violation("VR-18", f"ranks must be exactly 1..{SHIPPABLE_WORD_COUNT} with no gaps")
        )


def _duplicates(values) -> list:
    seen, dupes = set(), []
    for v in values:
        if v in seen and v not in dupes:
            dupes.append(v)
        seen.add(v)
    return dupes


def _check_schema(pack: dict[str, Any], report: Report, schema_path: Path) -> None:
    """VR-1 (and, redundantly, the type/enum layer of VR-6/VR-7/VR-8/VR-9)."""
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    validator = jsonschema.Draft202012Validator(schema)
    for err in sorted(validator.iter_errors(pack), key=lambda e: list(e.absolute_path)):
        where = "/".join(str(p) for p in err.absolute_path) or "(root)"
        report.violations.append(Violation("VR-1", f"{where}: {err.message}"))
