import Foundation
import XCTest
@testable import HomeStereoAppCore

final class MyMusicJSONContractTests: XCTestCase {
    private let trackID = UUID(uuidString: "d522d30b-37cd-4d4a-87a6-f2ac304f8865")!
    private let otherTrackID = UUID(uuidString: "3f629203-cbe1-4c32-a39c-aa15ce7ea777")!

    func testLibraryImportsExactTrackIDCasingAndPreservesIdentity() throws {
        let data = Data(#"{"version":1,"tracks":[{"trackID":"d522d30b-37cd-4d4a-87a6-f2ac304f8865","title":"Night Drive","artist":"Sample Artist","duration":243.21,"format":"FLAC"}]}"#.utf8)
        let imported = try MyMusicJSONImportService().importLibrary(data)
        XCTAssertEqual(imported.tracks.first?.trackID, trackID)

        let wrongCase = Data(#"{"version":1,"tracks":[{"trackId":"d522d30b-37cd-4d4a-87a6-f2ac304f8865","title":"Night Drive","artist":"Sample Artist","duration":243.21}]}"#.utf8)
        XCTAssertThrowsError(try MyMusicJSONImportService().importLibrary(wrongCase))
    }

    func testLibraryRejectsUnsupportedVersionDuplicateIDsAndInvalidFingerprint() throws {
        let unsupported = Data(#"{"version":2,"tracks":[]}"#.utf8)
        XCTAssertThrowsError(try MyMusicJSONCodec.decodeLibrary(unsupported)) { error in
            XCTAssertEqual(error as? MyMusicJSONContractError, .unsupportedVersion(2))
        }

        let duplicate = Data(#"{"version":1,"tracks":[{"trackID":"d522d30b-37cd-4d4a-87a6-f2ac304f8865","title":"A","artist":"B","duration":1},{"trackID":"d522d30b-37cd-4d4a-87a6-f2ac304f8865","title":"C","artist":"D","duration":2}]}"#.utf8)
        XCTAssertThrowsError(try MyMusicJSONCodec.decodeLibrary(duplicate))

        let fingerprint = Data(#"{"version":1,"tracks":[{"trackID":"d522d30b-37cd-4d4a-87a6-f2ac304f8865","title":"A","artist":"B","duration":1,"audioFingerprint":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}]}"#.utf8)
        XCTAssertThrowsError(try MyMusicJSONCodec.decodeLibrary(fingerprint))
    }

    func testPreferencesUseLowercaseDTrackIdAndValidateWholeDocument() throws {
        let data = Data(#"{"schemaVersion":2,"exportedAt":"2026-09-25T12:34:56Z","tracks":[{"trackId":"d522d30b-37cd-4d4a-87a6-f2ac304f8865","playbackPreference":4,"favorite":true},{"trackId":"3f629203-cbe1-4c32-a39c-aa15ce7ea777","playbackPreference":0,"favorite":false}]}"#.utf8)
        let imported = try MyMusicJSONImportService().importPreferences(data)
        XCTAssertEqual(imported.tracks.map(\.trackID), [trackID, otherTrackID])

        let invalidTail = Data(#"{"schemaVersion":2,"exportedAt":"2026-09-25T12:34:56Z","tracks":[{"trackId":"d522d30b-37cd-4d4a-87a6-f2ac304f8865","playbackPreference":4,"favorite":true},{"trackId":"3f629203-cbe1-4c32-a39c-aa15ce7ea777","playbackPreference":11,"favorite":false}]}"#.utf8)
        XCTAssertThrowsError(try MyMusicJSONImportService().importPreferences(invalidTail))
    }

    func testPlaybackEventsRejectDuplicatesInvalidEnumsAndCompletedSkippedConflict() throws {
        let validEvent = #"{"eventId":"mac-550e8400-e29b-41d4-a716-446655440000","trackId":"d522d30b-37cd-4d4a-87a6-f2ac304f8865","trackTitle":"Night Drive","artist":"Sample Artist","playedAt":"2026-09-25T12:00:00Z","playDuration":182.5,"trackDuration":243.21,"completed":false,"skipped":true,"playSource":"playlist","selectionType":"manual","platform":"macOS","schemaVersion":1}"#
        let valid = Data("{\"schemaVersion\":1,\"exportedAt\":\"2026-09-25T12:34:56Z\",\"events\":[\(validEvent)]}".utf8)
        let imported = try MyMusicJSONImportService().importPlaybackEvents(valid)
        XCTAssertEqual(imported.events.first?.eventID, "mac-550e8400-e29b-41d4-a716-446655440000")

        let duplicate = Data("{\"schemaVersion\":1,\"exportedAt\":\"2026-09-25T12:34:56Z\",\"events\":[\(validEvent),\(validEvent)]}".utf8)
        XCTAssertThrowsError(try MyMusicJSONCodec.decodePlaybackEvents(duplicate))

        let conflict = validEvent.replacingOccurrences(of: "\"completed\":false", with: "\"completed\":true")
        XCTAssertThrowsError(try MyMusicJSONCodec.decodePlaybackEvents(Data("{\"schemaVersion\":1,\"exportedAt\":\"2026-09-25T12:34:56Z\",\"events\":[\(conflict)]}".utf8)))

        let invalidSelection = validEvent.replacingOccurrences(of: "\"selectionType\":\"manual\"", with: "\"selectionType\":\"radio\"")
        XCTAssertThrowsError(try MyMusicJSONCodec.decodePlaybackEvents(Data("{\"schemaVersion\":1,\"exportedAt\":\"2026-09-25T12:34:56Z\",\"events\":[\(invalidSelection)]}".utf8)))
    }

    func testExportsOmitNilFieldsUseExactNamesAndRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_758_803_696)
        let library = try MyMusicJSONExportService().exportLibrary([
            MyMusicTrackRecord(trackID: trackID, title: "Night Drive", artist: "Sample Artist", duration: 243.21)
        ])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: library) as? [String: Any])
        let track = try XCTUnwrap((object["tracks"] as? [[String: Any]])?.first)
        XCTAssertEqual(track["trackID"] as? String, trackID.uuidString)
        XCTAssertNil(track["trackId"])
        XCTAssertNil(track["album"])

        let preferences = try MyMusicJSONExportService().exportPreferences([
            MyMusicPreferenceRecord(trackID: trackID, playbackPreference: -2, favorite: true)
        ], exportedAt: date)
        let preferenceObject = try XCTUnwrap(JSONSerialization.jsonObject(with: preferences) as? [String: Any])
        let preference = try XCTUnwrap((preferenceObject["tracks"] as? [[String: Any]])?.first)
        XCTAssertEqual(preference["trackId"] as? String, trackID.uuidString)
        XCTAssertNil(preference["trackID"])
        XCTAssertEqual(try MyMusicJSONImportService().importPreferences(preferences).tracks.first?.playbackPreference, -2)
    }

    func testDatesMustBeUTCISO8601() {
        let offset = Data(#"{"schemaVersion":2,"exportedAt":"2026-09-25T21:34:56+09:00","tracks":[]}"#.utf8)
        XCTAssertThrowsError(try MyMusicJSONCodec.decodePreferences(offset))
        let malformed = Data(#"{"schemaVersion":2,"exportedAt":"2026/09/25 12:34:56Z","tracks":[]}"#.utf8)
        XCTAssertThrowsError(try MyMusicJSONCodec.decodePreferences(malformed))
        let utf16 = #"{"schemaVersion":2,"exportedAt":"2026-09-25T12:34:56Z","tracks":[]}"#.data(using: .utf16)!
        XCTAssertThrowsError(try MyMusicJSONCodec.decodePreferences(utf16))
    }

    func testMergeKeepsOmittedPreferencesAndDeduplicatesEventsByEventID() {
        let existingPreference = MyMusicPreferenceRecord(trackID: otherTrackID, playbackPreference: 3, favorite: true)
        let importedPreference = MyMusicPreferenceRecord(trackID: trackID, playbackPreference: -1, favorite: false)
        let merged = MyMusicImportMergeService.mergePreferences(
            imported: [importedPreference], into: [existingPreference]
        )
        XCTAssertEqual(Set(merged.map(\.trackID)), [trackID, otherTrackID])

        let event = MyMusicPlaybackEventRecord(
            eventID: "mac-event", trackID: trackID, trackTitle: "Night Drive", artist: "Artist",
            playedAt: .distantPast, playDuration: 1, trackDuration: 2, completed: false,
            skipped: true, playSource: "library", selectionType: "manual", platform: "macOS"
        )
        XCTAssertEqual(MyMusicImportMergeService.appendEvents(imported: [event], to: [event]).count, 1)
    }

    func testCurrentModelsExportDerivedLibraryValuesAndMacEventFields() throws {
        let track = Track(
            id: trackID, url: URL(fileURLWithPath: "/tmp/night.flac"), title: "Night Drive",
            artist: "Sample Artist", duration: 243.21, codec: "flac"
        )
        let startedAt = Date(timeIntervalSince1970: 1_758_801_600)
        let eventID = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!
        let event = PlaybackEvent(
            id: eventID, trackID: trackID, startedAt: startedAt, playedSeconds: 182.5, outcome: .completed
        )
        let service = MyMusicJSONExportService()
        let library = try service.exportLibrary(
            tracks: [track], favorites: [Favorite(trackID: trackID)], events: [event]
        )
        let importedLibrary = try MyMusicJSONImportService().importLibrary(library)
        XCTAssertEqual(importedLibrary.tracks.first?.favorite, true)
        XCTAssertEqual(importedLibrary.tracks.first?.playCount, 1)
        XCTAssertEqual(importedLibrary.tracks.first?.lastPlayedAt, startedAt)
        XCTAssertEqual(importedLibrary.tracks.first?.format, "FLAC")

        let record = service.playbackEventRecord(
            event: event, track: track, skipped: true, playSource: "playlist", selectionType: "manual"
        )
        XCTAssertEqual(record.eventID, "mac-550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(record.platform, "macOS")
        XCTAssertTrue(record.completed)
        XCTAssertFalse(record.skipped)
    }
}
