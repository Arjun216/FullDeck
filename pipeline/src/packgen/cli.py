"""packgen CLI.

    packgen words fr        # wordfreq + spaCy   -> work/fr/candidates.json
    packgen prompts fr      # candidates         -> work/fr/prompts/NNN.md
    packgen generate fr     # prompts            -> work/fr/responses/NNN.json
    packgen pack fr         # responses          -> packs/fr.pack.json + validation report
    packgen validate <path> # re-check any pack against the §7 rules

`generate` answers the prompts through the Claude Code CLI (`claude --print`),
which runs on an existing Claude subscription -- there is no API key anywhere in
this repo. Pasting the prompts into claude.ai by hand produces the same files, so
the two are interchangeable.

`pack` is re-runnable: it validates what it built and writes retry prompts for
exactly the words that failed. `generate --retry` answers those, and a retry
answer supersedes the batch answer for its word. The loop converges without
regenerating anything that already passed.
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
from packgen.words import Candidate, build_candidates, suspicious_lemmas

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

    p_generate = sub.add_parser("generate", help="answer the prompts via the Claude Code CLI")
    p_generate.add_argument("language")
    p_generate.add_argument("--model", default="sonnet")
    p_generate.add_argument("--batch", type=int, default=50, help="must match `prompts --batch`")
    p_generate.add_argument("--timeout", type=int, default=900, help="seconds per prompt")
    p_generate.add_argument(
        "--retry", action="store_true", help="answer work/<lang>/retry/*.md instead"
    )

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
        "generate": cmd_generate,
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
    # Clear first: `pack` derives each batch's rank range from --batch, so a stale
    # prompt from a different batch size would silently mis-align the ranks.
    for stale in prompts_dir.glob("*.md"):
        stale.unlink()

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


def cmd_generate(args) -> int:
    """Answer every unanswered prompt by shelling out to the Claude Code CLI.

    `claude --print` runs on your existing Claude subscription -- no API key. It is
    the same mechanism as ~/Projects/resume_pipeline/run.sh.
    """
    lang = args.language
    candidates = _load_candidates(lang)
    source = WORK / lang / ("retry" if args.retry else "prompts")
    # Retries answer in place; batch answers go where the manual paste workflow
    # puts them, so the two are interchangeable.
    destination = source if args.retry else WORK / lang / "responses"
    prompts = sorted(source.glob("*.md"))
    if not prompts:
        print(f"no prompts in {source}", file=sys.stderr)
        return 1

    destination.mkdir(parents=True, exist_ok=True)
    todo = [p for p in prompts if not (destination / f"{p.stem}.json").exists()]
    print(f"{len(todo)} of {len(prompts)} prompts to answer ({args.model})")

    failed = []
    for i, prompt_path in enumerate(todo, start=1):
        n = int(prompt_path.stem)
        out_path = destination / f"{prompt_path.stem}.json"
        expected = (
            {n}
            if args.retry
            else {c.rank for c in candidates[(n - 1) * args.batch : n * args.batch]}
        )
        print(f"  [{i}/{len(todo)}] {prompt_path.name} ... ", end="", flush=True)

        try:
            reply = _run_claude(prompt_path.read_text(encoding="utf-8"), args.model, args.timeout)
        except Exception as exc:  # noqa: BLE001 -- surface any CLI failure, keep going
            print(f"FAILED ({exc})")
            failed.append(prompt_path.name)
            continue

        # Only a reply that parses is kept, so re-running retries exactly the bad ones.
        entries, problems = parse_response(reply, expected)
        if problems:
            out_path.with_suffix(".json.bad").write_text(reply, encoding="utf-8")
            print(f"UNUSABLE ({problems[0]})")
            failed.append(prompt_path.name)
            continue

        out_path.write_text(reply, encoding="utf-8")
        print(f"ok ({len(entries)} words)")

    if failed:
        print(f"\n{len(failed)} unanswered: {', '.join(failed)}", file=sys.stderr)
        print("re-run this command to retry only those", file=sys.stderr)
        return 1
    return 0


def _run_claude(prompt: str, model: str, timeout: int) -> str:
    import subprocess

    result = subprocess.run(
        ["claude", "--print", "--model", model, prompt],
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError((result.stderr or result.stdout).strip()[:200] or "claude failed")
    return result.stdout


def cmd_pack(args) -> int:
    lang = args.language
    candidates = _load_candidates(lang)
    responses_dir = WORK / lang / "responses"

    by_rank = {c.rank: c for c in candidates}
    generated, errors = _ingest(candidates, args.batch, responses_dir, WORK / lang / "retry")

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

    suspects = suspicious_lemmas(pack)
    if suspects:
        _write_json(WORK / lang / "suspect-lemmas.json", suspects)
        print(
            f"{len(suspects)} lemmas the corpus has never seen -> work/{lang}/suspect-lemmas.json"
        )

    if not report.ok:
        if _write_retry_prompts(lang, candidates, by_rank, generated, report):
            print(f"{len(report.violations)} violations -- see work/{lang}/retry/", file=sys.stderr)
        else:
            print(
                f"{len(report.violations)} violations that regenerating will not fix. "
                f"Edit work/{lang}/responses/ by hand, or drop these words.",
                file=sys.stderr,
            )
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


def _ingest(candidates: list[Candidate], batch: int, responses_dir: Path, retry_dir: Path):
    """Batch replies, then per-word retries layered on top (a retry wins by rank)."""
    generated: list = []
    errors: list[str] = []

    def read(path: Path, expected: set[int]) -> None:
        entries, problems = parse_response(path.read_text(encoding="utf-8"), expected)
        generated.extend(entries)
        errors.extend(f"{path.name}: {e}" for e in problems)

    if responses_dir.is_dir():
        for path in sorted(responses_dir.glob("*.json")):
            n = int(path.stem)
            read(path, {c.rank for c in candidates[(n - 1) * batch : n * batch]})

    # Retry files are named for the single candidate rank they regenerate.
    if retry_dir.is_dir():
        for path in sorted(retry_dir.glob("*.json")):
            read(path, {int(path.stem)})

    # Last write wins, so a retry supersedes the batch answer for that rank.
    deduped = {g.rank: g for g in generated}
    return list(deduped.values()), errors


def _write_retry_prompts(
    lang: str, candidates: list[Candidate], by_rank: dict, generated, report
) -> bool:
    """One prompt per failing word, quoting the rule that rejected it.

    Returns False when there is nothing worth re-asking: every failing word was
    already regenerated once and still fails, or the failures are pack-level and
    belong to no single word. No prompts are left behind in that case, so
    `generate --retry` finds nothing, exits non-zero, and the loop stops instead
    of spinning.

    "Already regenerated" means an answer is on disk for that rank -- running
    `pack` twice with no regeneration in between is not a stuck loop.
    """
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
    previous = {int(path.stem) for path in retry_dir.glob("*.md")}
    answered = {int(path.stem) for path in retry_dir.glob("*.json")}
    for path in retry_dir.glob("*.md"):
        path.unlink()
    if not rejections or (rejections.keys() == previous and rejections.keys() <= answered):
        return False

    for rank, reason in sorted(rejections.items()):
        # A rank that still violates has a wrong answer on file. Clear it, or
        # `generate --retry` would skip the word as already answered.
        for stale in retry_dir.glob(f"{rank:04d}.json*"):
            stale.unlink()
        (retry_dir / f"{rank:04d}.md").write_text(
            render_prompt(
                language_name=LANGUAGE_NAMES.get(lang, lang),
                targets=[by_rank[rank]],
                vocabulary=candidates,
                rejections={rank: reason},
            ),
            encoding="utf-8",
        )
    return True


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
