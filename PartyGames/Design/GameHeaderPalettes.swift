import SwiftUI

/// Header palette for game cards — ported from `gameHeaderPalettes.ts`.
struct GameHeaderPalette: Equatable, Sendable {
    let backgroundTop: Color
    let backgroundBottom: Color
    let badge: Color
    let badgeText: Color
    let title: Color
    let tagBg: Color
    let tagText: Color
    let tagBgMuted: Color
    let tagTextMuted: Color

    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

enum GameHeaderPalettes {
    private struct Seed {
        let hue: Double
        var warmTitle: Bool = false
    }

    private static let referenceSeeds: [Seed] = [
        Seed(hue: 265),
        Seed(hue: 42, warmTitle: true),
        Seed(hue: 152),
        Seed(hue: 345),
        Seed(hue: 208),
        Seed(hue: 228),
    ]

    private static let goldenAngle = 137.508

    static let all: [GameHeaderPalette] = createPalettes()
    static let count: Int = all.count

    static func palette(forGameIndex index: Int) -> GameHeaderPalette {
        let safe = index >= 0 ? index : 0
        return all[safe % all.count]
    }

    static func palette(forGameID id: String, in games: [Game]) -> GameHeaderPalette {
        let index = games.firstIndex { $0.id == id } ?? 0
        return palette(forGameIndex: index)
    }

    private static func createPalettes() -> [GameHeaderPalette] {
        var palettes = referenceSeeds.map { buildPalette(from: $0) }
        var i = referenceSeeds.count
        while i < 100 {
            let hue = Double((Int((Double(i) * goldenAngle).truncatingRemainder(dividingBy: 360))))
            let warmTitle = hue >= 30 && hue <= 58
            palettes.append(buildPalette(from: Seed(hue: hue, warmTitle: warmTitle)))
            i += 1
        }
        return palettes
    }

    private static func buildPalette(from seed: Seed) -> GameHeaderPalette {
        let hue = seed.hue
        let title = seed.warmTitle
            ? Color(hue: 28 / 360, saturation: 0.42, brightness: 0.28)
            : Color(hue: hue / 360, saturation: 0.46, brightness: 0.22)

        return GameHeaderPalette(
            backgroundTop: Color(hue: hue / 360, saturation: 0.30, brightness: 0.945),
            backgroundBottom: Color(hue: hue / 360, saturation: 0.34, brightness: 0.895),
            badge: Color(hue: hue / 360, saturation: 0.60, brightness: 0.50),
            badgeText: .white,
            title: title,
            tagBg: Color(hue: hue / 360, saturation: 0.32, brightness: 0.84),
            tagText: Color(hue: hue / 360, saturation: 0.40, brightness: 0.28),
            tagBgMuted: Color(hue: hue / 360, saturation: 0.28, brightness: 0.865),
            tagTextMuted: Color(hue: hue / 360, saturation: 0.34, brightness: 0.34)
        )
    }
}
