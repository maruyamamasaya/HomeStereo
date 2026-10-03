import Foundation
import XCTest
@testable import HomeStereoAppCore

final class TrackFeatureTests: XCTestCase {
    private func analyzer(path: String = "Album/song.flac", version: Int = 2, values: String = "\"calm\":0.7", date: String = "2026-09-01T12:00:00.123Z") -> Data {
        Data("""
        {"schemaVersion":1,"analysisVersion":\(version),"generatedAt":"\(date)","tracks":[{"relativePath":"\(path)","fileSize":1000,"duration":60,"title":"Song","artist":"Artist","features":{\(values)}}]}
        """.utf8)
    }
    private func track(id: UUID = UUID(), path: String = "Album/song.flac", size: Int64 = 1000) -> Track {
        Track(id: id, relativePath: path, url: URL(fileURLWithPath: "/fixture/\(path)"), fileSize: size, title: "Song", artist: "Artist", duration: 60)
    }
    func testAnalyzerValidationAndSnapshotRoundTrip() throws {
        var record = try XCTUnwrap(FeatureCodec.decode(analyzer(), fileName: "features.json").first)
        record.trackID = UUID()
        let data = try FeatureCodec.exportSnapshot([record])
        let decoded = try XCTUnwrap(FeatureCodec.decode(data, fileName: "MyMusic-Track-Features.json").first)
        XCTAssertEqual(decoded.trackID, record.trackID)
        XCTAssertEqual(decoded.features, record.features)
        XCTAssertEqual(decoded.sourceIdentity, record.sourceIdentity)
        // Existing snapshot dates use seconds; tolerate its documented precision.
        XCTAssertLessThan(abs(decoded.analyzedAt.timeIntervalSince(record.analyzedAt)), 1)
        XCTAssertThrowsError(try FeatureCodec.decode(analyzer(path: "../song.flac"), fileName: "bad"))
        XCTAssertThrowsError(try FeatureCodec.decode(analyzer(version: 0), fileName: "bad"))
        XCTAssertThrowsError(try FeatureCodec.decode(analyzer(values: "\"calm\":2"), fileName: "bad"))
        XCTAssertThrowsError(try FeatureCodec.decode(analyzer(values: "\"integratedLUFS\":-12"), fileName: "bad"))
        XCTAssertThrowsError(try FeatureCodec.decode(analyzer(date: "bad-date"), fileName: "bad"))
        XCTAssertThrowsError(try FeatureCodec.decode(analyzer(values: "\"madeUp\":0.5"), fileName: "bad"))
    }
    func testAnalyzerExportPreservesBatchAndRejectsMixedBatches() throws {
        let records = try FeatureCodec.decode(analyzer(), fileName: "source")
        let decoded = try FeatureCodec.decode(FeatureCodec.exportAnalyzer(records, generatedAt: records[0].analyzedAt), fileName: "output")
        XCTAssertEqual(decoded[0].analysisVersion, records[0].analysisVersion)
        XCTAssertEqual(decoded[0].analyzedAt, records[0].analyzedAt)
        XCTAssertEqual(decoded[0].features, records[0].features)
        var later = records[0]; later.sourceIdentity.relativePath = "later.flac"; later.analyzedAt = later.analyzedAt.addingTimeInterval(60)
        XCTAssertNoThrow(try FeatureCodec.exportAnalyzer(records + [later]))
        let older = try FeatureCodec.decode(analyzer(version: 1), fileName: "older")
        XCTAssertThrowsError(try FeatureCodec.exportAnalyzer(records + older))
        XCTAssertThrowsError(try FeatureCodec.exportAnalyzer(records + records))
    }
    func testProvidedJSONWhenExplicitlySupplied() async throws {
        guard let path = ProcessInfo.processInfo.environment["HOMESTEREO_FEATURE_FIXTURE"] else {
            throw XCTSkip("Personal JSON is supplied only for local verification")
        }
        let records = try FeatureCodec.decode(Data(contentsOf: URL(fileURLWithPath: path)), fileName: "provided.json")
        XCTAssertEqual(records.count, 9_283)
        XCTAssertEqual(records.filter { $0.features.hasLoudness }.count, 7_806)
        let exported = try FeatureCodec.decode(FeatureCodec.exportSnapshot(records), fileName: "roundtrip.json")
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: exported.map { ($0.trackID!, $0.features) }), Dictionary(uniqueKeysWithValues: records.map { ($0.trackID!, $0.features) }))
        XCTAssertEqual(Set(exported.map(\.analyzedAt)), Set(records.map(\.analyzedAt)))
    }
    func testPathMismatchDoesNotFallbackAndDuplicatesAreAmbiguous() throws {
        let r = try XCTUnwrap(FeatureCodec.decode(analyzer(), fileName: "features").first)
        let exact = track()
        XCTAssertEqual(FeatureResolver(tracks: [exact], links: []).resolve(r).localTrackID, exact.id)
        XCTAssertEqual(FeatureResolver(tracks: [exact, track()], links: []).resolve(r).status, "曖昧")
        let conflict = track(size: 2000), fallback = track(path: "Else/song.flac")
        XCTAssertNil(FeatureResolver(tracks: [conflict, fallback], links: []).resolve(r).localTrackID)
        XCTAssertEqual(FeatureResolver(tracks: [fallback], links: []).resolve(r).localTrackID, fallback.id)
    }
    func testCanonicalIDIsConservativeAndResolvesMovedPath() throws {
        var r = try XCTUnwrap(FeatureCodec.decode(analyzer(), fileName: "features").first)
        r.trackID = UUID()
        let moved = track(path: "Moved/song.flac")
        let link = MyMusicTrackLink(homeStereoTrackID: moved.id, myMusicTrackID: r.trackID!, relativePath: moved.relativePath, fileSize: 1000, duration: 60, matchedAt: Date(), matchMethod: .relativePath, source: .libraryImport)
        XCTAssertEqual(FeatureResolver(tracks: [moved], links: [link]).resolve(r).localTrackID, moved.id)
        let changed = track(id: moved.id, path: moved.relativePath, size: 2000)
        XCTAssertNil(FeatureResolver(tracks: [changed, track()], links: [link]).resolve(r).localTrackID)
    }
    func testRepeatImportOlderVersionAndLoudnessPreservationAcrossRestart() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("features.json")
        let archive = FeatureRepository(url: url)
        let current = try FeatureCodec.decode(analyzer(), fileName: "semantic")
        let first = try await archive.merge(current, tracks: [], links: [])
        let repeated = try await archive.merge(current, tracks: [], links: [])
        XCTAssertEqual(first.first?.id, repeated.first?.id)
        XCTAssertEqual(repeated.count, 1)
        let older = try FeatureCodec.decode(analyzer(version: 1, values: "\"calm\":0.1,\"integratedLUFS\":-12,\"truePeakDBTP\":-1,\"normalizationGainDB\":-2"), fileName: "dsp")
        _ = try await archive.merge(older, tracks: [], links: [])
        let reloaded = try await FeatureRepository(url: url).load()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded[0].analysisVersion, 2)
        XCTAssertEqual(reloaded[0].features.values["calm"], 0.7)
        XCTAssertEqual(reloaded[0].features.values["integratedLUFS"], -12)
        XCTAssertEqual(reloaded[0].loudnessSource?.sourceFileName, "dsp")
        var invalid = current[0]; invalid.sourceIdentity.fileSize = -1
        do { _ = try await archive.merge([current[0], invalid], tracks: [], links: []); XCTFail("must reject") } catch {}
        let after = try await archive.load()
        XCTAssertEqual(after, reloaded)
    }
    func testTwentyThousandIndexedRecordsAndNoDuplicateSave() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let template = try XCTUnwrap(FeatureCodec.decode(analyzer(), fileName: "fixture").first)
        let tracks = (0..<20_000).map { track(path: "Album/\($0).flac") }
        let records = tracks.map { t in
            var r = template; r.id = UUID(); r.sourceIdentity.relativePath = t.relativePath; return r
        }
        let resolver = FeatureResolver(tracks: tracks, links: [])
        XCTAssertTrue(zip(records, tracks).allSatisfy { resolver.resolve($0.0).localTrackID == $0.1.id })
        let archive = FeatureRepository(url: dir.appendingPathComponent("features.json"))
        _ = try await archive.merge(records, tracks: tracks, links: [])
        let again = try await archive.merge(records, tracks: tracks, links: [])
        XCTAssertEqual(again.count, 20_000)
    }
}
