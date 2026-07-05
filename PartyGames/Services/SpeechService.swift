import AVFoundation
import Combine

@MainActor
final class SpeechService: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentSentenceIndex = 0

    private let synthesizer = AVSpeechSynthesizer()
    private var utterances: [AVSpeechUtterance] = []

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(game: Game) {
        stop()

        let lines = game.voiceScript.isEmpty ? game.rules : game.voiceScript
        guard !lines.isEmpty else { return }

        utterances = lines.map { line in
            let utterance = AVSpeechUtterance(string: line)
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.rate = 0.48
            utterance.pitchMultiplier = 1.02
            utterance.postUtteranceDelay = 0.12
            return utterance
        }

        isPlaying = true
        currentSentenceIndex = 0
        utterances.forEach(synthesizer.speak)
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        utterances.removeAll()
        isPlaying = false
        currentSentenceIndex = 0
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let spokenText = utterance.speechString
        Task { @MainActor [weak self] in
            guard let self,
                  let index = self.utterances.firstIndex(where: { $0.speechString == spokenText }) else { return }
            self.currentSentenceIndex = index
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let spokenText = utterance.speechString
        Task { @MainActor [weak self] in
            guard let self,
                  let index = self.utterances.firstIndex(where: { $0.speechString == spokenText }) else { return }
            if index == self.utterances.count - 1 {
                self.utterances.removeAll()
                self.isPlaying = false
                self.currentSentenceIndex = 0
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.isPlaying = false
            self?.currentSentenceIndex = 0
        }
    }
}
