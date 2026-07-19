import SwiftUI
import UIKit

enum PartyGamesResourceImage {
    static func uiImage(_ name: String) -> UIImage? {
        // 1) App 主包 Assets（PartyGamesApp/Assets.xcassets）
        if let image = UIImage(named: name) {
            return image
        }
        // 2) SPM Resources 兜底（优先高清 PNG）
        for ext in ["png", "jpg", "jpeg"] {
            if let url = Bundle.module.url(forResource: name, withExtension: ext),
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                return image
            }
        }
        return nil
    }

    static func image(_ name: String) -> Image {
        if let uiImage = uiImage(name) {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "photo")
    }
}
