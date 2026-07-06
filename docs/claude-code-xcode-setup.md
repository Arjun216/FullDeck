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

## Sources

- [Apple: Xcode 26.3 unlocks the power of agentic coding](https://www.apple.com/newsroom/2026/02/xcode-26-point-3-unlocks-the-power-of-agentic-coding/)
- [Anthropic: Apple's Xcode now supports the Claude Agent SDK](https://www.anthropic.com/news/apple-xcode-claude-agent-sdk)
- [Anthropic: Claude is now generally available in Xcode](https://www.anthropic.com/news/claude-in-xcode)
- [Claude Code × Xcode — practical setup guide (Claude Lab)](https://claudelab.net/en/articles/claude-code/claude-code-xcode-ios-development-guide)
- [XcodeBuildMCP setup gist](https://gist.github.com/joelklabo/6df9fa603bec3478dec7efc17ea44596)
