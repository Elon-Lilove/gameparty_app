import Foundation

struct AppBootstrapPayload: Sendable {
    let games: [Game]
    let favoriteIds: [String]
    let historyIds: [String]
}

enum AppBootstrap {
    nonisolated static func loadPayload() -> AppBootstrapPayload {
        // Warm palette table off the main thread before first card render.
        _ = GameHeaderPalettes.count

        return AppBootstrapPayload(
            games: GameStore.load(),
            favoriteIds: FavoritesStore.load(),
            historyIds: HistoryStore.load()
        )
    }
}
