import Foundation
import XCTest
@testable import HomeStereoAppCore

final class GenreDisplayPresetTests: XCTestCase {
    func testIPhoneDocumentRoundTripsOrderAndUnassignedSetting() throws {
        let firstID = UUID(), secondID = UUID()
        let data = Data("""
        {"kind":"mymusic.genre-display-presets","version":1,"presets":[
          {"id":"\(firstID.uuidString)","name":"集中","enabledGenreNames":["Ambient","maruyama.MyMusic.genre.unassigned"],"includesUnassignedGenreSetting":true},
          {"id":"\(secondID.uuidString)","name":"旧形式","enabledGenreNames":["Classical"]}
        ]}
        """.utf8)
        let decoded = try GenreDisplayPresetCodec.decode(data)
        XCTAssertEqual(decoded.presets.map(\.id), [firstID, secondID])
        XCTAssertTrue(decoded.presets[0].includesUnassignedGenre)
        XCTAssertTrue(decoded.presets[1].includesUnassignedGenre)
        XCTAssertEqual(try GenreDisplayPresetCodec.decode(GenreDisplayPresetCodec.encode(decoded.presets)).presets, decoded.presets)
    }

    func testInvalidDocumentsAreRejectedWhole() throws {
        let id = UUID()
        let documents = [
            "{\"kind\":\"mymusic.genre-display-presets\",\"version\":1,\"presets\":[{\"id\":\"\(id)\",\"name\":\"A\",\"enabledGenreNames\":[],\"unknown\":1}]}",
            "{\"kind\":\"mymusic.genre-display-presets\",\"version\":1,\"presets\":[{\"id\":\"\(id)\",\"name\":\"A\",\"enabledGenreNames\":[]},{\"id\":\"\(id)\",\"name\":\"B\",\"enabledGenreNames\":[]}]}",
            "{\"kind\":\"mymusic.genre-display-presets\",\"version\":1,\"presets\":[{\"id\":\"\(UUID())\",\"name\":\"Ａ\",\"enabledGenreNames\":[]},{\"id\":\"\(UUID())\",\"name\":\"a\",\"enabledGenreNames\":[]}]}",
        ]
        for value in documents {
            XCTAssertThrowsError(try GenreDisplayPresetCodec.decode(Data(value.utf8)))
        }
    }

    func testSQLitePersistsPresetOrderAndReplacementIsAtomic() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("genre-presets-\(UUID()).sqlite3")
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = try SQLiteLibraryRepository(databaseURL: url)
        let presets = [
            GenreDisplayPreset(name: "集中", enabledGenreNames: ["Ambient"]),
            GenreDisplayPreset(name: "夜", enabledGenreNames: ["Jazz"], includesUnassignedGenreSetting: false),
        ]
        try await repository.replaceGenreDisplayPresets(presets)
        let firstLoad = try await repository.loadGenreDisplayPresets()
        XCTAssertEqual(firstLoad, presets)
        do {
            try await repository.replaceGenreDisplayPresets([
                presets[0], GenreDisplayPreset(name: "ＣＥＮＴＥＲ", enabledGenreNames: []),
                GenreDisplayPreset(name: "center", enabledGenreNames: [])
            ])
            XCTFail("重複名を拒否する必要があります")
        } catch {}
        let secondLoad = try await repository.loadGenreDisplayPresets()
        let schemaVersion = try await repository.schemaVersion()
        XCTAssertEqual(secondLoad, presets)
        XCTAssertEqual(schemaVersion, 13)
    }
}
