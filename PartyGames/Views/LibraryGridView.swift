import SwiftUI

struct LibraryGridView: View {
    @Bindable var viewModel: HomeViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(viewModel.filteredGames.enumerated()), id: \.element.id) { index, game in
                    LibraryGameCard(
                        game: game,
                        palette: GameHeaderPalettes.palette(forGameIndex: index),
                        image: viewModel.gameImages[game.id],
                        isFavorite: viewModel.isFavorite(game.id),
                        onToggleFavorite: { viewModel.toggleFavorite(game.id) },
                        onTap: { viewModel.openDetail(game) }
                    )
                }
            }
            .padding(.horizontal, DesignTokens.pageHorizontalPadding)
            .padding(.vertical, 12)
        }
        .creamBackground()
        .navigationTitle("游戏库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.filterSheetOpen = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
            }
        }
        .sheet(isPresented: $viewModel.filterSheetOpen) {
            FilterSheet(viewModel: viewModel)
        }
        .navigationDestination(item: $viewModel.detailGame) { game in
            GameDetailView(game: game, viewModel: viewModel)
                .toolbar(.hidden, for: .tabBar)
        }
    }
}

private struct LibraryGameCard: View {
    let game: Game
    let palette: GameHeaderPalette
    var image: UIImage?
    var isFavorite: Bool
    var onToggleFavorite: () -> Void
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(game.type.labelZh)
                        .font(DesignTokens.bodyFont(size: 10))
                        .foregroundStyle(palette.badgeText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(palette.badge)
                        .clipShape(Capsule())
                    Spacer()
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(isFavorite ? .pink : palette.title.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                ZStack {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        palette.backgroundGradient
                        Text(game.type.emoji)
                            .font(.system(size: 28))
                    }
                }
                .frame(height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(game.name)
                    .font(DesignTokens.titleFont(size: 16))
                    .foregroundStyle(palette.title)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(game.playerLabel)
                    .font(DesignTokens.bodyFont(size: 11))
                    .foregroundStyle(DesignTokens.stone500)
            }
            .padding(12)
            .background(palette.backgroundGradient)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
