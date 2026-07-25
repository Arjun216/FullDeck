# ADR-002 — UI architecture pattern

**Status:** Accepted (2026-07-07) · **Deciders:** dev + Claude · **Phase:** 2

## Context

SwiftUI app, iOS 17+, solo developer new to Swift. `CLAUDE.md` requires thin views with logic
in testable ViewModels that depend on injected protocols. We need a pattern that keeps the
study/session logic unit-testable without a simulator, with minimal ceremony.

## Options considered

| Option | Fit |
|--------|-----|
| **MVVM + `@Observable`** | 2026 production default for indie apps; Apple engineers describe SwiftUI's default flow as "effectively MVVM." `@Observable` gives precise, performant view invalidation. |
| **Vanilla "MV" (`@State` only)** | Fine for trivial views; pushes session/scheduler logic into view bodies, which hurts testability. |
| **TCA (The Composable Architecture)** | Powerful for deterministic state machines, but a heavy third-party dependency and learning curve unjustified here. |
| **VIPER / MVVM-C with a Coordinator layer** | Extra rigidity/navigation indirection for large teams; our navigation is trivial. |

## Decision

**MVVM with `@Observable` ViewModels.**

- Views are thin and declarative; they read state from a `@MainActor @Observable` ViewModel.
- ViewModels own state + async work and depend **only on Domain ports** (`PackStore`, `ReviewStore`, `EntitlementStore`, `SpeechService`) and Domain services (`Scheduler`, `SessionBuilder`), injected via `init` (see architecture §3). No singletons.
- **No Coordinator layer and no DI framework.** Navigation is trivial (language selection → study/progress → completion); plain SwiftUI navigation suffices. Adding a Coordinator/router now would be speculative structure (ponytail).
- Trivial views with no async/logic may skip the ViewModel and use `@State` directly.

## Consequences

- **+** ViewModels are unit-testable with in-memory fakes — no real persistence or TTS (Phase 8).
- **+** Minimal ceremony; aligned with Apple's current guidance; leans on `@Observable` for reactive plumbing.
- **−** Requires ongoing discipline that views stay thin (enforced in review, and by ViewModels holding the logic).
- **Reversibility:** if navigation later grows complex, introducing coordinators is additive and localized.

## References
- [SwiftUI architecture 2026: MVVM + @Observable — Forasoft](https://www.forasoft.com/blog/article/advanced-ios-app-architecture-explained-on-mvvm-977)
- [MVVM vs TCA in SwiftUI — Medium](https://medium.com/@chathurikabandara0701/tca-vs-mvvm-in-swiftui-which-architecture-should-you-choose-f4cd21315329)
