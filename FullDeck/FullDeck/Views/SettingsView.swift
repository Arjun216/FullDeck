import SwiftUI

/// Reached from a row on the Languages screen, inside the NavigationStack that
/// already lives there. Not a fourth tab, and not a toolbar item: E-2 records
/// that iOS 26 renders toolbar text at a fixed size and the accessibility audit
/// fails it outright, which is why Restore is a row too.
struct SettingsView: View {
    /// `@Bindable`, not `let`: `@Observable` types need it to hand out the
    /// `$viewModel.property` bindings the controls take.
    @Bindable var viewModel: SettingsViewModel
    let credits: CreditsViewModel

    var body: some View {
        Form {
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
    }
}
