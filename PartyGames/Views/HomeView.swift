import SwiftUI

struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    @State private var promoRemaining = DesignTokens.promoCountdownSeconds
    @State private var promoTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            homeHeader
            cardZone
                .frame(maxHeight: .infinity)
            actionBar
        }
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
        .onAppear(perform: startPromoTimer)
        .onDisappear {
            promoTask?.cancel()
        }
        .navigationDestination(item: $viewModel.detailGame) { game in
            GameDetailView(game: game, viewModel: viewModel)
                .toolbar(.hidden, for: .tabBar)
        }
    }

    private var homeHeader: some View {
        VStack(spacing: 8) {
            header
            MoodFilterBar(selection: $viewModel.moodFilter) { mood in
                viewModel.setMoodFilter(mood)
            }
            recommendLine
            promoBanner
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("好友聚会")
                        .font(DesignTokens.titleFont(size: 26))
                        .foregroundStyle(DesignTokens.stone900)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DesignTokens.brandYellow)
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
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignTokens.pageHorizontalPadding)
        .padding(.top, 8)
    }

    private var recommendLine: some View {
        (
            Text("已为你推荐适合 ")
                .foregroundStyle(DesignTokens.stone400)
            + Text(viewModel.recommendPlayerLabel)
                .foregroundStyle(DesignTokens.stone900)
                .fontWeight(.black)
            + Text(" 人的游戏")
                .foregroundStyle(DesignTokens.stone400)
        )
        .font(DesignTokens.bodyFont(size: 12))
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var promoBanner: some View {
        if viewModel.promoPhase != .hidden {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("PREMIUM")
                            .font(DesignTokens.bodyFont(size: 10))
                            .foregroundStyle(.orange)
                        Text("解锁更多游戏")
                            .font(DesignTokens.bodyFont(size: 13))
                            .foregroundStyle(DesignTokens.stone900)
                    }
                    Text("限时81% off")
                        .font(DesignTokens.bodyFont(size: 11))
                        .foregroundStyle(DesignTokens.stone500)
                }
                Spacer()
                Button {
                    viewModel.homeTab = .library
                } label: {
                    VStack(spacing: 2) {
                        Text("立即获取")
                            .font(DesignTokens.bodyFont(size: 12))
                        Text(formatCountdown(promoRemaining))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                    .foregroundStyle(DesignTokens.stone900)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DesignTokens.stone400.opacity(0.25), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.promoPhase != .visible)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(white: 0.96))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, DesignTokens.pageHorizontalPadding)
            .opacity(viewModel.promoPhase == .closing ? 0 : 1)
            .animation(.easeOut(duration: DesignTokens.promoCollapseMs), value: viewModel.promoPhase)
        }
    }

    @ViewBuilder
    private var cardZone: some View {
        if viewModel.filteredGames.isEmpty {
            VStack(spacing: 8) {
                Text("没有匹配游戏")
                    .font(DesignTokens.titleFont(size: 18))
                Text("试试调整筛选条件或心情分类。")
                    .font(DesignTokens.bodyFont(size: 13))
                    .foregroundStyle(DesignTokens.stone500)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        } else if let featured = viewModel.featuredGame {
            HomeCardStackView(
                games: viewModel.filteredGames,
                current: featured,
                images: viewModel.gameImages,
                isFavorite: viewModel.isFavorite(featured.id),
                spinning: viewModel.isSpinning,
                onToggleFavorite: { viewModel.toggleFavorite(featured.id) },
                onOpen: { viewModel.openDetail(featured) },
                onSwipeNext: { viewModel.moveSelection(1) },
                onSwipePrev: { viewModel.moveSelection(-1) }
            )
            .padding(.horizontal, DesignTokens.pageHorizontalPadding)
        }
    }

    private var actionBar: some View {
        HStack {
            sideAction(title: "我的收藏", systemName: "bookmark") {
                viewModel.openMyPanel(.favorites)
            }
            Spacer()
            DiceSpinButton(
                spinning: viewModel.isSpinning,
                disabled: viewModel.isSpinning || viewModel.filteredGames.isEmpty,
                diceFace: viewModel.diceFace,
                onTap: viewModel.runSpin
            )
            Spacer()
            sideAction(title: "历史记录", systemName: "clock") {
                viewModel.historySheetOpen = true
            }
        }
        .frame(height: 90, alignment: .bottom)
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
    }

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DesignTokens.stone500)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
    }

    private func sideAction(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(DesignTokens.bodyFont(size: 11))
            }
            .foregroundStyle(DesignTokens.stone600)
            .frame(width: 76, height: 52)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
    }

    private func startPromoTimer() {
        guard viewModel.promoPhase == .visible else { return }
        promoTask?.cancel()
        promoTask = Task { @MainActor in
            while !Task.isCancelled, viewModel.promoPhase == .visible {
                promoRemaining = max(0, Int(ceil(viewModel.promoEndsAt.timeIntervalSinceNow)))
                if promoRemaining <= 0 {
                    viewModel.expirePromo()
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func formatCountdown(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
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
