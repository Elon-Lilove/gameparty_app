import Foundation

@main
struct MahjongOnlineModeSmoke {
    static func main() throws {
        guard MahjongRoomConnectionMode.default == .online else {
            throw SmokeFailure("expected Mahjong rooms to default to online sync")
        }

        let service = MahjongScoreService(baseURL: URL(string: "http://127.0.0.1:8787")!)
        let socketURL = try service.webSocketURL(roomCode: "abc123", memberToken: "token")

        guard socketURL.absoluteString == "wss://mahjong-score-worker.d03054144.workers.dev/rooms/ABC123/ws?memberToken=token" else {
            throw SmokeFailure("expected websocket URLs to use direct Worker access")
        }

        let fallbackURLs = MahjongScoreEndpoint.candidateBaseURLs(preferred: URL(string: "https://party-games-mahjong-join.netlify.app/api")!)
            .map { $0.absoluteString }

        guard fallbackURLs.contains("https://mahjong-score-worker.d03054144.workers.dev") else {
            throw SmokeFailure("expected API fallback URLs to include direct Worker access")
        }
    }
}

private struct SmokeFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
