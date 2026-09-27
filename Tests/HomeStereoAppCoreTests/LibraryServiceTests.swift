import AVFoundation
import Foundation
import XCTest
@testable import HomeStereoAppCore

final class LibraryServiceTests: XCTestCase {
    func testSupportedExtensionsAreCaseInsensitive() {
        for name in ["a.m4a", "a.MP3", "a.aac", "a.wav", "a.AIFF", "a.flac"] {
            XCTAssertTrue(LibraryService.supports(URL(fileURLWithPath: name)), name)
        }
        XCTAssertFalse(LibraryService.supports(URL(fileURLWithPath: "a.ogg")))
        XCTAssertFalse(LibraryService.supports(URL(fileURLWithPath: "a.txt")))
    }

    func testUnchangedLargeScanThrottlesProgressCallbacks() async throws {
        let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }
        let folder = LibraryFolder(displayName: "Fixture", path: folderURL.path)
        var existing: [Track] = []
        for index in 0..<250 {
            let name = String(format: "track-%03d.mp3", index)
            let url = folderURL.appendingPathComponent(name)
            try Data().write(to: url)
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            existing.append(Track(
                libraryFolderID: folder.id, relativePath: name, url: url,
                fileSize: 0, modificationDate: values.contentModificationDate ?? .distantPast,
                title: name
            ))
        }
        let callbackCount = CallbackCount()

        let result = try await LibraryService().scan(
            folder: folder, resolvedURL: folderURL, existingTracks: existing
        ) { _ in
            await callbackCount.increment()
        }

        XCTAssertEqual(result.progress.analyzed, 250)
        XCTAssertEqual(result.progress.unchanged, 250)
        let reportedProgressCount = await callbackCount.value
        XCTAssertLessThan(reportedProgressCount, 50)
    }

    func testTrackCarriesArtworkData() {
        let artwork = Data([0x01, 0x02, 0x03])
        let track = Track(
            url: URL(fileURLWithPath: "/tmp/artwork.m4a"),
            title: "Artwork",
            artworkData: artwork
        )

        XCTAssertEqual(track.artworkData, artwork)
    }

    func testITunesGenreAndReleaseDateMetadataAreExtracted() async {
        let genre = AVMutableMetadataItem()
        genre.identifier = .iTunesMetadataUserGenre
        genre.value = "Classical" as NSString
        let releaseDate = AVMutableMetadataItem()
        releaseDate.identifier = .iTunesMetadataReleaseDate
        releaseDate.value = "2025-09-26T00:00:00Z" as NSString

        let values = await LibraryService.supplementalMetadataValues(from: [genre, releaseDate])

        XCTAssertEqual(values.genre, "Classical")
        XCTAssertEqual(values.releaseYear, 2025)
    }

    func testFLACVorbisCommentsAreExtracted() async {
        func item(_ key: String, _ value: String) -> AVMutableMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = AVMetadataIdentifier(rawValue: "vorb/\(key)")
            item.value = value as NSString
            return item
        }
        let metadata = [
            item("TITLE", "Tagged Title"), item("ARTIST", "Tagged Artist"),
            item("ALBUM", "Tagged Album"), item("ALBUMARTIST", "Tagged Album Artist"),
            item("GENRE", "Jazz"), item("DATE", "2024-02-03"),
            item("COMPOSER", "Tagged Composer"), item("TRACKNUMBER", "2/10"),
            item("DISCNUMBER", "1/2"),
        ]

        let values = await LibraryService.metadataValues(from: metadata)

        XCTAssertEqual(values.title, "Tagged Title")
        XCTAssertEqual(values.artist, "Tagged Artist")
        XCTAssertEqual(values.album, "Tagged Album")
        XCTAssertEqual(values.albumArtist, "Tagged Album Artist")
        XCTAssertEqual(values.genre, "Jazz")
        XCTAssertEqual(values.releaseYear, 2024)
        XCTAssertEqual(values.composer, "Tagged Composer")
        XCTAssertEqual(values.trackNumber, 2)
        XCTAssertEqual(values.trackTotal, 10)
        XCTAssertEqual(values.discNumber, 1)
        XCTAssertEqual(values.discTotal, 2)
    }

    func testScanReadsFLACVorbisComments() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let encoded = "ZkxhQwAAACICQAJAAAAMAAAMAfQA8AAAAFDLQV4FuFvjFJSuG8IzvrWLhAAA+A0AAABMYXZmNjIuMTIuMTAyCgAAABIAAABUSVRMRT1UYWdnZWQgVGl0bGUUAAAAQVJUSVNUPVRhZ2dlZCBBcnRpc3QSAAAAQUxCVU09VGFnZ2VkIEFsYnVtHwAAAEFMQlVNQVJUSVNUPVRhZ2dlZCBBbGJ1bSBBcnRpc3QKAAAAR0VOUkU9SmF6eg8AAABEQVRFPTIwMjQtMDItMDMYAAAAQ09NUE9TRVI9VGFnZ2VkIENvbXBvc2VyEAAAAFRSQUNLTlVNQkVSPTIvMTAOAAAARElTQ05VTUJFUj0xLzIVAAAAZW5jb2Rlcj1MYXZmNjIuMTIuMTAy//hkCABPCQAAAHyn"
        let url = folder.appendingPathComponent("tagged.flac")
        try XCTUnwrap(Data(base64Encoded: encoded)).write(to: url)

        let tracks = try await LibraryService().scan(folder: folder)
        let track = try XCTUnwrap(tracks.first)

        XCTAssertEqual(track.title, "Tagged Title")
        XCTAssertEqual(track.artist, "Tagged Artist")
        XCTAssertEqual(track.album, "Tagged Album")
        XCTAssertEqual(track.albumArtist, "Tagged Album Artist")
        XCTAssertEqual(track.genre, "Jazz")
        XCTAssertEqual(track.releaseYear, 2024)
        XCTAssertEqual(track.composer, "Tagged Composer")
        XCTAssertEqual(track.trackNumber, 2)
        XCTAssertEqual(track.trackTotal, 10)
        XCTAssertEqual(track.discNumber, 1)
        XCTAssertEqual(track.discTotal, 2)
    }

    func testScanFindsPlayableAudioAndSkipsUnreadableCandidates() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let playable = folder.appendingPathComponent("tone.wav")
        try makeSilentWAV(duration: 1).write(to: playable)
        try Data("not audio".utf8).write(to: folder.appendingPathComponent("broken.mp3"))
        try Data("ignore".utf8).write(to: folder.appendingPathComponent("notes.txt"))

        let tracks = try await LibraryService().scan(folder: folder)

        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks.first?.title, "tone")
        XCTAssertEqual(tracks.first?.url, playable)
        XCTAssertGreaterThan(tracks.first?.duration ?? 0, 0.9)
        XCTAssertEqual(tracks.first?.sampleRate, 8_000)
        XCTAssertGreaterThan(tracks.first?.bitRate ?? 0, 0)
    }

    func testIdentityResolverRejectsSameSizeDifferentSongAndAmbiguousMetadata() {
        let folder = UUID()
        func track(id: UUID = UUID(), path: String, title: String, resource: Data? = nil) -> Track {
            Track(
                id: id, libraryFolderID: folder, relativePath: path,
                url: URL(fileURLWithPath: "/tmp/\(path)"), fileSize: 10_000,
                fileResourceIdentifier: resource, title: title, artist: "Artist", albumArtist: "Artist",
                album: "Album", duration: 180, codec: "lpcm", sampleRate: 44_100,
                bitDepth: 16, channelCount: 2
            )
        }

        let candidate = track(path: "new.wav", title: "Song")
        let different = track(path: "old.wav", title: "Different")
        XCTAssertEqual(TrackIdentityResolver.match(candidate, among: [different]), .none)

        let sameA = track(path: "a.wav", title: "Song")
        let sameB = track(path: "b.wav", title: "Song")
        XCTAssertEqual(
            TrackIdentityResolver.match(candidate, among: [sameA, sameB]),
            .ambiguous(candidateCount: 2, reason: .conservativeMetadata)
        )

        let resourceCandidate = track(path: "resource-new.wav", title: "Changed", resource: Data([1, 2, 3]))
        let resourceExisting = track(path: "resource-old.wav", title: "Old", resource: Data([1, 2, 3]))
        XCTAssertEqual(
            TrackIdentityResolver.match(resourceCandidate, among: [resourceExisting]),
            .matched(trackID: resourceExisting.id, reason: .fileResourceIdentifier)
        )
    }

    private func makeSilentWAV(duration: Int) -> Data {
        let sampleRate: UInt32 = 8_000
        let dataSize = sampleRate * UInt32(duration) * 2
        var data = Data()
        data.appendASCII("RIFF")
        data.appendLE(UInt32(36) + dataSize)
        data.appendASCII("WAVEfmt ")
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(UInt16(1))
        data.appendLE(sampleRate)
        data.appendLE(sampleRate * 2)
        data.appendLE(UInt16(2))
        data.appendLE(UInt16(16))
        data.appendASCII("data")
        data.appendLE(dataSize)
        data.append(Data(repeating: 0, count: Int(dataSize)))
        return data
    }
}

private actor CallbackCount {
    private(set) var value = 0
    func increment() { value += 1 }
}

private extension Data {
    mutating func appendASCII(_ value: String) { append(value.data(using: .ascii)!) }

    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
