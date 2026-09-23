import AVFoundation
import Foundation

public struct LibraryService: LibraryScanning {
    public static let supportedExtensions: Set<String> = ["m4a", "mp3", "aac", "wav", "aiff", "flac"]

    public init() {}

    public static func supports(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    public func scan(folder: URL) async throws -> [Track] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw UserFacingError.folderUnavailable
        }

        let urls = try candidateURLs(in: folder)

        var tracks: [Track] = []
        for url in urls.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            if let track = await metadata(for: url) { tracks.append(track) }
        }
        return tracks
    }

    private func candidateURLs(in folder: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isReadableKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw UserFacingError.folderUnavailable
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard Self.supports(url) else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true, values?.isReadable != false { urls.append(url) }
        }
        return urls
    }

    private func metadata(for url: URL) async -> Track? {
        let asset = AVURLAsset(url: url)
        do {
            let playable = try await asset.load(.isPlayable)
            guard playable else { return nil }
            let duration = try await asset.load(.duration).seconds
            let metadata = try await asset.load(.commonMetadata)
            var title: String?
            var artist: String?
            var album: String?
            for item in metadata {
                guard let key = item.commonKey, let value = try? await item.load(.stringValue) else { continue }
                switch key {
                case .commonKeyTitle: title = value
                case .commonKeyArtist: artist = value
                case .commonKeyAlbumName: album = value
                default: break
                }
            }
            return Track(
                url: url,
                title: title?.nilIfBlank ?? url.deletingPathExtension().lastPathComponent,
                artist: artist?.nilIfBlank,
                album: album?.nilIfBlank,
                duration: duration
            )
        } catch {
            return nil
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
