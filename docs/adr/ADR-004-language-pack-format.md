# ADR-004 — Language-pack format, bundling & discovery

**Status:** Accepted (2026-07-07) · **Deciders:** dev + Claude · **Phase:** 2

## Context

The central architectural claim (`CLAUDE.md`, proven in Phase 12) is that **adding a language
must be a content task, not an engineering task**. That requires a stable, versioned,
machine-validated pack format the app discovers generically — no per-language code. The Phase 6
Python pipeline emits packs; Phase 3 defines their formal schema and validation rules. This ADR
fixes the *format, bundling, discovery, update, and versioning* so Phase 3 can specify the field
schema against a known container.

## Options considered

| Option | Fit |
|--------|-----|
| **Versioned JSON (`Codable`)** | Human-reviewable, diffable, directly emitted+validated by the Python pipeline, matches a JSON Schema (Phase 3), trivial to load. |
| **plist** | Apple-native but clumsier to author/validate than JSON; weaker tooling. |
| **SQLite/SwiftData per pack** | Overkill for read-only static content; opaque to review/diff; heavier to produce from Python. |
| **Packs embedded in Swift code** | Directly violates "add a language = add data, not code." |

## Decision

- **Format:** one **JSON file per language**, conforming to the Phase 3 JSON Schema, carrying pack-level metadata — language code, display name, `schema_version`, word count, and the source/attribution + license note (**wordfreq CC-BY-SA 4.0**, spec D2). Loaded via `Codable` behind `PackStore`.
- **Bundling:** packs ship as **resources** in the app bundle (an SPM resource bundle / `Packs/` group). v1 is offline-first with no backend, so packs travel with the app.
- **Discovery:** a bundled **`manifest.json`** lists available packs (language code, display name, filename, `unlockedByDefault`). `PackStore.availablePacks()` reads it so language selection (FR-1) is fully data-driven — dropping in a new pack + manifest entry makes it appear, no code change.
- **Update:** packs update by **shipping a new app version** (no over-the-air pack delivery in v1). Accepted under the no-backend scope.
- **Versioning:** each pack declares `schema_version`. The loader checks compatibility and returns a **typed error** on an unknown/newer version rather than silently misreading (NFR-10). The exact forward/back-compat policy is specified in Phase 3.

## Consequences

- **+** Adding a language = drop in a validated JSON pack + a manifest line. No app-code change — the Phase 12 goal is structurally supported.
- **+** Packs are plain data the pipeline validates against the same schema the app reads; human-reviewable before shipping.
- **−** No OTA pack fixes in v1: a content correction needs an app update. Accepted (offline-first, no server).
- **−** JSON is parsed at load; fine at ~1000 entries. If load ever became a bottleneck, pre-indexing or an on-first-launch import into SwiftData is a future option (YAGNI now).

## References
- [SwiftData Tutorial (bundled data patterns) — Bugfender](https://bugfender.com/blog/swift-data/)
