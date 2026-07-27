import SwiftUI

/// The shared `.failed` state rendering for the three top-level views. Phase 10
/// owns the final user-facing copy — this keeps the current wording verbatim.
struct ErrorStateView: View {
    let message: String

    var body: some View {
        ContentUnavailableView(
            "Something went wrong", systemImage: "exclamationmark.triangle",
            description: Text(message))
    }
}
