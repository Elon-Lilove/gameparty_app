import SwiftUI

public struct RootView: View {
    @State private var viewModel = HomeViewModel()

    public init() {}

    public var body: some View {
        TabView(selection: tabSelection) {
            Tab("首页", systemImage: "house.fill", value: HomeTab.home) {
                NavigationStack {
                    HomeView(viewModel: viewModel)
                }
            }

            Tab("游戏库", systemImage: "gamecontroller.fill", value: HomeTab.library) {
                NavigationStack {
                    LibraryGridView(viewModel: viewModel)
                }
            }

            Tab("工具", systemImage: "wrench.and.screwdriver.fill", value: HomeTab.tools) {
                NavigationStack {
                    ToolsTabView()
                }
            }

            Tab("我的", systemImage: "face.smiling", value: HomeTab.me) {
                NavigationStack {
                    MyTabView(viewModel: viewModel)
                }
            }
        }
        .tint(DesignTokens.tabAccent)
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    private var tabSelection: Binding<HomeTab> {
        Binding(
            get: { viewModel.homeTab },
            set: { newTab in
                guard newTab != viewModel.homeTab else { return }
                viewModel.homeTab = newTab
                HapticService.medium()
            }
        )
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
                    Text("收藏常玩的游戏，或进入管理者模式。")
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
                        title: "管理者模式",
                        subtitle: "管理游戏卡片",
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
            .padding(.bottom, 24)
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
            .background(DesignTokens.surfaceElevatedSoft)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(DesignTokens.borderSubtle, lineWidth: 1)
            }
        }
        .buttonStyle(.hapticPlain)
    }

    private func compactAction(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(DesignTokens.bodyFont(size: 13))
                .foregroundStyle(DesignTokens.stone600)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(DesignTokens.surfaceElevatedSoft)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.hapticPlain)
    }
}
