# ADR-003 — Testing frameworks

**Status:** Accepted (2026-07-07) · **Deciders:** dev + Claude · **Phase:** 2

## Context

The build is test-first for domain logic (Phase 5), with tested ViewModels (Phase 8),
integration tests (Phase 9), and UI + optional snapshot tests (Phase 13). `CLAUDE.md` forbids
deprecated/soon-deprecated APIs, so the choice must reflect current (2026) best practice — not
a default assumption.

## Options considered

| Option | Fit |
|--------|-----|
| **Swift Testing** | 2026 default for new unit/integration tests: `@Test` + `#expect`/`#require`, parallel by default, `Sendable`/Swift-6-friendly, no class inheritance. |
| **XCTest** | The legacy framework; still required for UI tests (XCUITest) and performance metrics (XCTMetric). Coexists in the same target. |
| **XCUITest** | Apple's first-party UI-automation framework (built on XCTest); accessibility-driven, auto-waiting, out-of-process. No first-party successor. |
| **swift-snapshot-testing (Point-Free)** | The maintained de-facto snapshot library; image + text/JSON/recursive-description strategies. |
| **Quick/Nimble** | Third-party BDD unit frameworks — unnecessary given Swift Testing. |

## Decision

- **Unit + integration tests → Swift Testing.** All Domain, Data, and ViewModel tests. Runs the Domain/Data package tests fast via `swift test` (no simulator).
- **UI tests → XCUITest.** For the Phase 13 critical-flow tests (complete a session, reach completion, unlock a language). Swift Testing has no UI-automation; XCUITest is the correct first-party tool and stays.
- **Snapshot tests → `swift-snapshot-testing` *if adopted in Phase 13*.** Named now so the choice is settled, but **not added as a dependency until Phase 13** actually needs it (YAGNI).
- Swift Testing and XCTest coexist in one test target; keep XCTest only where required (XCUITest subclasses, XCTMetric).

## Consequences

- **+** Modern, concise, parallel unit tests; the fast TDD loop Phase 5 needs works out of the box.
- **+** No third-party test dependency in the core build; snapshot lib added only if/when used.
- **−** Two frameworks in play (Swift Testing for unit, XCUITest for UI) — normal in 2026, but two idioms to know.
- **−** `swift-snapshot-testing` (when added) is a third-party dependency and its reference images need maintenance across OS/render changes — a Phase 13 decision, revisit maintenance status then.

## References
- [Swift Testing vs XCTest in 2026 — CodeAnatomy](https://www.codeanatomybyaher.com/articles/swift-unit-testing-xctest-swift-testing-compared)
- [XCUITest iOS UI Testing (2026) — QASkills](https://qaskills.sh/blog/xcuitest-ios-ui-testing-tutorial-2026)
- [swift-snapshot-testing — Point-Free (GitHub)](https://github.com/pointfreeco/swift-snapshot-testing)
