import Foundation

public enum FeatureAnalysisMode: String, Sendable {
    case missing, loudness, update
}

public struct FeatureAnalysisTask: Codable, Sendable {
    public let localTrackID: UUID
    public let path: String
    public var record: FeatureRecord
    public let semantic: Bool
    public let loudness: Bool
}

public enum FeatureAnalysisPlanner {
    public static func tasks(mode: FeatureAnalysisMode, tracks: [Track], links: [MyMusicTrackLink], records: [FeatureRecord]) -> [FeatureAnalysisTask] {
        let resolver = FeatureResolver(tracks: tracks, links: links)
        let localIDs = Set(tracks.map(\.id))
        let canonicalIDs = Dictionary(grouping: links, by: \.myMusicTrackID)
        var existing: [UUID: FeatureRecord] = [:]
        for record in records {
            let storedID = record.homeStereoTrackID.flatMap { localIDs.contains($0) ? $0 : nil }
            let linkedID = record.trackID.flatMap { canonicalIDs[$0] }.flatMap { $0.count == 1 ? $0[0].homeStereoTrackID : nil }
            guard let id = storedID ?? linkedID ?? resolver.resolve(record).localTrackID, localIDs.contains(id) else { continue }
            if let previous = existing[id], previous.analysisVersion > record.analysisVersion || (previous.analysisVersion == record.analysisVersion && previous.analyzedAt > record.analyzedAt) { continue }
            existing[id] = record
        }
        let canonical = Dictionary(grouping: links, by: \.homeStereoTrackID)
        return tracks.filter { $0.scanState == .available }.compactMap { track in
            let previous = existing[track.id]
            let hasSemantic = previous.map { !FeatureValues.scores.intersection($0.features.values.keys).isEmpty } ?? false
            let changed = previous.map { record in
                record.sourceIdentity.fileSize != track.fileSize || record.sourceIdentity.modificationDate.map { abs($0.timeIntervalSince(track.modificationDate)) > 1 } == true
            } ?? false
            let old = previous.map { $0.analysisVersion < 2 } ?? false
            let semantic: Bool
            let volume: Bool
            switch mode {
            case .missing:
                guard !hasSemantic else { return nil }; semantic = true; volume = previous?.features.hasLoudness != true || changed
            case .loudness:
                guard previous?.features.hasLoudness != true, !changed else { return nil }; semantic = false; volume = true
            case .update:
                guard previous != nil, changed || old else { return nil }; semantic = true; volume = changed || previous?.features.hasLoudness != true
            }
            let identity = FeatureSourceIdentity(relativePath: track.relativePath, fileSize: track.fileSize, duration: track.duration,
                modificationDate: track.modificationDate, contentHash: nil, title: track.title, artist: track.artist, album: track.album)
            var record = previous ?? FeatureRecord(id: UUID(), trackID: canonical[track.id]?.count == 1 ? canonical[track.id]![0].myMusicTrackID : nil,
                title: track.title, artist: track.artist, sourceIdentity: identity, analysisVersion: 2,
                analyzedAt: Date(), importedAt: Date(), features: FeatureValues(values: [:]),
                sourceFormat: "Analyzer schema v1", sourceFileName: "HomeStereo Analyzer")
            // Refresh source identity only when reading changed/new sources. Loudness enrichment keeps semantic provenance.
            if semantic { record.sourceIdentity = identity }
            record.homeStereoTrackID = track.id
            return FeatureAnalysisTask(localTrackID: track.id, path: track.url.path, record: record, semantic: semantic, loudness: volume)
        }
    }
}

public struct FeatureAnalysisProgress: Decodable, Sendable {
    public let state: String
    public let completed: Int
    public let total: Int
    public let failed: Int
    public let message: String
    public init(state: String, completed: Int, total: Int, failed: Int, message: String) {
        self.state = state; self.completed = completed; self.total = total
        self.failed = failed; self.message = message
    }
}

public enum NormalizationPlaybackPolicy {
    /// Reserve 4 dB of player headroom so AVPlayer can express both cuts and boosts without amplification above unity.
    public static func amplitude(features: FeatureValues?, enabled: Bool) -> Float {
        guard enabled else { return 1 }
        var gain = 0.0
        if let features, features.hasLoudness,
           let recommended = features.values["normalizationGainDB"], let peak = features.values["truePeakDBTP"],
           recommended.isFinite, peak.isFinite {
            gain = min(max(-4, min(4, recommended)), -1 - peak)
        }
        return Float(pow(10, (gain - 4) / 20))
    }
}
