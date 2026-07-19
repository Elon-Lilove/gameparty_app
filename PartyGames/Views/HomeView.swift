import SwiftUI

struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    @State private var isCardDeckVisible = false
    @State private var isSidePeeksVisible = false

    var body: some View {
        VStack(spacing: 0) {
            homeHeader
            cardZone
                .padding(.top, DesignTokens.cardZoneTopInset)
                .frame(maxHeight: .infinity)
            actionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .creamBackground()
        .sheet(isPresented: $viewModel.filterSheetOpen) {
            FilterSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.historySheetOpen) {
            HistorySheet(games: viewModel.historyGames()) { game in
                viewModel.selectGame(game)
            }
        }
        .sheet(isPresented: $viewModel.myPanelOpen) {
            MyPanelSheet(viewModel: viewModel)
        }
        .navigationDestination(item: $viewModel.detailGame) { game in
            GameDetailView(game: game, viewModel: viewModel)
                .toolbar(.hidden, for: .tabBar)
        }
        .onChange(of: viewModel.isReady) { _, ready in
            guard ready else { return }
            revealCardDeckIfNeeded()
        }
        .onAppear {
            if viewModel.isReady {
                revealCardDeckIfNeeded()
            }
        }
    }

    private func revealCardDeckIfNeeded() {
        guard !isCardDeckVisible else { return }
        Task { @MainActor in
            await Task.yield()
            isCardDeckVisible = true
            await Task.yield()
            viewModel.preloadImagesForCurrentDeck()
            isSidePeeksVisible = true
        }
    }

    private var homeHeader: some View {
        VStack(spacing: 4) {
            header
            MoodFilterBar(selection: $viewModel.moodFilter) { mood in
                viewModel.setMoodFilter(mood)
            }
        }
        .padding(.top, 4)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("多玩聚会")
                        .font(DesignTokens.titleFont(size: 22))
                        .foregroundStyle(DesignTokens.stone900)
                }
                Text("让聚会更有趣")
                    .font(DesignTokens.bodyFont(size: 12))
                    .foregroundStyle(DesignTokens.stone500)
            }
            Spacer()
            HStack(spacing: 4) {
                iconButton(systemName: "magnifyingglass") {
                    viewModel.homeTab = .library
                }
                Button {
                    viewModel.filterSheetOpen = true
                } label: {
                    FunnelIcon()
                        .fill(DesignTokens.stone500)
                        .frame(width: 19, height: 19)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.hapticPlain)
            }
        }
        .padding(.horizontal, DesignTokens.pageHorizontalPadding)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var cardZone: some View {
        if !viewModel.isReady {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.filteredGames.isEmpty {
            VStack(spacing: 8) {
                Text("没有匹配游戏")
                    .font(DesignTokens.titleFont(size: 18))
                Text("试试调整筛选条件或心情分类。")
                    .font(DesignTokens.bodyFont(size: 13))
                    .foregroundStyle(DesignTokens.stone500)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 48)
        } else if isCardDeckVisible, let featured = viewModel.featuredGame {
            GeometryReader { geo in
                let bottomReserve = DesignTokens.cardBottomReserve
                let availableHeight = max(0, geo.size.height - bottomReserve)
                let deckScale = DesignTokens.deckScale(
                    zoneWidth: geo.size.width,
                    availableHeight: availableHeight
                )
                let scaledStackHeight = DesignTokens.stackMinHeight * deckScale

                HomeCardStackView(
                    games: viewModel.filteredGames,
                    current: featured,
                    images: viewModel.gameImages,
                    isFavorite: { viewModel.isFavorite($0) },
                    spinning: viewModel.isSpinning,
                    spinPhase: viewModel.spinPhase,
                    spinProgress: viewModel.spinProgress,
                    deckScale: deckScale,
                    showsSidePeeks: isSidePeeksVisible,
                    onToggleFavorite: { viewModel.toggleFavorite($0) },
                    onOpen: { viewModel.openDetail(featured) },
                    onSwipeNext: { viewModel.moveSelection(1) },
                    onSwipePrev: { viewModel.moveSelection(-1) }
                )
                .frame(width: geo.size.width, height: DesignTokens.stackMinHeight, alignment: .top)
                .scaleEffect(deckScale, anchor: .top)
                .frame(width: geo.size.width, height: scaledStackHeight, alignment: .top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.bottom, bottomReserve)
            }
            .padding(.horizontal, -DesignTokens.pageHorizontalPadding)
        }
    }

    private var actionBar: some View {
        ZStack(alignment: .top) {
            HStack {
                sideAction(title: "我的收藏", systemName: "bookmark") {
                    viewModel.openMyPanel(.favorites)
                }
                Spacer()
                sideAction(title: "历史记录", systemName: "clock") {
                    viewModel.historySheetOpen = true
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: DesignTokens.diceGlowDiameter, alignment: .center)

            DiceSpinButton(
                spinning: viewModel.isSpinning,
                disabled: viewModel.isSpinning || !viewModel.isReady || viewModel.filteredGames.isEmpty,
                diceFace: viewModel.diceFace,
                onPressStart: { HapticService.light() },
                onRelease: { _ in viewModel.runSpin() }
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: DesignTokens.homeActionBarHeight, alignment: .top)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .clipped()
    }

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DesignTokens.stone500)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.hapticPlain)
    }

    private func sideAction(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(DesignTokens.bodyFont(size: DesignTokens.sideActionFontSize))
            }
            .foregroundStyle(DesignTokens.stone600)
            .frame(width: DesignTokens.sideActionWidth, height: DesignTokens.sideActionHeight)
            .background(DesignTokens.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.sideActionCornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
        }
        .buttonStyle(.hapticPlain)
    }

}

private struct FunnelIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.14, y: rect.midY + rect.height * 0.02))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.14, y: rect.maxY - rect.height * 0.10))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.10, y: rect.maxY - rect.height * 0.22))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.10, y: rect.midY + rect.height * 0.02))
        path.closeSubpath()
        return path
    }
}
