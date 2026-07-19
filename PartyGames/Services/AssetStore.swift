import Foundation
import ImageIO
import UIKit

enum AssetStore {
    private static let imagesKey = "game-images"
    private static let bundledImageName = "true-or-false-home"
    private static let defaultGameID = "true_or_false"
    private static let cardImageMaxPixelSize: CGFloat = 900

    private nonisolated(unsafe) static let memoryCache = NSCache<NSString, UIImage>()
    private nonisolated(unsafe) static var cachedPathsSnapshot: [String: String]?
    private nonisolated(unsafe) static var bundledImageURL: URL?

    static func image(for gameId: String, cache: [String: UIImage]) -> UIImage? {
        cache[gameId] ?? cachedImage(for: gameId)
    }

    static func cachedImage(for gameId: String) -> UIImage? {
        if let cached = memoryCache.object(forKey: gameId as NSString) {
            return cached
        }
        guard let image = loadImageFromDisk(for: gameId) else { return nil }
        memoryCache.setObject(image, forKey: gameId as NSString)
        return image
    }

    static func loadImages(for gameIds: [String]) -> [String: UIImage] {
        var images: [String: UIImage] = [:]
        images.reserveCapacity(gameIds.count)
        for gameId in gameIds {
            if let image = loadImageFromDisk(for: gameId) {
                memoryCache.setObject(image, forKey: gameId as NSString)
                images[gameId] = image
            }
        }
        return images
    }

    static func bundledImage(for gameId: String) -> UIImage? {
        cachedImage(for: gameId)
    }

    static func saveImage(_ image: UIImage, for gameId: String) {
        guard let data = image.jpegData(compressionQuality: 0.88) else { return }
        let url = cacheDirectory().appendingPathComponent("\(gameId).jpg")
        try? data.write(to: url, options: .atomic)
        var paths = cachedPaths()
        paths[gameId] = url.path
        storeCachedPaths(paths)
        memoryCache.setObject(image, forKey: gameId as NSString)
    }

    private static func loadImageFromDisk(for gameId: String) -> UIImage? {
        if gameId == defaultGameID {
            if bundledImageURL == nil {
                bundledImageURL = Bundle.module.url(forResource: bundledImageName, withExtension: "jpg")
            }
            guard let url = bundledImageURL else { return nil }
            return downsampledImage(at: url, maxPixelSize: cardImageMaxPixelSize)
        }

        guard let path = cachedPaths()[gameId] else { return nil }
        return downsampledImage(at: URL(fileURLWithPath: path), maxPixelSize: cardImageMaxPixelSize)
    }

    private static func downsampledImage(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private static func cachedPaths() -> [String: String] {
        if let cachedPathsSnapshot {
            return cachedPathsSnapshot
        }
        guard let data = UserDefaults.standard.data(forKey: imagesKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            cachedPathsSnapshot = [:]
            return [:]
        }
        cachedPathsSnapshot = decoded
        return decoded
    }

    private static func storeCachedPaths(_ paths: [String: String]) {
        cachedPathsSnapshot = paths
        guard let data = try? JSONEncoder().encode(paths) else { return }
        UserDefaults.standard.set(data, forKey: imagesKey)
    }

    private static func cacheDirectory() -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("party-game-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
