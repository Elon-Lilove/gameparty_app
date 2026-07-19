import Foundation

@main
enum MahjongRecentTablePolicyTest {
    static func main() {
        precondition(MahjongRecentTablePolicy.shouldEndRemotely(code: "ABC123", status: "active", isOwner: true))
        precondition(!MahjongRecentTablePolicy.shouldEndRemotely(code: "ABC123", status: "active", isOwner: false))
        precondition(!MahjongRecentTablePolicy.shouldEndRemotely(code: "ABC123", status: "ended", isOwner: true))
        precondition(!MahjongRecentTablePolicy.shouldEndRemotely(code: "本地", status: "active", isOwner: true))
    }
}
