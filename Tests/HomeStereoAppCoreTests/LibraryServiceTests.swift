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

    func testTrackCarriesArtworkData() {
        let artwork = Data([0x01, 0x02, 0x03])
        let track = Track(
            url: URL(fileURLWithPath: "/tmp/artwork.m4a"),
            title: "Artwork",
            artworkData: artwork
        )

        XCTAssertEqual(track.artworkData, artwork)
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

private extension Data {
    mutating func appendASCII(_ value: String) { append(value.data(using: .ascii)!) }

    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
