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
            makeTrack(title: "Zulu", artist: "B", albumArtist: nil, album: "Second", genre: "Rock", duration: 20),
            makeTrack(title: "Alpha", artist: "A", albumArtist: nil, album: "First", genre: "Jazz", duration: 10),
        ]
        XCTAssertEqual(LibraryBrowserIndex(tracks: tracks, sort: .title).tracks.map(\.title), ["Alpha", "Zulu"])
        XCTAssertEqual(
            LibraryBrowserIndex(tracks: tracks, sort: .title, sortDirection: .descending).tracks.map(\.title),
            ["Zulu", "Alpha"]
        )
        XCTAssertEqual(LibraryBrowserIndex(tracks: tracks, search: "second").tracks.map(\.title), ["Zulu"])
        XCTAssertEqual(LibraryBrowserIndex(tracks: tracks, sort: .duration).tracks.map(\.duration), [10, 20])
        XCTAssertEqual(LibraryBrowserIndex(tracks: tracks, genre: "Rock").tracks.map(\.title), ["Zulu"])
        XCTAssertEqual(LibraryBrowserIndex(tracks: tracks).genres, ["Jazz", "Rock"])
        let tracksOnly = LibraryBrowserIndex(tracks: tracks, sort: .artist, buildCollections: false)
        XCTAssertEqual(tracksOnly.tracks.map(\.title), ["Alpha", "Zulu"])
        XCTAssertTrue(tracksOnly.albums.isEmpty)
        XCTAssertTrue(tracksOnly.artists.isEmpty)
    }

    func testGenrePresetMatchesMultipleGenresUnassignedAndFixedCategories() {
        let tracks = [
            makeTrack(title: "Ambient", artist: nil, albumArtist: nil, album: nil, genre: "Ambient"),
            makeTrack(title: "Classical", artist: nil, albumArtist: nil, album: nil, genre: "Classical"),
            makeTrack(title: "Unassigned", artist: nil, albumArtist: nil, album: nil),
            makeTrack(title: "Work", artist: nil, albumArtist: nil, album: nil, genre: "作業用BGM"),
            makeTrack(title: "Other", artist: nil, albumArtist: nil, album: nil, genre: "Rock"),
        ]
        let index = LibraryBrowserIndex(
            tracks: tracks, presetGenreNames: ["Ambient", "Classical"], includesUnassignedGenre: true
        )
        XCTAssertEqual(Set(index.tracks.map(\.title)), ["Ambient", "Classical", "Unassigned", "Work"])
    }

    func testReusableBasePreservesSortWhenFilterIsAppliedAndRemoved() {
        let tracks = [
            makeTrack(title: "Zulu", artist: "B", albumArtist: nil, album: nil, genre: "Rock"),
            makeTrack(title: "Alpha", artist: "A", albumArtist: nil, album: nil, genre: "Jazz"),
            makeTrack(title: "Mike", artist: "C", albumArtist: nil, album: nil, genre: "Rock"),
        ]
        let base = LibraryBrowserBase(tracks: tracks, sort: .title)

        XCTAssertEqual(LibraryBrowserIndex(base: base, genre: "Rock").tracks.map(\.title), ["Mike", "Zulu"])
        XCTAssertEqual(LibraryBrowserIndex(base: base).tracks.map(\.title), ["Alpha", "Mike", "Zulu"])
        XCTAssertEqual(base.genres, ["Jazz", "Rock"])
    }

    private func makeTrack(
        title: String, artist: String?, albumArtist: String?, album: String?, genre: String? = nil,
        duration: TimeInterval = 0
    ) -> Track {
        Track(
            libraryFolderID: UUID(), relativePath: "\(title).m4a",
            url: URL(fileURLWithPath: "/tmp/\(title).m4a"), title: title,
            artist: artist, albumArtist: albumArtist, album: album, genre: genre, duration: duration
        )
    }
}
