import SwiftUI

private enum ToolsScreen: Hashable {
    case scorekeeper
    case mahjongScorekeeper
    case dice
}

struct ToolsTabView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(showsIndicators: false) {
                menuContent
                    .padding(.horizontal, DesignTokens.pageHorizontalPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .creamBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ToolsScreen.self) { screen in
                switch screen {
                case .scorekeeper:
                    toolDetail(title: "计分器") {
                        ScorekeeperView()
                    }
                case .mahjongScorekeeper:
                    MahjongScorekeeperView()
                case .dice:
                    toolDetail(title: "骰子") {
                        DiceToolView()
                    }
                }
            }
        }
    }

    private func toolDetail<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView(showsIndicators: false) {
            content()
                .padding(.horizontal, DesignTokens.pageHorizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
        .creamBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TOOLS")
                    .font(DesignTokens.bodyFont(size: 11))
                    .tracking(2.2)
                    .foregroundStyle(DesignTokens.stone400)
                Text("工具")
                    .font(DesignTokens.titleFont(size: 30))
                    .foregroundStyle(DesignTokens.stone900)
                Text("聚会常用小工具，计分、掷骰一站搞定。")
                    .font(DesignTokens.bodyFont(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.stone500)
            }

            VStack(spacing: 12) {
                menuCard(
                    title: "计分器",
                    subtitle: "记录玩家得分",
                    systemImage: "trophy.fill",
                    foreground: Color(red: 0.72, green: 0.47, blue: 0.08),
                    background: Color.orange.opacity(0.13)
                ) {
                    path.append(ToolsScreen.scorekeeper)
                }
                menuCard(
                    title: "麻将计分器",
                    subtitle: "在线房间，最多 20 人",
                    systemImage: "square.grid.3x3.fill",
                    foreground: Color(red: 0.10, green: 0.55, blue: 0.42),
                    background: Color.green.opacity(0.12)
                ) {
                    path.append(ToolsScreen.mahjongScorekeeper)
                }
                menuCard(
                    title: "骰子",
                    subtitle: "随机掷出 1-6 点",
                    systemImage: "dice.fill",
                    foreground: .purple,
                    background: Color.purple.opacity(0.12)
                ) {
                    path.append(ToolsScreen.dice)
                }
            }
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
}
