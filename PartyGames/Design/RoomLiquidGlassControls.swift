import SwiftUI

struct RoomGlassButton<Label: View>: View {
    let action: () -> Void
    let prominent: Bool
    @ViewBuilder let label: () -> Label

    init(prominent: Bool = false, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.prominent = prominent
        self.label = label
    }

    var body: some View {
        if prominent {
            Button {
                HapticService.light()
                action()
            } label: {
                label()
            }
            .buttonStyle(.glassProminent)
        } else {
            Button {
                HapticService.light()
                action()
            } label: {
                label()
            }
            .buttonStyle(.glass)
        }
    }
}

struct RoomGlassToggle: View {
    let title: String
    let systemName: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: systemName)
                .font(DesignTokens.bodyFont(size: 13, weight: .semibold))
        }
        .toggleStyle(.switch)
        .glassEffect(.regular.interactive(), in: .capsule)
        .onChange(of: isOn) { _, _ in
            HapticService.selection()
        }
    }
}
