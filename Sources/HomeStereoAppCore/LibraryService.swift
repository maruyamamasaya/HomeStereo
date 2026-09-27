import AVFoundation
import Foundation

public struct LibraryService: LibraryScanning {
    public static let supportedExtensions: Set<String> = ["mp3", "m4a", "mp4", "aac", "wav", "aiff", "aif", "flac", "alac"]

    public init() {}

    public static func supports(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    public static func normalizedRelativePath(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased()
    }

    public func scan(folder: URL) async throws -> [Track] {
        let model = LibraryFolder(displayName: folder.lastPathComponent, path: folder.path)
        return try await scan(folder: model, resolvedURL: folder, existingTracks: []) { _ in }.tracks
            .filter { $0.scanState == .available }
    }

    public func scan(
        folder: LibraryFolder,
        resolvedURL: URL,
        existingTracks: [Track],
        progress progressHandler: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> LibraryScanResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw UserFacingError.folderUnavailable
        }

        let candidates = try candidateFiles(in: resolvedURL)
        let candidateKeys = Set(candidates.map { Self.normalizedRelativePath($0.relativePath) })
        let existing = Dictionary(uniqueKeysWithValues: existingTracks.map {
            (Self.normalizedRelativePath($0.relativePath), $0)
        })
        let relocationCandidates = existingTracks.filter {
            !candidateKeys.contains(Self.normalizedRelativePath($0.relativePath))
        }
        let now = Date()
        var progress = ScanProgress()
        progress.discovered = candidates.count
        await progressHandler(progress)
        var notices: [ScanNotice] = []
        var scanned: [Track] = []
        var discoveredKeys = Set<String>()
        var matchedExistingIDs = Set<Track.ID>()
        var lastProgressUpdate = ContinuousClock.now

        for candidate in candidates.sorted(by: { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }) {
            try Task.checkCancellation()
            let key = Self.normalizedRelativePath(candidate.relativePath)
            discoveredKeys.insert(key)
            progress.currentRelativePath = candidate.relativePath
            let previous = existing[key]
            if let previous { matchedExistingIDs.insert(previous.id) }
            if let previous,
               previous.fileSize == candidate.fileSize,
               abs(previous.modificationDate.timeIntervalSince(candidate.modificationDate)) < 0.001,
               previous.metadataSchemaVersion == Track.metadataVersion,
               previous.scanState != .unreadable {
                scanned.append(previous.replacingURL(
                    candidate.url,
                    fileResourceIdentifier: candidate.fileResourceIdentifier,
                    scanState: .available,
                    scannedAt: previous.scanState == .available ? previous.lastScannedAt : now
                ))
                progress.unchanged += 1
            } else if var metadata = await metadata(
                for: candidate.url,
                folderID: folder.id,
                relativePath: candidate.relativePath,
                fileSize: candidate.fileSize,
                modificationDate: candidate.modificationDate,
                fileResourceIdentifier: candidate.fileResourceIdentifier,
                existingID: previous?.id,
                scannedAt: now
            ) {
                if isStable(candidate) {
                    if previous == nil {
                        let unmatched = relocationCandidates.filter { !matchedExistingIDs.contains($0.id) }
                        switch TrackIdentityResolver.match(metadata, among: unmatched) {
                        case let .matched(trackID, reason):
                            metadata = metadata.replacingIdentity(
                                id: trackID, relativePath: candidate.relativePath, url: candidate.url, scannedAt: now
                            )
                            matchedExistingIDs.insert(trackID)
                            notices.append(ScanNotice(
                                relativePath: candidate.relativePath,
                                message: "Track IDを維持しました（\(reason.rawValue)一致）。"
                            ))
                        case let .ambiguous(count, reason):
                            notices.append(ScanNotice(
                                relativePath: candidate.relativePath,
                                message: "移動候補が\(count)件あり曖昧なため別Trackとして登録します（\(reason.rawValue)）。"
                            ))
                        case .none:
                            break
                        }
                    }
                    scanned.append(metadata)
                    if previous == nil, !matchedExistingIDs.contains(metadata.id) { progress.added += 1 }
                    else { progress.updated += 1 }
                } else {
                    progress.failed += 1
                    notices.append(ScanNotice(relativePath: candidate.relativePath, message: "コピーまたは更新中のため次回scanまで保留します。"))
                    if let previous { scanned.append(previous) }
                }
            } else {
                progress.failed += 1
                notices.append(ScanNotice(relativePath: candidate.relativePath, message: "音声metadataを読み取れませんでした。"))
                if let previous {
                    scanned.append(previous.replacingURL(candidate.url, scanState: .unreadable, scannedAt: now))
                }
            }
            progress.analyzed += 1
            let progressUpdate = ContinuousClock.now
            if progress.analyzed.isMultiple(of: 100)
                || lastProgressUpdate.duration(to: progressUpdate) >= .milliseconds(250) {
                await progressHandler(progress)
                lastProgressUpdate = progressUpdate
            }
        }

        for previous in existingTracks where
            !discoveredKeys.contains(Self.normalizedRelativePath(previous.relativePath))
            && !matchedExistingIDs.contains(previous.id) {
            scanned.append(previous.replacingURL(previous.url, scanState: .missing, scannedAt: now))
            progress.missing += 1
        }
        progress.currentRelativePath = nil
        await progressHandler(progress)
        return LibraryScanResult(tracks: scanned, progress: progress, notices: notices)
    }

    private struct Candidate: Sendable {
        let url: URL
        let relativePath: String
        let fileSize: Int64
        let modificationDate: Date
        let fileResourceIdentifier: Data?
    }

    private func candidateFiles(in root: URL) throws -> [Candidate] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isReadableKey, .isHiddenKey, .isSymbolicLinkKey,
            .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey,
        ]
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in enumerationError = error; return false }
        ) else { throw UserFacingError.folderUnavailable }

        var result: [Candidate] = []
        for case let url as URL in enumerator {
            if Task.isCancelled { throw CancellationError() }
            guard Self.supports(url), let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true, values.isHidden != true,
                  values.isReadable != false else { continue }
            let rootPath = root.standardizedFileURL.path
            let filePath = url.standardizedFileURL.path
            guard filePath.hasPrefix(rootPath + "/") else { continue }
            result.append(Candidate(
                url: url,
                relativePath: String(filePath.dropFirst(rootPath.count + 1)),
                fileSize: Int64(values.fileSize ?? 0),
                modificationDate: values.contentModificationDate ?? .distantPast,
                fileResourceIdentifier: Self.resourceIdentifierData(values.fileResourceIdentifier)
            ))
        }
        if let enumerationError { throw enumerationError }
        return result
    }

    private func isStable(_ candidate: Candidate) -> Bool {
        guard let values = try? candidate.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return false }
        return Int64(values.fileSize ?? -1) == candidate.fileSize
            && abs((values.contentModificationDate ?? .distantPast).timeIntervalSince(candidate.modificationDate)) < 0.001
    }

    private func metadata(
        for url: URL, folderID: UUID, relativePath: String, fileSize: Int64,
        modificationDate: Date, fileResourceIdentifier: Data?, existingID: UUID?, scannedAt: Date
    ) async -> Track? {
        let asset = AVURLAsset(url: url)
        do {
            guard try await asset.load(.isPlayable) else { return nil }
            let duration = try await asset.load(.duration).seconds
            let metadata = try await asset.load(.commonMetadata)
            let formats = try await asset.load(.availableMetadataFormats)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let formatDescriptions = try await audioTracks.first?.load(.formatDescriptions) ?? []
            let estimatedDataRate = try await audioTracks.first?.load(.estimatedDataRate)
            let basicDescription = formatDescriptions.first.flatMap { description in
                CMAudioFormatDescriptionGetStreamBasicDescription(description)
            }
            let loadedBitRate = Double(estimatedDataRate ?? 0)
            let pcmBitRate = basicDescription.flatMap { description -> Double? in
                let value = description.pointee.mSampleRate
                    * Double(description.pointee.mBitsPerChannel)
                    * Double(description.pointee.mChannelsPerFrame)
                return value > 0 ? value : nil
            }
            let bitRate = loadedBitRate > 0 ? loadedBitRate : pcmBitRate
            var formatMetadata: [AVMetadataItem] = []
            for format in formats { formatMetadata += (try? await asset.loadMetadata(for: format)) ?? [] }
            // FLAC/Vorbis comments are exposed through their format-specific collection on macOS,
            // while commonMetadata can be empty. Normalize both collections so every supported
            // container follows the same mapping.
            let values = await Self.metadataValues(from: metadata + formatMetadata)
            return Track(
                id: existingID ?? UUID(), libraryFolderID: folderID, relativePath: relativePath,
                url: url, fileSize: fileSize, modificationDate: modificationDate,
                fileResourceIdentifier: fileResourceIdentifier,
                title: values.title ?? url.deletingPathExtension().lastPathComponent,
                artist: values.artist, albumArtist: values.albumArtist,
                album: values.album, genre: values.genre, composer: values.composer,
                releaseYear: values.releaseYear, trackNumber: values.trackNumber, trackTotal: values.trackTotal,
                discNumber: values.discNumber, discTotal: values.discTotal, duration: duration,
                codec: basicDescription.map { String(format: "%08X", $0.pointee.mFormatID) },
                sampleRate: basicDescription?.pointee.mSampleRate,
                bitRate: bitRate,
                bitDepth: basicDescription.map { Int($0.pointee.mBitsPerChannel) },
                channelCount: basicDescription.map { Int($0.pointee.mChannelsPerFrame) },
                hasArtwork: values.hasArtwork, artworkData: nil, lastScannedAt: scannedAt
            )
        } catch { return nil }
    }

    struct MetadataValues: Equatable {
        var title: String?
        var artist: String?
        var albumArtist: String?
        var album: String?
        var genre: String?
        var composer: String?
        var releaseYear: Int?
        var trackNumber: Int?
        var trackTotal: Int?
        var discNumber: Int?
        var discTotal: Int?
        var hasArtwork = false
    }

    static func metadataValues(from metadata: [AVMetadataItem]) async -> MetadataValues {
        var result = MetadataValues()
        for item in metadata {
            if item.commonKey == .commonKeyArtwork {
                result.hasArtwork = true
                continue
            }
            let value = (try? await item.load(.stringValue))?.nilIfBlank
            let key = Self.normalizedMetadataKey(item.identifier?.rawValue)
            if result.albumArtist == nil,
               (item.identifier == .iTunesMetadataAlbumArtist || item.identifier == .id3MetadataBand) {
                result.albumArtist = value
            }
            if result.genre == nil, item.identifier == .iTunesMetadataUserGenre {
                result.genre = value
            }
            if result.releaseYear == nil, item.identifier == .iTunesMetadataReleaseDate {
                result.releaseYear = Self.metadataYear(from: value)
            }
            switch item.commonKey {
            case .commonKeyTitle where result.title == nil: result.title = value
            case .commonKeyArtist where result.artist == nil: result.artist = value
            case .commonKeyAlbumName where result.album == nil: result.album = value
            case .commonKeyCreationDate where result.releaseYear == nil:
                result.releaseYear = Self.metadataYear(from: value)
            default: break
            }

            switch key {
            case "TITLE" where result.title == nil: result.title = value
            case "ARTIST" where result.artist == nil: result.artist = value
            case "ALBUM" where result.album == nil: result.album = value
            case "ALBUMARTIST", "BAND":
                if result.albumArtist == nil { result.albumArtist = value }
            case "GENRE", "TCON":
                if result.genre == nil { result.genre = value }
            case "COMPOSER" where result.composer == nil: result.composer = value
            case "DATE", "YEAR", "RELEASEDATE", "ORIGINALDATE", "TYER", "TDRC", "TDOR", "DAY":
                if result.releaseYear == nil { result.releaseYear = Self.metadataYear(from: value) }
            case "TRACKNUMBER", "TRACK", "TRCK":
                let pair = Self.metadataNumberPair(from: value)
                if result.trackNumber == nil { result.trackNumber = pair.number }
                if result.trackTotal == nil { result.trackTotal = pair.total }
            case "TRACKTOTAL", "TOTALTRACKS":
                if result.trackTotal == nil { result.trackTotal = Self.metadataNumberPair(from: value).number }
            case "DISCNUMBER", "DISC", "TPOS":
                let pair = Self.metadataNumberPair(from: value)
                if result.discNumber == nil { result.discNumber = pair.number }
                if result.discTotal == nil { result.discTotal = pair.total }
            case "DISCTOTAL", "TOTALDISCS":
                if result.discTotal == nil { result.discTotal = Self.metadataNumberPair(from: value).number }
            case "METADATABLOCKPICTURE", "COVERART": result.hasArtwork = true
            default: break
            }
        }
        return result
    }

    static func supplementalMetadataValues(
        from metadata: [AVMetadataItem]
    ) async -> (albumArtist: String?, genre: String?, releaseYear: Int?) {
        let values = await metadataValues(from: metadata)
        return (values.albumArtist, values.genre, values.releaseYear)
    }

    private static func normalizedMetadataKey(_ identifier: String?) -> String {
        guard let identifier else { return "" }
        let leaf = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return String(leaf.uppercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func metadataNumberPair(from value: String?) -> (number: Int?, total: Int?) {
        guard let value else { return (nil, nil) }
        let numbers = value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return (numbers.first, numbers.dropFirst().first)
    }

    private static func metadataYear(from value: String?) -> Int? {
        guard let value else { return nil }
        let parts = value.split(whereSeparator: { !$0.isNumber })
        for part in parts where part.count >= 4 {
            guard let year = Int(part.prefix(4)), (1_000...2_999).contains(year) else { continue }
            return year
        }
        return nil
    }

    private static func resourceIdentifierData(_ value: Any?) -> Data? {
        if let data = value as? Data { return data }
        if let data = value as? NSData { return data as Data }
        if let number = value as? NSNumber { return Data(number.stringValue.utf8) }
        return nil
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
