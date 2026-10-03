import Foundation
import XCTest
@testable import HomeStereoAppCore
@testable import HomeStereoDLNAAppCore

@MainActor
final class FeatureAnalysisServiceTests: XCTestCase {
    func testPartialJournalRecoversCompleteLinesAndIgnoresTruncatedTail() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = FeatureRecord(id: UUID(), trackID: nil, title: nil, artist: nil,
            sourceIdentity: FeatureSourceIdentity(relativePath: "source.wav", fileSize: 10, duration: 5),
            analysisVersion: 2, analyzedAt: Date(), importedAt: Date(), features: FeatureValues(values: ["calm": 0.5]),
            sourceFormat: "Analyzer schema v1", sourceFileName: "HomeStereo Analyzer")
        var data = try FeatureCodec.encoder().encode(record)
        // Encode one compact JSON line, as written by Python.
        let object = try JSONSerialization.jsonObject(with: data)
        data = try JSONSerialization.data(withJSONObject: object)
        data.append(contentsOf: "\n{\"id\":".utf8)
        try data.write(to: directory.appendingPathComponent("completed.jsonl"))
        let recovered = try await FeatureRunFiles().partial(directory)
        XCTAssertEqual(recovered.map(\.id), [record.id])
    }
    func testInstalledCompanionViaNSWorkspaceWhenExplicitlyRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["HOMESTEREO_ANALYZER_SMOKE"] else {
            throw XCTSkip("Companion integration is explicitly enabled for local verification")
        }
        let url = URL(fileURLWithPath: path)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize!
        let id = UUID()
        var record = FeatureRecord(id: id, trackID: nil, title: "Synthetic verification", artist: nil,
            sourceIdentity: FeatureSourceIdentity(relativePath: "source.wav", fileSize: Int64(size), duration: 5),
            analysisVersion: 2, analyzedAt: Date(), importedAt: Date(), features: FeatureValues(values: [:]),
            sourceFormat: "Analyzer schema v1", sourceFileName: "HomeStereo Analyzer")
        record.homeStereoTrackID = id
        let task = FeatureAnalysisTask(localTrackID: id, path: path, record: record, semantic: true, loudness: true)
        var completed = false
        let records = try await FeatureAnalysisService().run(tasks: [task]) { progress in
            if progress.state == "completed" { completed = true }
        }
        XCTAssertTrue(completed)
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records[0].features.hasLoudness)
        XCTAssertNotNil(records[0].modelDescription)
        XCTAssertEqual(records[0].homeStereoTrackID, id)
    }
}
