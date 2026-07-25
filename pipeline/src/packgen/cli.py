"""packgen CLI -- four stages, with the copy-paste to claude.ai between 2 and 3.

    packgen words fr        # wordfreq + spaCy  -> work/fr/candidates.json
    packgen prompts fr      # candidates        -> work/fr/prompts/NNN.md   [paste these]
    packgen pack fr         # responses/NNN.json-> packs/fr.pack.json + validation report
    packgen validate <path> # re-check any pack against the §7 rules

`pack` is re-runnable: it validates what it built and writes retry prompts for
exactly the words that failed, so the regeneration loop is paste -> pack -> paste.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import sys
from datetime import date
from pathlib import Path

from packgen.analyze import SpacyAnalyzer
from packgen.generate import assemble_pack, parse_response, render_prompt
from packgen.validate import Profile, validate_pack
from packgen.words import Candidate, build_candidates

ROOT = Path(__file__).resolve().parents[2]  # pipeline/
WORK = ROOT / "work"
PACKS = ROOT / "packs"

LANGUAGE_NAMES = {"fr": "Français", "hi": "हिन्दी"}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="packgen", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p_words = sub.add_parser("words", help="build the ranked candidate list from wordfreq")
    p_words.add_argument("language")
    p_words.add_argument("--pool", type=int, default=3000, help="raw wordfreq tokens to consider")
    p_words.add_argument(
        "--limit", type=int, default=1200, help="candidates to keep (buffer > 1000)"
    )

    p_prompts = sub.add_parser("prompts", help="write paste-ready batch prompts")
    p_prompts.add_argument("language")
    p_prompts.add_argument("--batch", type=int, default=50, help="target words per prompt")

    p_pack = sub.add_parser("pack", help="assemble + validate the pack from pasted responses")
    p_pack.add_argument("language")
    p_pack.add_argument("--limit", type=int, default=1000)
    p_pack.add_argument("--batch", type=int, default=50)
    p_pack.add_argument(
        "--profile", choices=[p.value for p in Profile], default=Profile.SHIPPABLE.value
    )

    p_validate = sub.add_parser("validate", help="validate an existing pack file")
    p_validate.add_argument("path", type=Path)
    p_validate.add_argument(
        "--profile", choices=[p.value for p in Profile], default=Profile.STRUCTURAL.value
    )

    args = parser.parse_args(argv)
    return {
        "words": cmd_words,
        "prompts": cmd_prompts,
        "pack": cmd_pack,
        "validate": cmd_validate,
    }[args.command](args)


# --- stages -----------------------------------------------------------------


def cmd_words(args) -> int:
    import spacy

    lang = args.language
    nlp = spacy.load(SpacyAnalyzer.MODELS[lang], disable=["ner", "parser"])
    candidates, rejections = build_candidates(lang, nlp=nlp, pool=args.pool, limit=args.limit)

    out = WORK / lang
    out.mkdir(parents=True, exist_ok=True)
    _write_json(out / "candidates.json", [dataclasses.asdict(c) for c in candidates])
    _write_json(out / "rejected.json", [dataclasses.asdict(r) for r in rejections])

    print(f"{len(candidates)} candidates, {len(rejections)} forms rejected -> {out}")
    if len(candidates) < args.limit:
        print(f"warning: wanted {args.limit}; raise --pool", file=sys.stderr)
    return 0


def cmd_prompts(args) -> int:
    lang = args.language
    candidates = _load_candidates(lang)
    prompts_dir = WORK / lang / "prompts"
    prompts_dir.mkdir(parents=True, exist_ok=True)

    for n, start in enumerate(range(0, len(candidates), args.batch), start=1):
        batch = candidates[start : start + args.batch]
        (prompts_dir / f"{n:03d}.md").write_text(
            render_prompt(
                language_name=LANGUAGE_NAMES.get(lang, lang),
                targets=batch,
                vocabulary=candidates,
            ),
            encoding="utf-8",
        )

    print(f"{n} prompts -> {prompts_dir}")
    print(f"Paste each into claude.ai; save each reply as {WORK / lang / 'responses'}/NNN.json")
    return 0


def cmd_pack(args) -> int:
    lang = args.language
    candidates = _load_candidates(lang)
    responses_dir = WORK / lang / "responses"

    generated, errors = [], []
    by_rank = {c.rank: c for c in candidates}
    for path in sorted(responses_dir.glob("*.json")) if responses_dir.is_dir() else []:
        n = int(path.stem)
        expected = {c.rank for c in candidates[(n - 1) * args.batch : n * args.batch]}
        entries, batch_errors = parse_response(path.read_text(encoding="utf-8"), expected)
        generated.extend(entries)
        errors.extend(f"{path.name}: {e}" for e in batch_errors)

    if errors:
        print(f"{len(errors)} response problems -- fix and re-run:", file=sys.stderr)
        for e in errors[:20]:
            print(f"  {e}", file=sys.stderr)
        return 1
    if not generated:
        print(
            f"no responses in {responses_dir}; run `packgen prompts {lang}` first", file=sys.stderr
        )
        return 1

    pack, drops = assemble_pack(
        lang,
        LANGUAGE_NAMES.get(lang, lang),
        candidates,
        generated,
        limit=args.limit,
        created=date.today().isoformat(),
        model="claude.ai (manual)",
    )

    report = validate_pack(pack, analyzer=SpacyAnalyzer(lang), profile=Profile(args.profile))
    _write_json(WORK / lang / "drops.json", drops)

    print(f"{pack['word_count']} words, {len(drops)} candidates dropped")
    print(f"sentence tiers: {report.relaxed_fraction:.0%} RELAXED, rest STRICT")

    if not report.ok:
        _write_retry_prompts(lang, candidates, by_rank, generated, report)
        print(f"{len(report.violations)} violations -- see work/{lang}/retry/", file=sys.stderr)
        for v in report.violations[:20]:
            print(f"  {v}", file=sys.stderr)
        return 1

    PACKS.mkdir(parents=True, exist_ok=True)
    _write_json(PACKS / f"{lang}.pack.json", pack)
    print(f"valid -> {PACKS / f'{lang}.pack.json'}")
    return 0


def cmd_validate(args) -> int:
    pack = json.loads(args.path.read_text(encoding="utf-8"))
    report = validate_pack(
        pack,
        analyzer=SpacyAnalyzer(pack.get("language_code", "")),
        profile=Profile(args.profile),
    )
    for v in report.violations:
        print(v, file=sys.stderr)
    print(
        f"{args.path.name}: {'valid' if report.ok else str(len(report.violations)) + ' violations'}"
    )
    return 0 if report.ok else 1


# --- helpers ----------------------------------------------------------------


def _write_retry_prompts(lang: str, candidates: list[Candidate], by_rank: dict, generated, report):
    """One prompt per failing word, quoting the rule that rejected it."""
    # Pack ranks are re-numbered AND the generator may have corrected the lemma, so
    # map back through the generated entries -- their rank is the candidate rank.
    to_candidate_rank = {(g.lemma, g.pos): g.rank for g in generated}
    rejections: dict[int, str] = {}
    for v in report.violations:
        if not v.entry_id:
            continue  # pack-level rule; no single word to regenerate
        _code, lemma, pos = v.entry_id.split(":")
        rank = to_candidate_rank.get((lemma, pos))
        if rank is not None:
            rejections[rank] = v.message

    retry_dir = WORK / lang / "retry"
    retry_dir.mkdir(parents=True, exist_ok=True)
    for path in retry_dir.glob("*.md"):
        path.unlink()
    for rank, reason in sorted(rejections.items()):
        (retry_dir / f"{rank:04d}.md").write_text(
            render_prompt(
                language_name=LANGUAGE_NAMES.get(lang, lang),
                targets=[by_rank[rank]],
                vocabulary=candidates,
                rejections={rank: reason},
            ),
            encoding="utf-8",
        )


def _load_candidates(lang: str) -> list[Candidate]:
    path = WORK / lang / "candidates.json"
    if not path.is_file():
        sys.exit(f"{path} not found; run `packgen words {lang}` first")
    return [Candidate(**c) for c in json.loads(path.read_text(encoding="utf-8"))]


def _write_json(path: Path, payload) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
