import SwiftUI

struct ScorekeeperView: View {
    @State private var players: [ScorePlayer] = ScoreStore.load()

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                Text("轻点加减号记录得分，适合酒桌或桌游计分。")
                    .font(DesignTokens.bodyFont(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.stone500)
                Spacer(minLength: 8)
                Button("清零", action: resetScores)
                    .font(DesignTokens.bodyFont(size: 11))
                    .foregroundStyle(DesignTokens.stone600)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(white: 0.94))
                    .clipShape(Capsule())
            }

            ForEach($players) { $player in
                playerRow(player: $player)
            }

            Button(action: addPlayer) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("添加玩家")
                }
                .font(DesignTokens.bodyFont(size: 13))
                .foregroundStyle(DesignTokens.stone600)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.7))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        .foregroundStyle(DesignTokens.stone400.opacity(0.5))
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(players.count >= 8)
            .opacity(players.count >= 8 ? 0.45 : 1)
        }
    }

    private func playerRow(player: Binding<ScorePlayer>) -> some View {
        HStack(spacing: 10) {
            TextField("玩家名", text: player.name)
                .font(DesignTokens.bodyFont(size: 15))
                .foregroundStyle(DesignTokens.stone900)
                .onChange(of: player.wrappedValue.name) { _, _ in
                    savePlayers()
                }

            HStack(spacing: 8) {
                scoreButton(systemName: "minus", filled: false) {
                    adjustScore(id: player.wrappedValue.id, delta: -1)
                }
                Text("\(player.wrappedValue.score)")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(DesignTokens.stone900)
                    .frame(width: 36)
                    .monospacedDigit()
                scoreButton(systemName: "plus", filled: true) {
                    adjustScore(id: player.wrappedValue.id, delta: 1)
                }
            }

            if players.count > 2 {
                Button {
                    removePlayer(id: player.wrappedValue.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.pink)
                        .frame(width: 40, height: 40)
                        .background(Color.pink.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DesignTokens.stone400.opacity(0.25), lineWidth: 1)
        }
    }

    private func scoreButton(systemName: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(filled ? .white : DesignTokens.stone600)
                .frame(width: 40, height: 40)
                .background(filled ? DesignTokens.stone900 : Color(white: 0.94))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func updatePlayers(_ next: [ScorePlayer]) {
        players = next
        ScoreStore.save(next)
    }

    private func adjustScore(id: String, delta: Int) {
        updatePlayers(players.map { player in
            player.id == id ? ScorePlayer(id: player.id, name: player.name, score: player.score + delta) : player
        })
        HapticService.light()
    }

    private func addPlayer() {
        guard players.count < 8 else { return }
        let next = ScorePlayer(
            id: "p-\(Int(Date().timeIntervalSince1970 * 1000))",
            name: "玩家 \(players.count + 1)",
            score: 0
        )
        updatePlayers(players + [next])
    }

    private func removePlayer(id: String) {
        guard players.count > 2 else { return }
        updatePlayers(players.filter { $0.id != id })
    }

    private func resetScores() {
        updatePlayers(players.map { ScorePlayer(id: $0.id, name: $0.name, score: 0) })
    }

    private func savePlayers() {
        ScoreStore.save(players)
    }
}
