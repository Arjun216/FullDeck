import AVFoundation
import Domain

/// On-device TTS (spec D3, FR-7). The only place in the app that knows audio is
/// synthesized rather than recorded — swapping in bundled recordings later means
/// writing a second `SpeechService`, not touching a caller.
@MainActor
final class AVSpeechService: SpeechService {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, language: LanguageCode) throws {
        guard let voice = AVSpeechSynthesisVoice(language: language.rawValue) else {
            throw SpeechError.voiceUnavailable(language)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
