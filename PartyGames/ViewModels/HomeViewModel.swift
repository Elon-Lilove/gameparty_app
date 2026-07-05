import Foundation
import SwiftUI
import UIKit

@MainActor
@Observable
final class HomeViewModel {
    var games: [Game] = GameStore.load()
    var favoriteIds: [String] = FavoritesStore.load()
    var historyIds: [String] = HistoryStore.load()
    var gameImages: [String: UIImage] = AssetStore.loadImages()

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
    var diceFace: Int = 0
    var deckOffset: Int = 0

    var promoPhase: PromoPhase = .visible
    var promoEndsAt: Date = Date().addingTimeInterval(TimeInterval(DesignTokens.promoCountdownSeconds))
    var membershipBoxEnabled: Bool = SettingsStore.membershipBoxEnabled

    private var spinTask: Task<Void, Never>?

    init() {
        selectedGameId = games.first?.id
        syncPromoWithMembershipSetting()
    }

    // MARK: - Filtering

    var filteredGames: [Game] {
        games.filter { game in
            let playerMatch = isAllPlayerCount(playerCountFilter) || game.matchesPlayerCount(playerCountFilter ?? 0)
            let typeMatch = typeFilter == nil || game.type == typeFilter
            let moodMatch = game.matchesMood(moodFilter)
            return playerMatch && typeMatch && moodMatch
        }
    }

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
        HapticService.light()
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
        HapticService.light()
    }

    func selectGame(_ game: Game) {
        guard spinPhase == .idle, !filteredGames.isEmpty else { return }
        deckOffset = 0
        selectedGameId = game.id
        HapticService.light()
    }

    func openDetail(_ game: Game) {
        detailGame = game
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
    }

    func setMoodFilter(_ mood: MoodCategory) {
        moodFilter = mood
        syncSelectionAfterFilterChange()
    }

    func setPlayerCountFilter(_ count: Int?) {
        playerCountFilter = count
        syncSelectionAfterFilterChange()
    }

    func setTypeFilter(_ type: GameType?) {
        typeFilter = type
        syncSelectionAfterFilterChange()
    }

    func expirePromo() {
        guard membershipBoxEnabled else {
            promoPhase = .hidden
            return
        }
        promoPhase = .closing
        Task {
            try? await Task.sleep(for: .seconds(DesignTokens.promoCollapseMs))
            promoPhase = .hidden
        }
    }

    func setMembershipBoxEnabled(_ enabled: Bool) {
        membershipBoxEnabled = enabled
        SettingsStore.membershipBoxEnabled = enabled
        syncPromoWithMembershipSetting()
    }

    private func syncPromoWithMembershipSetting() {
        if membershipBoxEnabled {
            promoPhase = .visible
            promoEndsAt = Date().addingTimeInterval(TimeInterval(DesignTokens.promoCountdownSeconds))
        } else {
            promoPhase = .hidden
        }
    }

    func runSpin() {
        guard spinPhase == .idle, !filteredGames.isEmpty else { return }
        spinTask?.cancel()

        let count = filteredGames.count
        let safeCurrent = currentIndex
        let targetIndex = count == 1 ? safeCurrent : (safeCurrent + 1) % count
        let stepsToTarget = count == 1 ? 0 : ((targetIndex - safeCurrent + count) % count)
        let totalSteps = count == 1 ? 0 : count + stepsToTarget

        HapticService.medium()
        deckOffset = 0
        spinPhase = .press
        diceFace = 0

        spinTask = Task {
            let start = Date()
            var lastStep = -1

            while !Task.isCancelled {
                let elapsedMs = Date().timeIntervalSince(start) * 1000

                if elapsedMs >= DesignTokens.spinDurationMs {
                    selectedGameId = filteredGames[targetIndex].id
                    deckOffset = 0
                    spinPhase = .idle
                    diceFace = 0
                    if let picked = filteredGames[safeIndex: targetIndex] {
                        HistoryStore.prepend(picked.id, to: &historyIds)
                    }
                    return
                }

                let face = Int(elapsedMs / DesignTokens.spinDiceFaceMs) % 6
                diceFace = face

                if elapsedMs < DesignTokens.spinPressMs {
                    spinPhase = .press
                } else if elapsedMs < DesignTokens.spinSoftStartMs {
                    spinPhase = .accelerate
                } else {
                    let motionSpan = max(1, DesignTokens.spinDurationMs - DesignTokens.spinSoftStartMs)
                    let motionElapsed = elapsedMs - DesignTokens.spinSoftStartMs
                    let t = min(1, motionElapsed / motionSpan)
                    let eased = 1 - pow(1 - t, 4)
                    let step = totalSteps > 0
                        ? min(totalSteps, Int(floor(eased * Double(totalSteps + 1))))
                        : 0
                    if step != lastStep {
                        lastStep = step
                        deckOffset = step
                    }
                    spinPhase = spinMotionPhase(progress: totalSteps > 0 ? Double(step) / Double(totalSteps) : eased)
                }

                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    func historyGames() -> [Game] {
        historyIds.compactMap { id in games.first(where: { $0.id == id }) }
    }

    func favoriteGames() -> [Game] {
        favoriteIds.compactMap { id in games.first(where: { $0.id == id }) }
    }

    // MARK: - Helpers

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
