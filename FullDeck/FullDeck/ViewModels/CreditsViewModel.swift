import Domain
import Foundation
import Observation

/// One credit line: a source, its licence, and every bundled language that uses
/// it. Grouped rather than per-pack, so two wordfreq packs do not render the
/// same three lines twice.
struct Credit: Equatable, Identifiable {
    let sourceName: String
    let license: String
    let attribution: String
    let languages: [String]

    var id: String { "\(sourceName)|\(license)|\(attribution)" }
}

/// FR-16, the app half. The pack-metadata half has been enforced by
/// `PackValidator` since Phase 6, which is exactly what made this half easy to
/// miss for four phases (N-4).
///
/// Reads each pack's own `PackSource` rather than a hardcoded string, so
/// ADR-004 survives: a third pack from a different source shows up here with no
/// app code touched. wordfreq's data is CC-BY-SA 4.0, and this screen is the
/// licence condition, not a nicety.
@MainActor
@Observable
final class CreditsViewModel {
    enum State: Equatable {
        case loading
        case ready([Credit])
        case failed(String)
    }

    private(set) var state: State = .loading

    private let packStore: PackStore

    init(packStore: PackStore) {
        self.packStore = packStore
    }

    func load() async {
        state = .loading
        do {
            let descriptors = try await packStore.availablePacks()
            var loaded: [(name: String, source: PackSource)] = []
            for descriptor in descriptors {
                let pack = try await packStore.loadPack(descriptor.languageCode)
                loaded.append((pack.languageName, pack.source))
            }
            state = .ready(Self.grouped(loaded))
        } catch let error as PackLoadError {
            state = .failed(error.userMessage)
        } catch {
            state = .failed(String(localized: "Couldn't load the credits."))
        }
    }

    /// Groups by the whole source triple, preserving first-appearance order so
    /// the list is stable rather than dictionary-ordered.
    static func grouped(_ packs: [(name: String, source: PackSource)]) -> [Credit] {
        var order: [String] = []
        var byKey: [String: Credit] = [:]
        for pack in packs {
            let key = "\(pack.source.name)|\(pack.source.license)|\(pack.source.attribution)"
            if let existing = byKey[key] {
                byKey[key] = Credit(
                    sourceName: existing.sourceName, license: existing.license,
                    attribution: existing.attribution,
                    languages: existing.languages + [pack.name])
            } else {
                order.append(key)
                byKey[key] = Credit(
                    sourceName: pack.source.name, license: pack.source.license,
                    attribution: pack.source.attribution, languages: [pack.name])
            }
        }
        return order.compactMap { byKey[$0] }
    }
}
