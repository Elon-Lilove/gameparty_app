import SwiftUI

struct HistorySheet: View {
    let games: [Game]
    var onSelect: (Game) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if games.isEmpty {
                    ContentUnavailableView("暂无历史", systemImage: "clock", description: Text("随机选局后会出现在这里"))
                } else {
                    List(games) { game in
                        Button {
                            onSelect(game)
                            dismiss()
                        } label: {
                            HStack {
                                Text(game.name)
                                    .font(DesignTokens.bodyFont(size: 16))
                                Spacer()
                                Text(game.playerLabel)
                                    .font(DesignTokens.bodyFont(size: 12))
                                    .foregroundStyle(DesignTokens.stone500)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
