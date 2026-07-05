import SwiftUI

struct GameDetailView: View {
    let game: Game
    @Bindable var viewModel: HomeViewModel
    @StateObject private var speechService = SpeechService()
    @Environment(\.dismiss) private var dismiss

    private var palette: GameHeaderPalette {
        GameHeaderPalettes.palette(forGameID: game.id, in: viewModel.games)
    }

    private var image: UIImage? {
        viewModel.gameImages[game.id] ?? AssetStore.bundledImage(for: game.id)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                heroCard
                if let preparation = game.preparation, !preparation.isEmpty {
                    preparationSection(preparation)
                }
                rulesSection
            }
            .padding(.horizontal, DesignTokens.pageHorizontalPadding)
            .padding(.bottom, 28)
        }
        .creamBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    speechService.stop()
                    viewModel.closeDetail()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                }
            }
        }
        .onDisappear {
            speechService.stop()
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(game.type.labelZh)
                    .font(DesignTokens.bodyFont(size: 11))
                    .foregroundStyle(palette.badgeText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(palette.badge)
                    .clipShape(Capsule())
                Spacer()
                Button {
                    viewModel.toggleFavorite(game.id)
                } label: {
                    Image(systemName: viewModel.isFavorite(game.id) ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(viewModel.isFavorite(game.id) ? .pink : palette.title.opacity(0.55))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(game.name)
                        .font(DesignTokens.titleFont(size: 26))
                        .foregroundStyle(palette.title)
                    if let intro = game.detailIntro?.trimmingCharacters(in: .whitespaces), !intro.isEmpty {
                        Text(intro)
                            .font(DesignTokens.bodyFont(size: 13, weight: .semibold))
                            .foregroundStyle(DesignTokens.stone600.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    FlowTagsRow(game: game, palette: palette)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        palette.backgroundGradient
                        Text(game.type.emoji)
                            .font(.system(size: 36))
                    }
                }
                .frame(width: 108, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                }
            }
        }
        .padding(18)
        .background(palette.backgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
    }

    private func preparationSection(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("开始前准备")
                .font(DesignTokens.titleFont(size: 20))
                .foregroundStyle(DesignTokens.stone900)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(DesignTokens.bodyFont(size: 11))
                        .foregroundStyle(Color.orange)
                        .frame(width: 24, height: 24)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Circle())
                    Text(item)
                        .font(DesignTokens.bodyFont(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.stone600)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("游戏规则")
                    .font(DesignTokens.titleFont(size: 20))
                    .foregroundStyle(DesignTokens.stone900)
                Spacer()
                Button {
                    toggleVoice()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: speechService.isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(speechService.isPlaying ? "结束" : (game.startButtonLabel ?? "开始游戏"))
                            .font(DesignTokens.bodyFont(size: 13))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(DesignTokens.stone900)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            ForEach(Array(game.rules.enumerated()), id: \.offset) { index, rule in
                let highlighted = speechService.currentSentenceIndex > 0
                    && speechService.currentSentenceIndex - 1 == index
                Text("\(index + 1). \(rule)")
                    .font(DesignTokens.bodyFont(size: 15, weight: .bold))
                    .foregroundStyle(highlighted ? .white : DesignTokens.stone600)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(highlighted ? DesignTokens.stone900 : Color.white.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(highlighted ? 0.12 : 0.04), radius: highlighted ? 8 : 4, y: 2)
                    .animation(.easeInOut(duration: 0.2), value: speechService.currentSentenceIndex)
            }
        }
    }

    private func toggleVoice() {
        if speechService.isPlaying {
            speechService.stop()
        } else {
            speechService.speak(game: game)
        }
    }
}

private struct FlowTagsRow: View {
    let game: Game
    let palette: GameHeaderPalette

    var body: some View {
        FlowLayout(spacing: 6) {
            tag(game.playerLabel, strong: true)
            ForEach(game.tags, id: \.self) { gameTag in
                tag(GameTag.label(for: gameTag), strong: false)
            }
        }
    }

    private func tag(_ text: String, strong: Bool) -> some View {
        Text(text)
            .font(DesignTokens.bodyFont(size: 10))
            .foregroundStyle(strong ? palette.tagText : palette.tagTextMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(strong ? palette.tagBg : palette.tagBgMuted)
            .clipShape(Capsule())
    }
}

/// Simple horizontal wrapping layout for hero tags.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
