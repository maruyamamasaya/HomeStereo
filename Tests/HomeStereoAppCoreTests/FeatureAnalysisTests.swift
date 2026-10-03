import Foundation
import XCTest
@testable import HomeStereoAppCore

final class FeatureAnalysisTests: XCTestCase {
    private func track(size: Int64 = 100, modified: Date = Date(timeIntervalSince1970: 100)) -> Track {
        Track(id: UUID(), relativePath: "song.flac", url: URL(fileURLWithPath: "/fixture/song.flac"), fileSize: size, modificationDate: modified, title: "Song", duration: 60)
    }
    private func record(_ track: Track, version: Int = 2, hasVolume: Bool = false) -> FeatureRecord {
        var values = ["calm": 0.8]
        if hasVolume { values.merge(["integratedLUFS": -20, "truePeakDBTP": -8, "normalizationGainDB": 4]) { $1 } }
        var record = FeatureRecord(id: UUID(), trackID: nil, title: "Song", artist: nil,
            sourceIdentity: FeatureSourceIdentity(relativePath: track.relativePath, fileSize: track.fileSize, duration: track.duration, modificationDate: track.modificationDate),
            analysisVersion: version, analyzedAt: Date(), importedAt: Date(), features: FeatureValues(values: values), sourceFormat: "snapshot", sourceFileName: "source")
        record.homeStereoTrackID = track.id
        return record
    }
    func testImportedSemanticSkipsAndLoudnessOnlyDoesNotRunModel() {
        let track = track(); let record = record(track)
        XCTAssertTrue(FeatureAnalysisPlanner.tasks(mode: .missing, tracks: [track], links: [], records: [record]).isEmpty)
        let tasks = FeatureAnalysisPlanner.tasks(mode: .loudness, tracks: [track], links: [], records: [record])
        XCTAssertEqual(tasks.count, 1); XCTAssertFalse(tasks[0].semantic); XCTAssertTrue(tasks[0].loudness)
        XCTAssertTrue(FeatureAnalysisPlanner.tasks(mode: .loudness, tracks: [track], links: [], records: [self.record(track, hasVolume: true)]).isEmpty)
    }
    func testUpdatesFindChangedSourceByStableLocalIDAndRefreshIdentity() {
        let track = track(); var old = record(track)
        old.sourceIdentity.fileSize = 99
        let tasks = FeatureAnalysisPlanner.tasks(mode: .update, tracks: [track], links: [], records: [old])
        XCTAssertEqual(tasks.count, 1); XCTAssertTrue(tasks[0].semantic); XCTAssertTrue(tasks[0].loudness)
        XCTAssertEqual(tasks[0].record.sourceIdentity.fileSize, 100)
        XCTAssertTrue(FeatureAnalysisPlanner.tasks(mode: .loudness, tracks: [track], links: [], records: [old]).isEmpty)
    }
    func testOldVersionCanUpdateWithoutRecomputingExistingVolume() {
        let track = track(); let old = record(track, version: 1, hasVolume: true)
        let tasks = FeatureAnalysisPlanner.tasks(mode: .update, tracks: [track], links: [], records: [old])
        XCTAssertEqual(tasks.count, 1); XCTAssertTrue(tasks[0].semantic); XCTAssertFalse(tasks[0].loudness)
    }
    func testChangedSourceReplacesSameLocalRecordRatherThanDuplicating() async throws {
        let track = track(); var old = record(track)
        old.sourceIdentity.fileSize = 99
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = FeatureRepository(url: root.appendingPathComponent("features.json"))
        _ = try await archive.merge([old], tracks: [], links: [])
        var updated = record(track); updated.analyzedAt = old.analyzedAt.addingTimeInterval(10)
        let saved = try await archive.merge([updated], tracks: [track], links: [])
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].id, old.id)
        XCTAssertEqual(saved[0].sourceIdentity.fileSize, 100)
    }
    func testNormalizationHeadroomToggleAndTruePeakSafety() {
        XCTAssertEqual(NormalizationPlaybackPolicy.amplitude(features: nil, enabled: false), 1)
        XCTAssertEqual(NormalizationPlaybackPolicy.amplitude(features: nil, enabled: true), Float(pow(10, -4.0 / 20)), accuracy: 0.00001)
        let boosted = FeatureValues(values: ["integratedLUFS": -20, "truePeakDBTP": -10, "normalizationGainDB": 4])
        XCTAssertEqual(NormalizationPlaybackPolicy.amplitude(features: boosted, enabled: true), 1)
        let peakLimited = FeatureValues(values: ["integratedLUFS": -20, "truePeakDBTP": -1, "normalizationGainDB": 4])
        XCTAssertEqual(NormalizationPlaybackPolicy.amplitude(features: peakLimited, enabled: true), Float(pow(10, -4.0 / 20)), accuracy: 0.00001)
    }
}
