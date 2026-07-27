import Domain

/// Spoken audio for a card (FR-7, spec D3). Presentation owns this port — Domain
/// never learns that audio exists. Callers cannot tell on-device TTS from a
/// future bundled recording; only the adapter changes.
///
/// `@MainActor` because the concrete adapter wraps `AVSpeechSynthesizer`, a
/// non-`Sendable` class. ViewModels are already main-actor, so calls are free.
@MainActor
protocol SpeechService {
    /// Throws `SpeechError.voiceUnavailable` when the device has no voice for
    /// this language — the caller degrades, it never crashes.
    func speak(_ text: String, language: LanguageCode) throws
    func stop()
}

enum SpeechError: Error, Equatable {
    case voiceUnavailable(LanguageCode)
}
