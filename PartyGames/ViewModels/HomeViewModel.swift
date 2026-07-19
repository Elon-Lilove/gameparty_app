import Foundation
import SwiftUI
import UIKit

@MainActor
@Observable
final class HomeViewModel {
    private(set) var isReady = false
    var games: [Game] = []
    var favoriteIds: [String] = []
    var historyIds: [String] = []
    var gameImages: [String: UIImage] = [:]

    var moodFilter: MoodCategory = .funny
    var playerCountFilter: Int? = nil
    var typeFilter: GameType? = nil

    var selectedGameId: String?
    var detailGame: Game?
    var homeTab: HomeTab = .home

    var filterSheetOpen = false
    var historySheetOpen = false
    var myPanelOpen = false
    var myPanelScreen: MyPanelScreen = .menu

    var spinPhase: SpinPhase = .idle
    var spinProgress: Double = 0
    var diceFace: Int = 0
    var deckOffset: Int = 0

    private(set) var filteredGames: [Game] = []
    private var gamesById: [String: Game] = [:]
    private var spinTask: Task<Void, Never>?
    private var imagePreloadTask: Task<Void, Never>?
    private var hasBootstrapped = false

    init() {}

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        let payload = await Task.detached(priority: .userInitiated) {
            AppBootstrap.loadPayload()
        }.value

        games = payload.games
        favoriteIds = payload.favoriteIds
        historyIds = payload.historyIds
        gamesById = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0) })
        selectedGameId = games.first?.id
        rebuildFilteredGames()
        isReady = true
        // 图片预加载交给首页首帧后再做，避免拖慢 isReady。
    }

    // MARK: - Images

    func gameImage(for gameId: String) -> UIImage? {
        gameImages[gameId]
    }

    func preloadImages(for gameIds: [String]) {
        let missing = Set(gameIds.filter { gameImages[$0] == nil })
        guard !missing.isEmpty else { return }

        imagePreloadTask?.cancel()
        imagePreloadTask = Task {
            let loaded = await Task.detached(priority: .utility) {
                AssetStore.loadImages(for: Array(missing))
            }.value

            guard !Task.isCancelled else { return }
            for (gameId, image) in loaded where gameImages[gameId] == nil {
                gameImages[gameId] = image
            }
        }
    }

    func preloadImagesForCurrentDeck() {
        guard let featured = featuredGame else { return }
        let ids = deckImageGameIDs(around: featured.id)
        preloadImages(for: ids)
    }

    func preloadImagesForLibrary() {
        preloadImages(for: filteredGames.map(\.id))
    }

    // MARK: - Filtering

    var activeSelection: Game? {
        if let id = selectedGameId,
           let game = filteredGames.first(where: { $0.id == id }) {
            return game
        }
        return filteredGames.first
    }

    var currentIndex: Int {
        guard let active = activeSelection else { return 0 }
        return filteredGames.firstIndex(where: { $0.id == active.id }) ?? 0
    }

    var featuredGame: Game? {
        guard !filteredGames.isEmpty else { return nil }
        if spinPhase == .idle {
            return activeSelection ?? filteredGames.first
        }
        let base = currentIndex
        let index = (base + deckOffset + filteredGames.count) % filteredGames.count
        return filteredGames[index]
    }

    var recommendPlayerLabel: String {
        recommendLabel(for: playerCountFilter)
    }

    var isSpinning: Bool { spinPhase != .idle }

    // MARK: - Actions

    func toggleFavorite(_ gameId: String) {
        FavoritesStore.toggle(gameId, in: &favoriteIds)
    }

    func isFavorite(_ gameId: String) -> Bool {
        FavoritesStore.isFavorite(gameId, in: favoriteIds)
    }

    func moveSelection(_ direction: Int) {
        guard spinPhase == .idle, !filteredGames.isEmpty, let active = activeSelection else { return }
        let current = filteredGames.firstIndex(where: { $0.id == active.id }) ?? 0
        let next = (current + direction + filteredGames.count) % filteredGames.count
        deckOffset = 0
        selectedGameId = filteredGames[next].id
        preloadImagesForCurrentDeck()
    }

    func selectGame(_ game: Game) {
        guard spinPhase == .idle, !filteredGames.isEmpty else { return }
        deckOffset = 0
        selectedGameId = game.id
        preloadImagesForCurrentDeck()
    }

    func openDetail(_ game: Game) {
        detailGame = game
        preloadImages(for: [game.id])
    }

    func closeDetail() {
        detailGame = nil
    }

    func openMyPanel(_ screen: MyPanelScreen = .menu) {
        myPanelScreen = screen
        myPanelOpen = true
    }

    func closeMyPanel() {
        myPanelOpen = false
        myPanelScreen = .menu
    }

    func syncSelectionAfterFilterChange() {
        if let id = selectedGameId,
           filteredGames.contains(where: { $0.id == id }) {
            return
        }
        selectedGameId = filteredGames.first?.id
        deckOffset = 0
        preloadImagesForCurrentDeck()
    }

    func setMoodFilter(_ mood: MoodCategory) {
        if moodFilter == mood, mood != .all {
            moodFilter = .all
        } else {
            moodFilter = mood
        }
        rebuildFilteredGames()
        syncSelectionAfterFilterChange()
    }

    func setPlayerCountFilter(_ count: Int?) {
        playerCountFilter = count
        rebuildFilteredGames()
        syncSelectionAfterFilterChange()
    }

    func setTypeFilter(_ type: GameType?) {
        typeFilter = type
        rebuildFilteredGames()
        syncSelectionAfterFilterChange()
    }

    func runSpin() {
        runSpin(momentum: .tapInertia, totalDurationMs: DesignTokens.spinTapDurationMs)
    }

    func runSpin(momentum: SpinMomentum, totalDurationMs: Double? = nil) {
        guard spinPhase == .idle, !filteredGames.isEmpty else { return }
        spinTask?.cancel()

        let count = filteredGames.count
        let safeCurrent = currentIndex
        let targetIndex = count == 1 ? safeCurrent : (safeCurrent + 1) % count
        let stepsToTarget = count == 1 ? 0 : ((targetIndex - safeCurrent + count) % count)
        let extraRevolutions = momentum.extraRevolutions
        let totalSteps = count == 1 ? 0 : (extraRevolutions * count) + count + stepsToTarget
        let spinTotalMs = totalDurationMs ?? momentum.spinDurationMs
        let settleMs = DesignTokens.spinSettleMs
        let motionEndMs = max(DesignTokens.spinSoftStartMs, spinTotalMs - settleMs)

        HapticService.medium()
        deckOffset = 0
        spinProgress = 0
        spinPhase = .press
        diceFace = 0

        spinTask = Task {
            let start = Date()
            var lastStep = -1

            while !Task.isCancelled {
                let elapsedMs = Date().timeIntervalSince(start) * 1000

                if elapsedMs >= spinTotalMs {
                    selectedGameId = filteredGames[targetIndex].id
                    deckOffset = 0
                    spinPhase = .idle
                    spinProgress = 0
                    diceFace = 0
                    if let picked = filteredGames[safeIndex: targetIndex] {
                        HistoryStore.prepend(picked.id, to: &historyIds)
                    }
                    preloadImagesForCurrentDeck()
                    return
                }

                let face = Int(elapsedMs / DesignTokens.spinDiceFaceMs) % 6
                diceFace = face

                if elapsedMs < DesignTokens.spinPressMs {
                    spinPhase = .press
                } else if elapsedMs < DesignTokens.spinSoftStartMs {
                    spinPhase = .accelerate
                    spinProgress = 0.08
                } else if elapsedMs >= motionEndMs {
                    if totalSteps > 0, lastStep != totalSteps {
                        lastStep = totalSteps
                        deckOffset = totalSteps
                    }
                    spinPhase = .settle
                    spinProgress = 1
                } else {
                    let motionSpan = max(1, motionEndMs - DesignTokens.spinSoftStartMs)
                    let motionElapsed = elapsedMs - DesignTokens.spinSoftStartMs
                    let t = min(1, motionElapsed / motionSpan)
                    let eased = CubicBezierTiming.spinProgress(at: t)
                    let step = totalSteps > 0
                        ? min(totalSteps, Int(floor(eased * Double(totalSteps + 1))))
                        : 0
                    if step != lastStep {
                        lastStep = step
                        deckOffset = step
                    }
                    spinProgress = totalSteps > 0 ? Double(step) / Double(totalSteps) : eased
                    spinPhase = spinMotionPhase(progress: spinProgress)
                }

                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    func historyGames() -> [Game] {
        historyIds.compactMap { gamesById[$0] }
    }

    func favoriteGames() -> [Game] {
        favoriteIds.compactMap { gamesById[$0] }
    }

    // MARK: - Helpers

    private func rebuildFilteredGames() {
        filteredGames = games.filter { game in
            let playerMatch = isAllPlayerCount(playerCountFilter) || game.matchesPlayerCount(playerCountFilter ?? 0)
            let typeMatch = typeFilter == nil || game.type == typeFilter
            let moodMatch = game.matchesMood(moodFilter)
            return playerMatch && typeMatch && moodMatch
        }
    }

    private func deckImageGameIDs(around gameId: String) -> [String] {
        guard let index = filteredGames.firstIndex(where: { $0.id == gameId }) else {
            return [gameId]
        }

        let count = filteredGames.count
        var ids: [String] = []
        for offset in -2...2 {
            let wrapped = (index + offset + count) % count
            ids.append(filteredGames[wrapped].id)
        }
        return ids
    }

    private func isAllPlayerCount(_ count: Int?) -> Bool {
        count == nil || count == 0
    }

    private func recommendLabel(for count: Int?) -> String {
        if isAllPlayerCount(count) { return "4-6" }
        guard let count else { return "4-6" }
        if count == 2 { return "2" }
        if count <= 4 { return "3-6" }
        return "5+"
    }

    private func spinMotionPhase(progress: Double) -> SpinPhase {
        if progress < 0.18 { return .accelerate }
        if progress < 0.52 { return .chaos }
        return .decelerate
    }
}

private extension Array {
    subscript(safeIndex index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
