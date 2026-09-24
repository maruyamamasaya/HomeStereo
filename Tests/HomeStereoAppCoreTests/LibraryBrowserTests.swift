import Foundation
import XCTest
@testable import HomeStereoAppCore

final class LibraryBrowserTests: XCTestCase {
    func testAlbumsUseAlbumArtistAndTitleAsCompositeIdentity() {
        let tracks = [
            makeTrack(title: "One", artist: "Singer", albumArtist: "Band A", album: "Shared"),
            makeTrack(title: "Two", artist: "Guest", albumArtist: "Band B", album: "Shared"),
        ]
        let index = LibraryBrowserIndex(tracks: tracks)
        XCTAssertEqual(index.albums.count, 2)
        XCTAssertEqual(Set(index.albums.compactMap(\.albumArtist)), ["Band A", "Band B"])
    }

    func testTrackArtistIsNotReplacedByAlbumArtist() {
        let index = LibraryBrowserIndex(tracks: [
            makeTrack(title: "Duet", artist: "Guest Singer", albumArtist: "Main Band", album: "Album")
        ])
        XCTAssertEqual(index.artists.map(\.name), ["Guest Singer"])
        XCTAssertFalse(index.artists.contains { $0.name == "Main Band" })
        XCTAssertEqual(index.albums.first?.albumArtist, "Main Band")
    }

    func testSearchAndSortArePreparedOutsideView() {
        let tracks = [
            makeTrack(title: "Zulu", artist: "B", albumArtist: nil, album: "Second", duration: 20),
            makeTrack(title: "Alpha", artist: "A", albumArtist: nil, album: "First", duration: 10),
        ]
        XCTAssertEqual(LibraryBrowserIndex(tracks: tracks, sort: .title).tracks.map(\.title), ["Alpha", "Zulu"])
        XCTAssertEqual(LibraryBrowserIndex(tracks: tracks, search: "second").tracks.map(\.title), ["Zulu"])
        XCTAssertEqual(LibraryBrowserIndex(tracks: tracks, sort: .duration).tracks.map(\.duration), [10, 20])
    }

    private func makeTrack(
        title: String, artist: String?, albumArtist: String?, album: String?, duration: TimeInterval = 0
    ) -> Track {
        Track(
            libraryFolderID: UUID(), relativePath: "\(title).m4a",
            url: URL(fileURLWithPath: "/tmp/\(title).m4a"), title: title,
            artist: artist, albumArtist: albumArtist, album: album, duration: duration
        )
    }
}
