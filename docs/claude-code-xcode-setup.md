# Claude Code + Xcode: setup and workflow for this project

**Date:** 2026-07-06 · **For:** a developer new to Xcode, already fluent with Claude Code and the terminal.

## The short version

Use **Claude Code in the terminal as the primary driver** for all 14 phases, with **Xcode open alongside** for the simulator, SwiftUI previews, and debugging. Since Xcode 26.3 (Feb 2026), Xcode also embeds the **Claude Agent SDK natively** — the same engine as Claude Code, inside the IDE — which you can sign into with your existing Claude account and use for in-editor work once the Swift phases start. You don't have to pick one; they share your account and coexist fine.

Why terminal-first for this project specifically:

- The plan is more than Swift: docs phases, a Python pipeline (Phase 6), git workflows, CI (Phase 4). Terminal Claude Code covers all of it in one session with one `CLAUDE.md` context; Xcode's agent only sees the Xcode project.
- Your prompt library is designed as paste-one-phase-per-session — that maps naturally onto terminal sessions in the project root.
- Claude Code can build, test, and drive the simulator itself from the CLI (commands below), so "runs in Xcode" is never a blocker.

Use Xcode's built-in Claude agent when it genuinely shines: iterating on a SwiftUI view while watching the live preview, and fixing compiler errors in place.

## One-time setup

1. **Update Xcode to 26.3 or later** (App Store → Updates). The agentic Claude integration landed in 26.3; earlier 26.x only had chat-style assistance.
2. **Install command-line tools** so Claude Code can build without the IDE:
   ```sh
   xcode-select --install        # no-op if already present
   sudo xcodebuild -license accept
   ```
3. **Optional but recommended — `xcbeautify`:** raw `xcodebuild` output is thousands of lines; this makes it readable for both you and Claude:
   ```sh
   brew install xcbeautify
   ```
4. **Sign into Claude inside Xcode** (Settings → Intelligence → add Claude account) if you want the in-IDE agent. Uses your existing subscription.
5. **First simulator run:** open the project in Xcode once, pick an iPhone simulator in the toolbar, press ⌘R. Do this manually the first time so you've seen the loop; after that Claude can drive it.

## How the day-to-day loop works

- Run `claude` in `~/Projects/Language_App`. Claude edits files on disk; Xcode picks up changes automatically — no import/export step.
- Claude verifies its own work from the CLI. You mostly press ⌘R in Xcode when you want to *see* the app.
- **You stay the human in the loop at phase boundaries**, exactly as the prompt library prescribes: read the output, run it, commit it, next session.

### Commands Claude Code uses (these go in CLAUDE.md at Phase 4)

```sh
# Pure-Swift packages (domain engine, data layer) — fast, no simulator:
swift test --package-path Packages/Domain

# Full app build:
xcodebuild -scheme <AppName> -destination 'platform=iOS Simulator,name=iPhone 17' build | xcbeautify

# Full test suite (unit + UI):
xcodebuild -scheme <AppName> -destination 'platform=iOS Simulator,name=iPhone 17' test | xcbeautify

# Simulator control:
xcrun simctl list devices                      # what's available
xcrun simctl boot 'iPhone 17'                  # start one
xcrun simctl io booted screenshot shot.png     # screenshot for Claude to inspect
```

When Phase 4 creates `CLAUDE.md`'s final version, add a **"Build & test commands"** section containing the exact working versions of these — every future session then knows how to verify without rediscovering flags.

## Project structure that keeps AI tooling painless

The classic failure mode of AI agents + Xcode is the `.pbxproj` project file: an opaque format where a bad merge or edit corrupts the whole project. Two modern choices eliminate the problem, and both align with the Phase 2 architecture:

1. **Xcode 16+ synchronized folder groups** (the default for new projects): the project mirrors the file system, so files Claude creates on disk appear in Xcode automatically. No project-file editing, ever.
2. **Local Swift packages for the inner layers.** Make `Domain` and `Data` local Swift Package Manager packages (each with its own `Package.swift` and test target), with the Xcode app target as a thin SwiftUI shell that depends on them. `Package.swift` is plain, reviewable Swift — the file system *is* the project. Bonus: `swift test` runs the domain tests in seconds with no simulator, which is exactly the fast TDD loop Phase 5 needs.

Instruct Claude in Phase 4 to scaffold this way. If a file ever does need manual registration in Xcode, do it by hand in Xcode rather than letting any tool edit `.pbxproj` — community consensus is unanimous on this.

## Optional power-up: XcodeBuildMCP

[XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP) is the de-facto MCP server for iOS work: it gives Claude Code structured tools to build, run on a simulator, read runtime logs, and take screenshots — instead of shelling out to `xcodebuild` and parsing text. Add it with:

```sh
claude mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest
```

Skip it for now; plain `xcodebuild` + `xcbeautify` works out of the box. Add it around Phase 8–9 if you find Claude fumbling simulator interaction or log reading. (Xcode 26.3 also exposes its own capabilities over MCP, so tooling here is still evolving — re-check what's current when you get there.)

## Division of labor cheat sheet

| Task | Tool |
|---|---|
| Running a phase prompt, multi-file work, docs, Python pipeline, git, CI | Claude Code (terminal) |
| Seeing/using the app, simulator, debugging with breakpoints | Xcode (you, ⌘R) |
| Tweaking a SwiftUI view against the live preview; fixing a compiler error in place | Xcode's built-in Claude agent |
| Building/testing/screenshotting without opening Xcode | Claude Code via `xcodebuild` / `simctl` |

## How to "vibe code" this: skills and prompts, phase by phase

"Vibe coding" here doesn't mean dropping the discipline in `docs/build-plan.md` — it means you don't have to hand-hold the process. This session's harness has a rule (`using-superpowers`) that forces Claude to check for a matching skill before every response. You don't invoke skills yourself; you just paste the phase prompt and talk normally, and the right skill fires on its own. What you actually need to know is *which skill you should expect to see*, so you can tell when something's off.

### The loop, once per phase

1. Open a session in the project root (a fresh one is fine — `CLAUDE.md` loads automatically).
2. **Paste that phase's prompt from `docs/build-plan.md` verbatim.** That file already *is* the plan; don't wrap it in extra framing.
3. Skills fire automatically as the work proceeds (table below).
4. Before the phase is called "done": a **self-review pass** (CLAUDE.md requires this after every phase) — ask for `/code-review` and, since this project runs Ponytail in full mode, a `/ponytail-review` pass too. Different targets: code-review hunts bugs, ponytail-review hunts over-engineering.
5. **Actually see it work.** Use `/run` (or ask Claude to launch the simulator) before accepting a UI-facing phase — passing tests are not the same as a working screen.
6. Commit. One phase = one (or a few) conventional commits, per CLAUDE.md.

### Which skill should show up when

| Phase(s) | What's happening | Skill that should fire |
|---|---|---|
| 1–3 (docs only) | requirements, architecture, schema | Nothing extra — these were already brainstormed; it's straight writing. If a real ambiguity surfaces, `brainstorming` re-opens for just that question. |
| 4, 6, 7, 9, 10 | turning a written phase-prompt spec into working code | `writing-plans` first (breaks the prompt into concrete steps), then plain execution |
| 5, and the test parts of 6/7/8 | scheduler, pipeline, persistence, ViewModels | `test-driven-development` — CLAUDE.md already mandates tests-before-code; this is what enforces it |
| 11 (StoreKit) | money-handling code | `writing-plans`, then treat `/security-review` as non-optional before you trust it |
| 12 (Hindi) | proving the "no code change" claim | `systematic-debugging` if the abstraction leaks somewhere |
| 13–14 | QA, release | `verification-before-completion` — this is the whole point of these phases: evidence before "it's ready" |
| any phase, any time | a red test, a crash, "why doesn't this work" | `systematic-debugging` — before any fix is proposed, not after |

Ponytail (full) runs underneath all of this the whole time — it's what keeps Claude from adding config knobs, abstractions, or speculative flexibility you didn't ask for. If a phase's output looks suspiciously minimal, that's it working, not it skipping steps; the `ponytail:` comments mark anything it deliberately simplified. Run `/ponytail-debt` anytime to see the running list of what got deferred.

### Best prompts

- **The phase prompt, unmodified.** That's the entire design of `docs/build-plan.md` — it's already been through brainstorming once. Adding your own preamble usually just dilutes it.
- **Plain English for anything the plan doesn't cover** — "explain what an ease factor is before we go further," "I don't like these completion-screen options, give me different ones." One sentence is enough; Claude pulls in whichever skill fits (usually `brainstorming` again for a design change).
- **Two phrases worth knowing:**
  - *"self-review this phase"* — triggers the CLAUDE.md-mandated tech-debt callout explicitly, if it didn't already happen.
  - *"what did ponytail defer"* — surfaces every `ponytail:` shortcut left in the code so far (via `ponytail-debt`), so shortcuts don't quietly rot into permanent gaps.

## Sources

- [Apple: Xcode 26.3 unlocks the power of agentic coding](https://www.apple.com/newsroom/2026/02/xcode-26-point-3-unlocks-the-power-of-agentic-coding/)
- [Anthropic: Apple's Xcode now supports the Claude Agent SDK](https://www.anthropic.com/news/apple-xcode-claude-agent-sdk)
- [Anthropic: Claude is now generally available in Xcode](https://www.anthropic.com/news/claude-in-xcode)
- [Claude Code × Xcode — practical setup guide (Claude Lab)](https://claudelab.net/en/articles/claude-code/claude-code-xcode-ios-development-guide)
- [XcodeBuildMCP setup gist](https://gist.github.com/joelklabo/6df9fa603bec3478dec7efc17ea44596)
