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

    func testHighResolutionIsAQualityAttributeIndependentOfLibraryRelationships() {
        let examples: [(sampleRate: Double, bitDepth: Int, expected: Bool)] = [
            (44_100, 16, false),
            (48_000, 16, false),
            (44_100, 24, true),
            (48_000, 24, true),
            (96_000, 16, true),
            (96_000, 24, true),
            (32_000, 24, false),
            (96_000, 12, false),
        ]
        let tracks = examples.enumerated().map { index, example in
            Track(
                url: URL(fileURLWithPath: "/tmp/quality-\(index).flac"), title: "Quality \(index)",
                artist: "Artist", album: "Album",
                sampleRate: example.sampleRate, bitDepth: example.bitDepth
            )
        }

        for (track, example) in zip(tracks, examples) {
            XCTAssertEqual(
                track.isHighResolutionAudio, example.expected,
                "\(example.sampleRate)Hz / \(example.bitDepth)bit"
            )
        }

        let tagged = Track(
            url: URL(fileURLWithPath: "/tmp/tagged.flac"), title: "Tagged",
            artist: "Artist", album: "Album", genre: "Ambient; ハイレゾ",
            sampleRate: 32_000, bitDepth: 12
        )
        XCTAssertTrue(tagged.isHighResolutionAudio)

        let index = LibraryBrowserIndex(tracks: tracks + [tagged])
        XCTAssertEqual(index.albums.first?.tracks.count, examples.count + 1)
        XCTAssertEqual(index.artists.first?.tracks.count, examples.count + 1)
    }

    func testRegularLibraryTrackExcludesWorkBGMAndHighResolutionTracks() {
        let regular = Track(
            url: URL(fileURLWithPath: "/tmp/regular.m4a"), title: "Regular",
            sampleRate: 48_000, bitDepth: 16
        )
        let work = Track(
            url: URL(fileURLWithPath: "/tmp/work.m4a"), title: "Work",
            genre: Track.workPlaybackGenre, sampleRate: 48_000, bitDepth: 16
        )
        let highResolution = Track(
            url: URL(fileURLWithPath: "/tmp/high-resolution.flac"), title: "High Resolution",
            sampleRate: 96_000, bitDepth: 24
        )
        let taggedHighResolution = Track(
            url: URL(fileURLWithPath: "/tmp/tagged-high-resolution.m4a"), title: "Tagged High Resolution",
            genre: Track.highResolutionGenre, sampleRate: 48_000, bitDepth: 16
        )

        XCTAssertTrue(regular.isRegularLibraryTrack)
        XCTAssertFalse(work.isRegularLibraryTrack)
        XCTAssertFalse(highResolution.isRegularLibraryTrack)
        XCTAssertFalse(taggedHighResolution.isRegularLibraryTrack)
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
