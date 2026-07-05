import Foundation
import UIKit

enum AssetStore {
    private static let imagesKey = "game-images"
    private static let bundledImageName = "true-or-false-home"
    private static let defaultGameID = "true_or_false"

    static func loadImages() -> [String: UIImage] {
        var images: [String: UIImage] = [:]
        if let bundled = bundledImage(for: defaultGameID) {
            images[defaultGameID] = bundled
        }
        let cached = loadCachedPaths()
        for (gameId, path) in cached {
            if let image = UIImage(contentsOfFile: path) {
                images[gameId] = image
            }
        }
        return images
    }

    static func bundledImage(for gameId: String) -> UIImage? {
        guard gameId == defaultGameID,
              let url = Bundle.module.url(forResource: bundledImageName, withExtension: "jpg"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }

    static func image(for gameId: String, cache: [String: UIImage]) -> UIImage? {
        cache[gameId] ?? bundledImage(for: gameId)
    }

    static func saveImage(_ image: UIImage, for gameId: String) {
        guard let data = image.jpegData(compressionQuality: 0.88) else { return }
        let url = cacheDirectory().appendingPathComponent("\(gameId).jpg")
        try? data.write(to: url, options: .atomic)
        var paths = loadCachedPaths()
        paths[gameId] = url.path
        saveCachedPaths(paths)
    }

    private static func cacheDirectory() -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("party-game-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func loadCachedPaths() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: imagesKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveCachedPaths(_ paths: [String: String]) {
        guard let data = try? JSONEncoder().encode(paths) else { return }
        UserDefaults.standard.set(data, forKey: imagesKey)
    }
}
