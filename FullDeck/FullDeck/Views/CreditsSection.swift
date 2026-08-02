import SwiftUI

/// Maps a licence string to its canonical text, when we recognise it.
///
/// `PackSource` carries no URL, so a link needs a literal — the one place this
/// feature could break ADR-004's "add a pack, not app code" rule. An
/// unrecognised licence degrades to text only rather than to a wrong link.
/// Text attribution alone satisfies CC-BY-SA; the URI is its "where reasonably
/// practicable" clause.
enum LicenseLink {
    static func url(for license: String) -> URL? {
        switch license {
        case "CC-BY-SA 4.0": URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")
        default: nil
        }
    }
}

/// FR-16. A section rather than a pushed screen: two packs at three lines each
/// fits, and burying a licence obligation one level deeper serves nobody.
struct CreditsSection: View {
    let viewModel: CreditsViewModel

    var body: some View {
        Section("Credits") {
            switch viewModel.state {
            case .loading:
                ProgressView()
            case .ready(let credits):
                ForEach(credits) { credit in
                    creditRow(credit)
                }
            case .failed(let message):
                Text(message)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .listRowBackground(Color.appBackground)
    }

    private func creditRow(_ credit: Credit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(credit.languages.joined(separator: ", "))
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            // The attribution string verbatim, with nothing added. It already
            // names the source and the licence, and it is the text the licence
            // requires — wrapping it in a sentence of ours produced "CC-BY-SA
            // 4.0.." on screen and said "wordfreq" twice.
            Text(credit.attribution)
                .foregroundStyle(Color.textPrimary)
            if let url = LicenseLink.url(for: credit.license) {
                Link(credit.license, destination: url)
            } else {
                Text(credit.license)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        // One row per credit to VoiceOver, rather than three unrelated
        // fragments the learner has to stitch together.
        .accessibilityElement(children: .combine)
    }
}
