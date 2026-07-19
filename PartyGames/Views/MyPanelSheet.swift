import SwiftUI

struct MyPanelSheet: View {
    @Bindable var viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var favoriteQuery = ""
    @State private var adminPasswordInput = ""
    @State private var adminError = ""
    @AppStorage("partyGames.adminUnlocked") private var adminUnlocked = false
    @AppStorage("partyGames.adminPassword") private var adminPassword = "888888"

    var body: some View {
        VStack(spacing: 0) {
            panelHeader

            ScrollView(showsIndicators: false) {
                Group {
                switch viewModel.myPanelScreen {
                case .menu:
                    menuItems
                case .favorites:
                    favoritesList
                case .admin:
                    adminPanel
                }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .creamBackground()
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var panelHeader: some View {
        HStack(spacing: 10) {
            if viewModel.myPanelScreen != .menu {
                circleButton(systemImage: "chevron.left") {
                    viewModel.myPanelScreen = .menu
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("MY SPACE")
                    .font(DesignTokens.bodyFont(size: 10))
                    .tracking(2)
                    .foregroundStyle(DesignTokens.stone400)
                Text(screenTitle)
                    .font(DesignTokens.titleFont(size: 24))
                    .foregroundStyle(DesignTokens.stone900)
            }
            Spacer()
            circleButton(systemImage: "xmark") {
                viewModel.closeMyPanel()
                dismiss()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.borderSubtle)
                .frame(height: 1)
        }
    }

    private var screenTitle: String {
        switch viewModel.myPanelScreen {
        case .menu: return "我的"
        case .favorites: return "我的收藏"
        case .admin: return "管理者模式"
        }
    }

    private var menuItems: some View {
        VStack(spacing: 12) {
            panelMenuCard(title: "我的收藏", subtitle: "查找收藏的游戏", icon: "star.fill", tone: .orange) {
                viewModel.myPanelScreen = .favorites
            }
            panelMenuCard(title: "管理者模式", subtitle: "管理游戏卡片", icon: "lock.fill", tone: DesignTokens.stone600) {
                viewModel.myPanelScreen = .admin
            }
        }
    }

    @ViewBuilder
    private var favoritesList: some View {
        let favorites = viewModel.favoriteGames().filter {
            favoriteQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(favoriteQuery)
        }
        VStack(alignment: .leading, spacing: 14) {
            Text("搜索并查看你收藏的游戏，点击卡片可打开详情。")
                .font(DesignTokens.bodyFont(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.stone500)

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DesignTokens.stone400)
                TextField("搜索收藏的游戏", text: $favoriteQuery)
                    .font(DesignTokens.bodyFont(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(DesignTokens.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if favorites.isEmpty {
                ContentUnavailableView(
                    favoriteQuery.isEmpty ? "还没有收藏的游戏" : "没有找到收藏",
                    systemImage: "star",
                    description: Text(favoriteQuery.isEmpty ? "在游戏详情页点爱心即可收藏。" : "试试搜索其他游戏名称。")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 36)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(favorites) { game in
                        favoriteCard(game)
                    }
                }
            }
        }
    }

    private var adminPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(DesignTokens.stone500)
                Text("管理者模式")
                    .font(DesignTokens.titleFont(size: 19))
                    .foregroundStyle(DesignTokens.stone900)
            }

            if adminUnlocked {
                HStack {
                    Label("已解锁管理者权限", systemImage: "checkmark.seal.fill")
                        .font(DesignTokens.bodyFont(size: 13))
                        .foregroundStyle(.green)
                    Spacer()
                    Button("退出管理") {
                        adminUnlocked = false
                    }
                    .font(DesignTokens.bodyFont(size: 12))
                    .foregroundStyle(DesignTokens.stone600)
                    .buttonStyle(.hapticPlain)
                }

                Text("游戏卡片管理")
                    .font(DesignTokens.titleFont(size: 17))
                    .foregroundStyle(DesignTokens.stone900)

                LazyVStack(spacing: 9) {
                    ForEach(viewModel.games) { game in
                        HStack(spacing: 12) {
                            Text(game.type.emoji)
                                .font(.system(size: 22))
                                .frame(width: 42, height: 42)
                                .background(DesignTokens.surfaceMuted)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(game.name)
                                    .font(DesignTokens.bodyFont(size: 15))
                                    .foregroundStyle(DesignTokens.stone900)
                                Text("\(game.type.labelZh) · \(game.playerLabel)")
                                    .font(DesignTokens.bodyFont(size: 11, weight: .semibold))
                                    .foregroundStyle(DesignTokens.stone500)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(DesignTokens.stone400)
                        }
                        .padding(12)
                        .background(DesignTokens.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            } else {
                Text("输入管理密码后可查看和管理游戏卡片。")
                    .font(DesignTokens.bodyFont(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.stone500)

                SecureField("请输入管理密码", text: $adminPasswordInput)
                    .font(DesignTokens.bodyFont(size: 15, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(DesignTokens.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if !adminError.isEmpty {
                    Text(adminError)
                        .font(DesignTokens.bodyFont(size: 12))
                        .foregroundStyle(.red)
                }

                Button {
                    if adminPasswordInput == adminPassword {
                        adminUnlocked = true
                        adminPasswordInput = ""
                        adminError = ""
                    } else {
                        adminError = "密码错误，请重试"
                    }
                } label: {
                    Text("进入管理者模式")
                        .font(DesignTokens.bodyFont(size: 14))
                        .foregroundStyle(DesignTokens.inverseText)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background(DesignTokens.inverseSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.hapticPlain)

                Text("默认密码：888888")
                    .font(DesignTokens.bodyFont(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.stone400)
            }
        }
        .padding(16)
        .background(DesignTokens.surfaceElevatedSoft)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(DesignTokens.borderSubtle, lineWidth: 1)
        }
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

    private func panelMenuCard(
        title: String,
        subtitle: String,
        icon: String,
        tone: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(tone)
                    .frame(width: 48, height: 48)
                    .background(tone.opacity(0.12))
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
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DesignTokens.stone400)
            }
            .padding(15)
            .background(DesignTokens.surfaceElevatedSoft)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(DesignTokens.borderSubtle, lineWidth: 1)
            }
        }
        .buttonStyle(.hapticPlain)
    }

    private func favoriteCard(_ game: Game) -> some View {
        Button {
            viewModel.selectGame(game)
            viewModel.openDetail(game)
            viewModel.closeMyPanel()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    if let image = viewModel.gameImage(for: game.id) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Text(game.type.emoji)
                            .font(.system(size: 27))
                    }
                }
                .frame(width: 58, height: 58)
                .background(DesignTokens.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(game.name)
                        .font(DesignTokens.titleFont(size: 17))
                        .foregroundStyle(DesignTokens.stone900)
                    Text("\(game.type.labelZh) · \(game.playerLabel)")
                        .font(DesignTokens.bodyFont(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.stone500)
                }
                Spacer()
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
            }
            .padding(12)
            .background(DesignTokens.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.hapticPlain)
    }
}
