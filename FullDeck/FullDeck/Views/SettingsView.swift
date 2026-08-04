import SwiftUI
import UIKit

/// Reached from a row on the Languages screen, inside the NavigationStack that
/// already lives there. Not a fourth tab, and not a toolbar item: E-2 records
/// that iOS 26 renders toolbar text at a fixed size and the accessibility audit
/// fails it outright, which is why Restore is a row too.
struct SettingsView: View {
    /// `@Bindable`, not `let`: `@Observable` types need it to hand out the
    /// `$viewModel.property` bindings the controls take.
    @Bindable var viewModel: SettingsViewModel
    let credits: CreditsViewModel

    /// Revoking notification permission means leaving for iOS Settings and
    /// coming back, which resumes the app without re-creating this view — so
    /// `.task` alone never sees it. Found by revoking permission by hand;
    /// no ViewModel test can catch it, because a ViewModel test calls
    /// `refreshAuthorization()` itself and cannot know whether anything else does.
    @Environment(\.scenePhase) private var scenePhase

    /// Hoisted out of the condition purely to keep the `if` on one line —
    /// SwiftLint's `opening_brace` and `swift format` disagree about wrapped
    /// conditions, and SwiftLint is the gate (CLAUDE.md).
    private static let systemSettings = URL(string: UIApplication.openSettingsURLString)

    var body: some View {
        Form {
            Section {
                // A computed Binding, not `$viewModel.isReminderOn`: the property
                // is private(set) because turning it on is an async negotiation
                // with iOS that can end in "no", not a value the view may assign.
                Toggle(
                    "Daily reminder",
                    isOn: Binding(
                        get: { viewModel.isReminderOn },
                        set: { on in Task { await viewModel.setReminder(on: on) } }))
                if viewModel.isReminderOn {
                    DatePicker(
                        "Time",
                        selection: Binding(
                            get: { viewModel.reminderDate },
                            set: { date in
                                Task { await viewModel.setReminderTime(from: date) }
                            }),
                        displayedComponents: .hourAndMinute)
                }
                if let note = viewModel.permissionNote {
                    Text(note)
                        .foregroundStyle(Color.textSecondary)
                    // Only for a denial. A scheduling failure is retryable here,
                    // and sending the learner to iOS Settings to fix nothing is
                    // worse than saying nothing.
                    if viewModel.noteCause == .permissionDenied, let url = Self.systemSettings {
                        // Same contrast substitution as the licence link. The
                        // audit never reached this one — it only renders once
                        // permission is denied — so it would have shipped
                        // failing.
                        Link("Open Settings", destination: url)
                            .tint(Color.accentFill)
                    }
                }
            } header: {
                sectionHeader("Reminder")
            }
            .listRowBackground(Color.appBackground)
            Section {
                Stepper(value: $viewModel.newWordsPerDay, in: SettingsViewModel.capRange) {
                    Text("New words per day: \(viewModel.newWordsPerDay)")
                        .foregroundStyle(Color.textPrimary)
                }
            } header: {
                sectionHeader("Study")
            }
            .listRowBackground(Color.appBackground)
            CreditsSection(viewModel: credits)
        }
        // A Form paints its own background over the one set below it, the same
        // way the Languages List does.
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Settings")
        // On the Form, not on the Section: a Section is a layout container, not
        // a reliable host for a lifecycle modifier.
        .task { await credits.load() }
        // Covers arriving at the screen...
        .task { await viewModel.refreshAuthorization() }
        // ...and returning to it from iOS Settings, which is the only path a
        // revocation can take.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.refreshAuthorization() }
        }
    }

    /// SwiftUI's default section-header grey fails the accessibility audit on
    /// the warm `AppBackground` — "Contrast is not high enough ... unless font
    /// size is larger", caught the first time Settings was audited. The
    /// project's own `TextSecondary` measures 7.36:1 there, so the fix is to
    /// stop inheriting the system colour. Same family as L-5.
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .foregroundStyle(Color.textSecondary)
    }
}
