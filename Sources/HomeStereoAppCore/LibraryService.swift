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
            await progressHandler(progress)
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
            var title: String?, artist: String?, albumArtist: String?, album: String?, genre: String?
            var releaseYear: Int?
            var hasArtwork = false
            for item in metadata {
                switch item.commonKey {
                case .commonKeyTitle: title = try? await item.load(.stringValue)
                case .commonKeyArtist: artist = try? await item.load(.stringValue)
                case .commonKeyAlbumName: album = try? await item.load(.stringValue)
                case .commonKeyCreationDate:
                    releaseYear = Self.metadataYear(from: try? await item.load(.stringValue))
                case .commonKeyArtwork: hasArtwork = true
                default: break
                }
            }
            let supplemental = await Self.supplementalMetadataValues(from: formatMetadata)
            albumArtist = supplemental.albumArtist
            genre = supplemental.genre
            if releaseYear == nil { releaseYear = supplemental.releaseYear }
            return Track(
                id: existingID ?? UUID(), libraryFolderID: folderID, relativePath: relativePath,
                url: url, fileSize: fileSize, modificationDate: modificationDate,
                fileResourceIdentifier: fileResourceIdentifier,
                title: title?.nilIfBlank ?? url.deletingPathExtension().lastPathComponent,
                artist: artist?.nilIfBlank, albumArtist: albumArtist?.nilIfBlank,
                album: album?.nilIfBlank, genre: genre?.nilIfBlank, releaseYear: releaseYear, duration: duration,
                codec: basicDescription.map { String(format: "%08X", $0.pointee.mFormatID) },
                sampleRate: basicDescription?.pointee.mSampleRate,
                bitRate: bitRate,
                bitDepth: basicDescription.map { Int($0.pointee.mBitsPerChannel) },
                channelCount: basicDescription.map { Int($0.pointee.mChannelsPerFrame) },
                hasArtwork: hasArtwork, artworkData: nil, lastScannedAt: scannedAt
            )
        } catch { return nil }
    }

    static func supplementalMetadataValues(
        from metadata: [AVMetadataItem]
    ) async -> (albumArtist: String?, genre: String?, releaseYear: Int?) {
        var albumArtist: String?, genre: String?, releaseYear: Int?
        for item in metadata {
            let identifier = item.identifier?.rawValue.lowercased() ?? ""
            let value = try? await item.load(.stringValue)
            if albumArtist == nil,
               (item.identifier == .iTunesMetadataAlbumArtist || item.identifier == .id3MetadataBand) {
                albumArtist = value
            }
            if genre == nil,
               (item.identifier == .iTunesMetadataUserGenre
                || (identifier.contains("genre") && !identifier.contains("predefined") && !identifier.contains("genreid"))
                || identifier.contains("tcon")) {
                genre = value
            }
            if releaseYear == nil,
               (item.identifier == .iTunesMetadataReleaseDate
                || identifier.contains("releasedate") || identifier.hasSuffix("year")
                || identifier.contains("tyer") || identifier.contains("tdrc")
                || identifier.contains("tdor") || identifier.contains("©day")) {
                releaseYear = Self.metadataYear(from: value)
            }
        }
        return (albumArtist?.nilIfBlank, genre?.nilIfBlank, releaseYear)
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
