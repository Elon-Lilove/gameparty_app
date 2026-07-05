import SwiftUI

struct MoodFilterBar: View {
    @Binding var selection: MoodCategory
    var onChange: (MoodCategory) -> Void

    private let options: [MoodCategory] = [.funny, .flirty, .brain, .icebreaker, .all]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { mood in
                    Button {
                        selection = mood
                        onChange(mood)
                    } label: {
                        HStack(spacing: 5) {
                            Text(mood.emoji)
                            Text(mood.label)
                                .font(DesignTokens.bodyFont(size: 13))
                        }
                        .foregroundStyle(selection == mood ? DesignTokens.stone900 : DesignTokens.stone500)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(selection == mood ? DesignTokens.moodActiveBackground : .white)
                        .overlay {
                            Capsule()
                                .stroke(selection == mood ? DesignTokens.moodActiveBorder : Color.clear, lineWidth: 1.5)
                        }
                        .clipShape(Capsule())
                        .shadow(
                            color: selection == mood ? DesignTokens.brandYellow.opacity(0.18) : .black.opacity(0.06),
                            radius: selection == mood ? 0 : 6,
                            y: selection == mood ? 0 : 4
                        )
                        .overlay {
                            if selection == mood {
                                Capsule()
                                    .stroke(DesignTokens.brandYellow.opacity(0.16), lineWidth: 3)
                                    .padding(-3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignTokens.pageHorizontalPadding)
        }
    }
}
