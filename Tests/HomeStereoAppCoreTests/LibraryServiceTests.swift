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
