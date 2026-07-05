import SwiftUI

public struct RootView: View {
    @State private var viewModel = HomeViewModel()

    public init() {}

    public var body: some View {
        Group {
            switch viewModel.homeTab {
            case .home:
                NavigationStack {
                    HomeView(viewModel: viewModel)
                }
            case .library:
                NavigationStack {
                    LibraryGridView(viewModel: viewModel)
                }
            case .me:
                NavigationStack {
                    MyTabView(viewModel: viewModel)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.detailGame == nil {
                customTabBar
            }
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 4) {
            tabButton(.home, title: "首页", systemImage: "house.fill")
            tabButton(.library, title: "游戏库", systemImage: "gamecontroller.fill")
            tabButton(.me, title: "我的", systemImage: "face.smiling")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignTokens.stone400.opacity(0.10))
                .frame(height: 1)
        }
    }

    private func tabButton(_ tab: HomeTab, title: String, systemImage: String) -> some View {
        let selected = viewModel.homeTab == tab
        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                viewModel.homeTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected && tab == .home ? DesignTokens.brandYellow : (selected ? DesignTokens.stone900 : DesignTokens.stone400))
                Text(title)
                    .font(DesignTokens.bodyFont(size: 10))
                    .foregroundStyle(selected ? DesignTokens.stone900 : DesignTokens.stone400)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MyTabView: View {
    @Bindable var viewModel: HomeViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MY SPACE")
                        .font(DesignTokens.bodyFont(size: 11))
                        .tracking(2.2)
                        .foregroundStyle(DesignTokens.stone400)
                    Text("我的")
                        .font(DesignTokens.titleFont(size: 30))
                        .foregroundStyle(DesignTokens.stone900)
                    Text("收藏常玩的游戏，随时打开聚会小工具。")
                        .font(DesignTokens.bodyFont(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.stone500)
                }

                VStack(spacing: 12) {
                    menuCard(
                        title: "我的收藏",
                        subtitle: "已收藏 \(viewModel.favoriteGames().count) 个游戏",
                        systemImage: "star.fill",
                        foreground: .orange,
                        background: Color.orange.opacity(0.14)
                    ) {
                        viewModel.openMyPanel(.favorites)
                    }
                    menuCard(
                        title: "计分器",
                        subtitle: "记录玩家得分",
                        systemImage: "trophy.fill",
                        foreground: Color(red: 0.72, green: 0.47, blue: 0.08),
                        background: Color.orange.opacity(0.13)
                    ) {
                        viewModel.openMyPanel(.scorekeeper)
                    }
                    menuCard(
                        title: "骰子",
                        subtitle: "随机掷出 1-6 点",
                        systemImage: "dice.fill",
                        foreground: .purple,
                        background: Color.purple.opacity(0.12)
                    ) {
                        viewModel.openMyPanel(.dice)
                    }
                    menuCard(
                        title: "管理者模式",
                        subtitle: "查看游戏卡片与管理入口",
                        systemImage: "lock.fill",
                        foreground: DesignTokens.stone600,
                        background: DesignTokens.stone400.opacity(0.18)
                    ) {
                        viewModel.openMyPanel(.admin)
                    }
                }

                HStack(spacing: 12) {
                    compactAction(title: "历史记录", systemImage: "clock") {
                        viewModel.historySheetOpen = true
                    }
                    compactAction(title: "筛选游戏", systemImage: "line.3.horizontal.decrease") {
                        viewModel.filterSheetOpen = true
                    }
                }
            }
            .padding(.horizontal, DesignTokens.pageHorizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .creamBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $viewModel.myPanelOpen) {
            MyPanelSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.historySheetOpen) {
            HistorySheet(games: viewModel.historyGames()) { game in
                viewModel.selectGame(game)
            }
        }
        .sheet(isPresented: $viewModel.filterSheetOpen) {
            FilterSheet(viewModel: viewModel)
        }
    }

    private func menuCard(
        title: String,
        subtitle: String,
        systemImage: String,
        foreground: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(foreground)
                    .frame(width: 48, height: 48)
                    .background(background)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(DesignTokens.titleFont(size: 18))
                        .foregroundStyle(DesignTokens.stone900)
                    Text(subtitle)
                        .font(DesignTokens.bodyFont(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.stone500)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DesignTokens.stone400)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(DesignTokens.stone400.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func compactAction(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(DesignTokens.bodyFont(size: 13))
                .foregroundStyle(DesignTokens.stone600)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(Color.white.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
