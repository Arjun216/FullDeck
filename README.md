# Full Deck

A SwiftUI iOS app that teaches the ~1000 highest-frequency words in a language
using spaced repetition — and nothing else. First language (French) is free;
each additional language is a one-time $0.99 unlock. No ads, no subscriptions,
no gamification, and a deliberate ending when all 1000 words are learned.

> **Status:** in active development. Currently Phase 4 (scaffolding) of a
> 14-phase build — see [`docs/build-plan.md`](docs/build-plan.md).

## Architecture

Three layers, dependencies pointing **inward only** (full detail in
[`docs/architecture.md`](docs/architecture.md)):

```
Presentation (SwiftUI views + @Observable ViewModels)   ← App target
        │  depends on
        ▼
      Domain (pure Swift: scheduler, models, ports)      ← Packages/Domain
        ▲  implemented by
        │
       Data (JSON packs + SwiftData review state)        ← Packages/Data
```

- **Domain** is pure Swift with zero framework dependencies, so it's unit-tested
  in isolation (no simulator). The spaced-repetition engine lives here.
- **Data** implements Domain's ports (protocols) with concrete storage.
- The **App** target is a thin shell that wires everything at a composition root.
- Package boundaries enforce the dependency rules *at compile time* — Domain
  physically cannot import persistence or UI.

## Repository layout

```
Packages/Domain/     Pure-Swift domain package (SPM)
Packages/Data/       Persistence package (SPM), depends on Domain
FullDeck/            The iOS app target (thin SwiftUI shell)   [added in the Xcode step]
docs/                Requirements, architecture, ADRs, the pack schema
fixtures/            Valid + invalid language-pack fixtures for validator tests
schema/              JSON Schema for language packs
scripts/             CI gate scripts (coverage, determinism, traceability)
.github/workflows/   CI
```

## Build & test locally

Requires Xcode 26+ (Swift 6). The domain/data packages need no simulator:

```sh
# Fast package tests (seconds, no simulator):
swift test --package-path Packages/Domain
swift test --package-path Packages/Data

# Coverage gates (Domain >= 90%, Data >= 80%):
swift test --package-path Packages/Domain --enable-code-coverage
scripts/coverage-gate.sh Packages/Domain 90 DomainPackageTests

# The full app (needs the FullDeck Xcode project + a booted simulator).
# Use any iPhone simulator your Xcode has installed:
xcodebuild test -project FullDeck/FullDeck.xcodeproj -scheme FullDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' | xcbeautify
```

## Lint & format

```sh
swiftlint lint --strict                          # brew install swiftlint
swift format lint --strict --recursive Packages  # Apple's formatter, bundled with the toolchain
swift format --in-place --recursive Packages     # auto-fix
```

## License & attribution

Word-frequency data is derived from the [`wordfreq`](https://github.com/rspeer/wordfreq)
package (CC-BY-SA 4.0); attribution is carried in each language pack's metadata
and shown in the app's credits. See [`docs/language-pack-schema.md`](docs/language-pack-schema.md).
