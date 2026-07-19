import Foundation

enum MahjongRecentTablePolicy {
    static func shouldEndRemotely(code: String, status: String, isOwner: Bool) -> Bool {
        code != "本地" && status == "active" && isOwner
    }
}
