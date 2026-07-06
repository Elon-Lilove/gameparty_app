import SwiftUI

private enum ToolsScreen {
    case menu
    case scorekeeper
    case dice
}

struct ToolsTabView: View {
    @State private var screen: ToolsScreen = .menu

    var body: some View {
        VStack(spacing: 0) {
            if screen != .menu {
                detailHeader
            }

            ScrollView(showsIndicators: false) {
                Group {
                    switch screen {
                    case .menu:
                        menuContent
                    case .scorekeeper:
                        ScorekeeperView()
                    case .dice:
                        DiceToolView()
                    }
                }
                .padding(.horizontal, DesignTokens.pageHorizontalPadding)
                .padding(.top, screen == .menu ? 14 : 0)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .creamBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var detailHeader: some View {
        HStack(spacing: 10) {
            circleButton(systemImage: "chevron.left") {
                screen = .menu
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("TOOLS")
                    .font(DesignTokens.bodyFont(size: 10))
                    .tracking(2)
                    .foregroundStyle(DesignTokens.stone400)
                Text(screenTitle)
                    .font(DesignTokens.titleFont(size: 24))
                    .foregroundStyle(DesignTokens.stone900)
            }

            Spacer()
        }
        .padding(.horizontal, DesignTokens.pageHorizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.borderSubtle)
                .frame(height: 1)
        }
    }

    private var screenTitle: String {
        switch screen {
        case .menu: return "工具"
        case .scorekeeper: return "计分器"
        case .dice: return "骰子"
        }
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
                    screen = .scorekeeper
                }
                menuCard(
                    title: "骰子",
                    subtitle: "随机掷出 1-6 点",
                    systemImage: "dice.fill",
                    foreground: .purple,
                    background: Color.purple.opacity(0.12)
                ) {
                    screen = .dice
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

    private func circleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DesignTokens.stone600)
                .frame(width: 44, height: 44)
                .background(DesignTokens.stone400.opacity(0.16))
                .clipShape(Circle())
        }
        .buttonStyle(.hapticPlain)
    }
}
