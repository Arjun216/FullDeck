import Charts
import Domain
import SwiftUI

/// Words learned out of the total (FR-10), the outcome trend (FR-17), and the
/// hardest words (FR-18). Outcome-only: §4 rules out time-spent, review counts
/// and streak chains, and none of them appears here.
struct LearningProgressView: View {
    let viewModel: ProgressViewModel

    // Dynamic Type: 64pt at the default text size, scaling on the .largeTitle
    // curve — a bare .system(size:) would ignore the user's setting entirely.
    @ScaledMetric(relativeTo: .largeTitle) private var countSize: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 180

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity)
                .background(Color.appBackground)
                .navigationTitle("Progress")
                .task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .ready(let snapshot):
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    hero(snapshot)
                    // Two days, not one. A `LineMark` needs two x values to draw
                    // a segment, so a learner's first session rendered axis
                    // labels around an empty plot — found by looking at it, not
                    // by a test. One point is not a trend anyway: "you started
                    // today" is what the count above already says.
                    if snapshot.trend.count >= 2 {
                        trend(snapshot.trend)
                    }
                    hardest(snapshot.hardest)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .failed(let message):
            ErrorStateView(message: message)
        }
    }

    private func hero(_ snapshot: ProgressViewModel.Snapshot) -> some View {
        VStack(spacing: Spacing.sm) {
            Text("\(snapshot.learned)")
                .font(.system(size: countSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
            Text("of \(snapshot.total) words learned")
                .font(.title3)
                .foregroundStyle(Color.textSecondary)
            if viewModel.state.isComplete {
                Text("Every word. That's the whole deck.")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.learned) of \(snapshot.total) words learned")
    }

    private func trend(_ series: [TrendPoint]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("Over time")
            Chart {
                ForEach(series, id: \.day) { point in
                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("Words", point.started),
                        series: .value("Series", "started")
                    )
                    .foregroundStyle(Color.textSecondary)
                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("Words", point.learned),
                        series: .value("Series", "learned")
                    )
                    .foregroundStyle(Color.accentFill)
                }
            }
            // Axis labels are *text*, so they need 4.5:1, and SwiftUI's default
            // axis grey does not clear it on this background — the same defect
            // C-6 caught on the Settings section headers, one screen over.
            // `.font(.caption)`, not the Charts default: the default is a fixed
            // size that ignores Dynamic Type, which the audit reports as
            // "Potentially inaccessible text" once the chart is actually on
            // screen. A text style scales with the user's setting.
            .chartXAxis {
                AxisMarks {
                    AxisValueLabel().font(.caption).foregroundStyle(Color.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks {
                    AxisValueLabel().font(.caption).foregroundStyle(Color.textSecondary)
                }
            }
            .frame(height: chartHeight)
            legend
        }
        // One label for the whole section, not hundreds of marks and not a
        // separate node per legend swatch. VoiceOver reading a per-day series
        // individually is worse than silence; a caption-height legend of its own
        // is smaller than the audit's minimum hit area; and these numbers are
        // FR-17's own acceptance sentence.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Over time. Two lines: words started, and words learned. "
                + "\(series.learnedInLast(7)) words learned in the last 7 days, "
                + "\(series.learnedInLast(30)) in the last 30")
    }

    /// Written by hand rather than left to `chartLegend`: two lines told apart
    /// by colour alone fail WCAG 1.4.1, and Charts' own legend draws its labels
    /// in a system grey that the audit reported as "Contrast nearly passed" on
    /// this background — with no API to restyle it.
    ///
    /// Carries no accessibility modifiers of its own: it is folded into the
    /// section's single element above, because `accessibilityHidden` leaves text
    /// the accessibility API cannot see and a standalone element is smaller than
    /// the minimum hit area — both of which the audit reports.
    private var legend: some View {
        HStack(spacing: Spacing.md) {
            legendKey("Started", color: .textSecondary)
            legendKey("Learned", color: .accentFill)
        }
        .font(.caption)
    }

    private func legendKey(_ label: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            Capsule().fill(color).frame(width: 16, height: 3)
            Text(label).foregroundStyle(Color.textSecondary)
        }
    }

    private func hardest(_ words: [WordEntry]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("Hardest words")
            if words.isEmpty {
                // True, useful, and not a scolding.
                Text("Nothing has tripped you up yet.")
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(words, id: \.id) { word in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(word.display)
                            .foregroundStyle(Color.textPrimary)
                        // `gloss` is optional in the pack schema. A word without
                        // one still belongs on this list — the display form is
                        // what the learner is struggling with.
                        if let gloss = word.gloss {
                            Text(gloss)
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color.textSecondary)
    }
}
