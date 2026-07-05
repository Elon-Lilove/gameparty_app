import SwiftUI

struct FilterSheet: View {
    @Bindable var viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("人数") {
                    Picker("玩家人数", selection: Binding(
                        get: { viewModel.playerCountFilter ?? 0 },
                        set: { viewModel.setPlayerCountFilter($0 == 0 ? nil : $0) }
                    )) {
                        Text("不限").tag(0)
                        Text("2人").tag(2)
                        Text("3-4人").tag(4)
                        Text("5人以上").tag(6)
                    }
                    .pickerStyle(.inline)
                }

                Section("类型") {
                    Picker("游戏类型", selection: Binding(
                        get: { viewModel.typeFilter },
                        set: { viewModel.setTypeFilter($0) }
                    )) {
                        Text("全部").tag(GameType?.none)
                        ForEach(GameType.allCases, id: \.self) { type in
                            Text("\(type.emoji) \(type.labelZh)").tag(GameType?.some(type))
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
