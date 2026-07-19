import Foundation

@main
enum MahjongRealtimeProtocolTest {
    static func main() throws {
        let data = Data(
            #"{"type":"error","error":"Use give_score","operationId":"invalid-score","actorDeviceId":"guest-device"}"#.utf8
        )
        let envelope = try JSONDecoder().decode(MahjongRealtimeEnvelope.self, from: data)
        let expected = MahjongRealtimeAcknowledgement(
            operationId: "invalid-score",
            actorDeviceId: "guest-device"
        )

        precondition(envelope.type == "error")
        precondition(envelope.error == "Use give_score")
        precondition(envelope.acknowledgement == expected)
    }
}
