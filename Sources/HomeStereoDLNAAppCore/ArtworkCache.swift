import AVFoundation
import Foundation
import ImageIO
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif

public actor ArtworkCache {
    private let cache = NSCache<NSString, NSData>()
    private let maximumSourceBytes: Int

    public init(
        countLimit: Int = 48,
        totalCostLimit: Int = 24 * 1_024 * 1_024,
        maximumSourceBytes: Int = 32 * 1_024 * 1_024
    ) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
        self.maximumSourceBytes = maximumSourceBytes
    }

    public func data(for track: Track, fileURL: URL, pixelSize: Int = 256) async -> Data? {
        let key = "\(track.id.uuidString)-\(pixelSize)" as NSString
        if let cached = cache.object(forKey: key) { return cached as Data }
        if let embedded = track.artworkData {
            return storeReduced(embedded, key: key, pixelSize: pixelSize)
        }
        let asset = AVURLAsset(url: fileURL)
        guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
        for item in metadata where item.commonKey == .commonKeyArtwork {
            if let data = try? await item.load(.dataValue) {
                return storeReduced(data, key: key, pixelSize: pixelSize)
            }
        }
        return nil
    }

    public func removeAll() { cache.removeAllObjects() }

    private func storeReduced(_ source: Data, key: NSString, pixelSize: Int) -> Data? {
        guard !Task.isCancelled, source.count <= maximumSourceBytes,
              let reduced = Self.downsample(source, pixelSize: pixelSize) else { return nil }
        cache.setObject(reduced as NSData, forKey: key, cost: reduced.count)
        return reduced
    }

    private nonisolated static func downsample(_ data: Data, pixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(32, pixelSize)
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
