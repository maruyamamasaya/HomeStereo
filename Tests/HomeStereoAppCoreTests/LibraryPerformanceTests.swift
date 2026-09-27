import Foundation
import XCTest
@testable import HomeStereoAppCore

final class LibraryPerformanceTests: XCTestCase {
    func testThirtyThousandTrackMetadataFixture() async throws {
        guard ProcessInfo.processInfo.environment["HOMESTEREO_RUN_PERFORMANCE"] == "1" else {
            throw XCTSkip("Set HOMESTEREO_RUN_PERFORMANCE=1 to run the 30k fixture.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("library.sqlite3")
        let repository = try SQLiteLibraryRepository(databaseURL: databaseURL)
        let folder = LibraryFolder(displayName: "Synthetic", path: root.path)
        try await repository.addFolder(folder, bookmarkData: Data([1]))
        let fixture = (0..<30_000).map { index in
            Track(
                id: deterministicUUID(index), libraryFolderID: folder.id,
                relativePath: String(format: "Artist%03d/Album%04d/Track%05d.mp3", index % 400, index % 2_000, index),
                url: root.appendingPathComponent("track-\(index).mp3"), fileSize: Int64(4_000_000 + index),
                modificationDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                title: "Track \(index)", artist: "Artist \(index % 400)", albumArtist: "Album Artist \(index % 250)",
                album: "Album \(index % 2_000)", duration: Double(120 + index % 300), hasArtwork: index % 3 == 0
            )
        }

        let initial = try await elapsed { try await repository.applySuccessfulScan(folderID: folder.id, tracks: fixture, scannedAt: .now) }
        let load = try await elapsed { _ = try await repository.loadTracks(folderID: nil) }
        let unchanged = try await elapsed { try await repository.applySuccessfulScan(folderID: folder.id, tracks: fixture, scannedAt: .now) }
        let loaded = try await repository.loadTracks(folderID: nil)
        let browseStart = ContinuousClock.now
        let browser = LibraryBrowserIndex(tracks: loaded, sort: .title)
        let browse = seconds(browseStart.duration(to: .now))
        let sortStart = ContinuousClock.now
        _ = LibraryBrowserIndex(tracks: loaded, sort: .artist, buildCollections: false)
        let trackSort = seconds(sortStart.duration(to: .now))
        let base = LibraryBrowserBase(tracks: loaded, sort: .title)
        let filterStart = ContinuousClock.now
        _ = LibraryBrowserIndex(base: base, genre: "Genre 1", buildCollections: false)
        let filter = seconds(filterStart.duration(to: .now))
        let clearFilterStart = ContinuousClock.now
        let cleared = LibraryBrowserIndex(base: base, buildCollections: false)
        let clearFilter = seconds(clearFilterStart.duration(to: .now))
        let searchStart = ContinuousClock.now
        _ = LibraryBrowserIndex(tracks: loaded, search: "Track 199", sort: .title)
        let search = seconds(searchStart.duration(to: .now))
        let attributes = try FileManager.default.attributesOfItem(atPath: databaseURL.path)
        let databaseBytes = attributes[.size] as? Int64 ?? 0
        print("PERF30K initial=\(initial) unchanged=\(unchanged) load=\(load) browse=\(browse) trackSort=\(trackSort) filter=\(filter) clearFilter=\(clearFilter) search=\(search) dbBytes=\(databaseBytes)")
        XCTAssertEqual(loaded.count, 30_000)
        XCTAssertEqual(browser.tracks.count, 30_000)
        XCTAssertEqual(cleared.tracks.count, 30_000)
    }

    private func elapsed(_ operation: () async throws -> Void) async throws -> Double {
        let start = ContinuousClock.now
        try await operation()
        return seconds(start.duration(to: .now))
    }

    private func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private func deterministicUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }
}
