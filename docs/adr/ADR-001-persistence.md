# ADR-001 — Persistence

**Status:** Accepted (2026-07-07) · **Deciders:** dev + Claude · **Phase:** 2

## Context

Two kinds of data with different shapes:

1. **Language packs** — read-only, bundled in the app, ~1000 word entries + one sentence each + metadata per language. Defined as JSON by the Phase 3 schema and emitted by the Phase 6 Python pipeline.
2. **Review state + settings** — mutable, per-user: ease factor, interval, next-review date, learned status per word; plus the daily new-word cap and reminder settings.

Constraints: offline-first, local-only, single-user, no sync, small data (a few thousand tiny rows total), solo-maintained, iOS 17.0+ (NFR-9). Must never crash on bad/missing data (NFR-10) and never lose a graded result (NFR-11). Both kinds are accessed only through repository ports (`PackStore`, `ReviewStore`), so the concrete store is swappable.

## Options considered

| Option | Fit |
|--------|-----|
| **Core Data** | Mature but superseded by SwiftData for new apps; `.xcdatamodeld` + `NSManagedObject` boilerplate is heavy for a learner. |
| **SwiftData** | Apple's native iOS 17+ store and the 2026 default for new apps; `@Model` macro, transactional, migration tooling, zero third-party deps, SwiftUI-integrated. |
| **SQLite via GRDB** | Excellent, fast, SQL-explicit (familiar to a Python dev), robust migrations — but a third-party dependency we don't need at this data size. |
| **JSON + Codable** | Zero frameworks, trivial for read-only packs; sufficient for the tiny mutable store with atomic writes, but no transactions/migrations and less to learn. |

## Decision

**Split by data kind:**

- **Read-only language packs → JSON + `Codable`.** They are already JSON (Phase 3 schema); static bundled content does not belong in a database. Loaded via `PackStore` (ADR-004).
- **Mutable review state + settings → SwiftData.** Native to our iOS 17 floor, transactional (durability for NFR-11), migration tooling for schema evolution, zero third-party dependencies, and the 2026-recommended default. It also directly serves the learning goal (D1). Exposed via `ReviewStore`.

**Discipline that keeps the Domain pure:** SwiftData `@Model` classes live only in the Data layer. The `ReviewStore` adapter maps them to/from `Sendable` pure-Swift domain value types; `@Model` types never cross the port. SwiftData's non-`Sendable` `ModelContext` is isolated inside the adapter (a `ModelActor` or dedicated context) — see architecture §4.

## Consequences

- **+** No third-party dependencies; modern, Apple-aligned, teachable; transactional writes; free migration tooling; fast package tests via an in-memory `ModelConfiguration`.
- **+** Read-only packs stay diffable, human-reviewable JSON the pipeline validates directly.
- **−** Couples the Data layer to iOS 17+ (already our minimum, so no real cost).
- **−** SwiftData's `ModelContext` is not `Sendable`; the Data layer must isolate it and hand out value types (handled in Phase 7).
- **−** We own the review-state migration policy as its schema evolves; SwiftData tooling assists, and additive `Codable`-style changes are low-risk.
- **+** **Stats/trend support:** the review-state model carries milestone dates (`firstReviewedDate`, `learnedDate`) so the learning-progress trend (FR-17), status buckets, and hardest-words ranking (FR-18) are reconstructable from current state — no review-event log. Assumes "learned" is a monotonic milestone (Phase 9); an append-only event log is the documented upgrade path *only if* activity/accuracy trends are ever wanted (out of scope v1).
- **Reversibility:** everything is behind `ReviewStore`/`PackStore`; if SwiftData disappoints, swapping to GRDB or a JSON store is contained to the Data layer.

## References
- [SwiftData vs Core Data 2026 — Medium](https://medium.com/@bhumibhuva18/swiftdata-is-here-but-should-you-actually-ditch-core-data-49a3c8665e13)
- [Swift 6 iOS Development 2026 — SoftAims](https://softaims.com/blog/swift-ios-development-guide-2026)
