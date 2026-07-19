import Foundation

@main
enum MahjongMemberTokenStoreTest {
    static func main() {
        let suiteName = "PartyGames.MahjongMemberTokenStoreTest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        precondition(MahjongMemberTokenStore.token(for: "abc123", defaults: defaults) == nil)
        MahjongMemberTokenStore.save("member-token", for: "abc123", defaults: defaults)
        precondition(MahjongMemberTokenStore.token(for: "ABC123", defaults: defaults) == "member-token")
        MahjongMemberTokenStore.remove(for: "ABC123", defaults: defaults)
        precondition(MahjongMemberTokenStore.token(for: "ABC123", defaults: defaults) == nil)
    }
}
