import AVFoundation

@MainActor
final class MahjongVoiceAnnouncer {
    private let synthesizer = AVSpeechSynthesizer()
    private var knownEventIDs = Set<String>()
    private var hasPrimed = false

    func prime(with snapshot: MahjongRoomSnapshot?) {
        knownEventIDs = Set(snapshot?.recentEvents.map(\.id) ?? [])
        hasPrimed = true
    }

    func announceNewEvents(in snapshot: MahjongRoomSnapshot, enabled: Bool) {
        guard hasPrimed else {
            prime(with: snapshot)
            return
        }

        let newEvents = snapshot.recentEvents
            .filter { knownEventIDs.insert($0.id).inserted }
            .reversed()

        guard enabled else { return }
        for event in newEvents {
            let playerName = snapshot.players.first(where: { $0.id == event.playerId })?.name ?? "玩家"
            let sign = event.delta > 0 ? "加" : "减"
            let utterance = AVSpeechUtterance(string: "\(playerName)\(sign)\(abs(event.delta))分")
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.rate = 0.48
            synthesizer.speak(utterance)
        }
    }
}
