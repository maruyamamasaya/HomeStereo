import Foundation

public struct FeatureSourceIdentity: Codable, Equatable, Sendable {
    public var relativePath: String
    public var fileSize: Int64
    public var duration: Double
    public var modificationDate: Date?
    public var contentHash: String?
    public var title: String?
    public var artist: String?
    public var album: String?
}

public struct FeatureValues: Codable, Equatable, Sendable {
    public var values: [String: Double]
    public var additional: [String: Double]
    public static let scores: Set<String> = ["energy", "piano", "ambient", "electronic", "drumAndBass", "aggressive", "calm", "bright", "dark", "vocal", "instrumental"]
    public static let loudness: Set<String> = ["integratedLUFS", "truePeakDBTP", "normalizationGainDB"]
    struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    public init(values: [String: Double], additional: [String: Double] = [:]) {
        self.values = values; self.additional = additional
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        values = [:]; additional = [:]
        for key in c.allKeys {
            if key.stringValue == "additional" {
                additional = try c.decodeIfPresent([String: Double].self, forKey: key) ?? [:]
            } else if let value = try c.decodeIfPresent(Double.self, forKey: key) {
                values[key.stringValue] = value
            }
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        for (key, value) in values { try c.encode(value, forKey: Key(stringValue: key)) }
        if !additional.isEmpty { try c.encode(additional, forKey: Key(stringValue: "additional")) }
    }
    public var hasLoudness: Bool { Self.loudness.allSatisfy { values[$0] != nil } }
    public func validate() throws {
        guard !values.isEmpty || !additional.isEmpty else { throw FeatureError.invalid("特徴量が空です。") }
        for (key, value) in values {
            guard value.isFinite else { throw FeatureError.invalid("有限値ではありません。") }
            if Self.scores.contains(key) { guard (0...1).contains(value) else { throw FeatureError.invalid("特徴量の範囲が不正です。") } }
            else if key == "tempo" { guard value > 0 else { throw FeatureError.invalid("BPMが不正です。") } }
            else if key == "normalizationGainDB" { guard (-4...4).contains(value) else { throw FeatureError.invalid("音量補正の範囲が不正です。") } }
            else if !Self.loudness.contains(key) { throw FeatureError.invalid("未対応の特徴量: \(key)") }
        }
        guard Self.loudness.intersection(values.keys).isEmpty || hasLoudness else { throw FeatureError.invalid("音量解析3項目が揃っていません。") }
        for (key, value) in additional {
            guard !Self.scores.contains(key), value.isFinite, (0...1).contains(value) else { throw FeatureError.invalid("追加特徴量が不正です。") }
        }
    }
    public func preservingLoudness(from other: Self) -> Self {
        guard !hasLoudness, other.hasLoudness else { return self }
        var result = self
        for key in Self.loudness { result.values[key] = other.values[key] }
        return result
    }
}

public struct FeatureRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var trackID: UUID?
    public var title: String?
    public var artist: String?
    public var sourceIdentity: FeatureSourceIdentity
    public var analysisVersion: Int
    public var analyzedAt: Date
    public var importedAt: Date
    public var features: FeatureValues
    public var sourceFormat: String
    public var sourceFileName: String
    public var modelDescription: String?
    public var analysisProfile: String?
    public var homeStereoTrackID: UUID?
    public var loudnessSource: FeatureOrigin?
    public var identityKey: String {
        if let trackID { return "id:" + trackID.uuidString }
        let s = sourceIdentity
        return "source:" + [s.relativePath.precomposedStringWithCanonicalMapping, String(s.fileSize), String(s.duration), s.title ?? "", s.artist ?? "", s.album ?? ""].joined(separator: "\u{001F}")
    }
}

public struct FeatureOrigin: Codable, Equatable, Sendable {
    public var analysisVersion: Int
    public var analyzedAt: Date
    public var sourceFileName: String
    public var methodName: String?
    public init(record: FeatureRecord) {
        analysisVersion = record.analysisVersion; analyzedAt = record.analyzedAt; sourceFileName = record.sourceFileName
    }
}

public enum FeatureError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

public enum FeatureCodec {
    private struct Snapshot: Codable {
        var version: Int
        var exportedAt: Date
        var tracks: [SnapshotItem]
    }
    private struct SnapshotItem: Codable {
        var trackID: UUID
        var title: String?
        var artist: String?
        var sourceIdentity: FeatureSourceIdentity
        var analysisVersion: Int
        var analyzedAt: Date
        var importedAt: Date
        var features: FeatureValues
    }
    private struct Analyzer: Codable {
        var schemaVersion: Int
        var analysisVersion: Int
        var generatedAt: Date
        var tracks: [AnalyzerItem]
    }
    private struct AnalyzerItem: Codable {
        var relativePath: String
        var fileSize: Int64
        var duration: Double
        var modificationDate: Date?
        var contentHash: String?
        var title: String?
        var artist: String?
        var album: String?
        var features: FeatureValues
        var identity: FeatureSourceIdentity {
            .init(relativePath: relativePath, fileSize: fileSize, duration: duration, modificationDate: modificationDate, contentHash: contentHash, title: title, artist: artist, album: album)
        }
    }
    public static func exportAnalyzer(_ records: [FeatureRecord], generatedAt: Date = Date()) throws -> Data {
        guard let first = records.first else { throw FeatureError.invalid("書き出し対象がありません。") }
        guard records.allSatisfy({ $0.analysisVersion == first.analysisVersion }) else {
            throw FeatureError.invalid("Analyzer形式は同じ解析版ごとに書き出してください。")
        }
        var paths = Set<String>()
        let entries = try records.map { r -> AnalyzerItem in
            try validate(r)
            let s = r.sourceIdentity
            guard paths.insert(s.relativePath.precomposedStringWithCanonicalMapping).inserted else {
                throw FeatureError.invalid("異なる音楽フォルダの相対パスが重複しています。全件保存用の形式で書き出してください。")
            }
            return .init(relativePath: s.relativePath, fileSize: s.fileSize, duration: s.duration,
                modificationDate: s.modificationDate, contentHash: s.contentHash, title: s.title,
                artist: s.artist, album: s.album, features: r.features)
        }
        return try encoder().encode(Analyzer(schemaVersion: 1, analysisVersion: first.analysisVersion,
            generatedAt: generatedAt, tracks: entries))
    }
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let value = try c.decode(String.self)
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: value) { return date }
            f.formatOptions = [.withInternetDateTime]
            guard let date = f.date(from: value) else { throw FeatureError.invalid("日時が不正です。") }
            return date
        }
        return d
    }
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try c.encode(f.string(from: date))
        }
        return e
    }
    public static func decode(_ data: Data, fileName: String, now: Date = Date()) throws -> [FeatureRecord] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw FeatureError.invalid("JSON文書ではありません。") }
        let snapshot = root["version"] != nil && root["schemaVersion"] == nil
        let rootKeys: Set<String> = snapshot ? ["version", "exportedAt", "tracks"] : ["schemaVersion", "analysisVersion", "generatedAt", "tracks"]
        guard Set(root.keys).isSubset(of: rootKeys), let items = root["tracks"] as? [[String: Any]] else { throw FeatureError.invalid("文書の項目が不正です。") }
        let identityKeys: Set<String> = ["relativePath", "fileSize", "duration", "modificationDate", "contentHash", "title", "artist", "album"]
        let itemKeys: Set<String> = snapshot ? ["trackID", "title", "artist", "sourceIdentity", "analysisVersion", "analyzedAt", "importedAt", "features"] : identityKeys.union(["features"])
        for item in items {
            guard Set(item.keys).isSubset(of: itemKeys) else { throw FeatureError.invalid("未対応の曲情報が含まれています。") }
            if snapshot {
                guard let source = item["sourceIdentity"] as? [String: Any], Set(source.keys).isSubset(of: identityKeys) else { throw FeatureError.invalid("音源識別情報の項目が不正です。") }
            }
        }
        let records: [FeatureRecord]
        if root["version"] != nil && root["schemaVersion"] == nil {
            let doc = try decoder().decode(Snapshot.self, from: data)
            guard doc.version == 1 else { throw FeatureError.invalid("未対応の特徴量versionです。") }
            records = doc.tracks.map { .init(id: UUID(), trackID: $0.trackID, title: $0.title, artist: $0.artist, sourceIdentity: $0.sourceIdentity, analysisVersion: $0.analysisVersion, analyzedAt: $0.analyzedAt, importedAt: $0.importedAt, features: $0.features, sourceFormat: "MyMusic snapshot v1", sourceFileName: fileName) }
        } else {
            let doc = try decoder().decode(Analyzer.self, from: data)
            guard doc.schemaVersion == 1, doc.analysisVersion >= 1 else { throw FeatureError.invalid("未対応のAnalyzer versionです。") }
            records = doc.tracks.map { .init(id: UUID(), trackID: nil, title: $0.title, artist: $0.artist, sourceIdentity: $0.identity, analysisVersion: doc.analysisVersion, analyzedAt: doc.generatedAt, importedAt: now, features: $0.features, sourceFormat: "Analyzer schema v1", sourceFileName: fileName) }
        }
        var keys = Set<String>()
        for record in records {
            try validate(record)
            guard keys.insert(record.identityKey).inserted else { throw FeatureError.invalid("同じ曲の特徴量が重複しています。") }
        }
        return records
    }
    public static func validate(_ r: FeatureRecord) throws {
        let s = r.sourceIdentity
        let parts = s.relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !s.relativePath.isEmpty, !s.relativePath.hasPrefix("/"), !s.relativePath.contains("\\"), !parts.contains("."), !parts.contains(".."), !parts.contains(""), s.fileSize > 0, s.duration.isFinite, s.duration > 0, r.analysisVersion >= 1 else { throw FeatureError.invalid("音源識別情報が不正です。") }
        if let hash = s.contentHash {
            guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { throw FeatureError.invalid("contentHashが不正です。") }
        }
        try r.features.validate()
    }
    /// MyMusic's existing snapshot export contract. Records without a canonical ID are excluded.
    public static func exportSnapshot(_ records: [FeatureRecord], now: Date = Date()) throws -> Data {
        let items = records.compactMap { r -> SnapshotItem? in
            guard let id = r.trackID else { return nil }
            return .init(trackID: id, title: r.title, artist: r.artist, sourceIdentity: r.sourceIdentity, analysisVersion: r.analysisVersion, analyzedAt: r.analyzedAt, importedAt: r.importedAt, features: r.features)
        }.sorted { $0.trackID.uuidString < $1.trackID.uuidString }
        return try encoder().encode(Snapshot(version: 1, exportedAt: now, tracks: items))
    }
}

public struct FeatureResolution: Identifiable, Sendable {
    public let record: FeatureRecord
    public let localTrackID: UUID?
    public let status: String
    public var id: UUID { record.id }
}

public struct FeatureResolver: Sendable {
    private let tracksByID: [UUID: Track]
    private let canonical: [UUID: [UUID]]
    private let paths: [String: [Track]]
    private let metadata: [String: [Track]]
    public init(tracks: [Track], links: [MyMusicTrackLink]) {
        tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        canonical = Dictionary(grouping: links, by: \.myMusicTrackID).mapValues { $0.map(\.homeStereoTrackID) }
        paths = Dictionary(grouping: tracks, by: { $0.relativePath.precomposedStringWithCanonicalMapping })
        metadata = Dictionary(grouping: tracks, by: { Self.metadataKey($0.title, $0.artist) })
    }
    private static func normalize(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    private static func metadataKey(_ title: String?, _ artist: String?) -> String {
        normalize(title) + "\u{001F}" + normalize(artist)
    }
    public func resolve(_ r: FeatureRecord) -> FeatureResolution {
        let s = r.sourceIdentity
        var candidates: [Track]
        var method = "パス"
        if let id = r.homeStereoTrackID, let track = tracksByID[id] {
            candidates = [track]; method = "HomeStereo ID"
        } else if let id = r.trackID, let ids = canonical[id], !ids.isEmpty {
            candidates = ids.compactMap { tracksByID[$0] }; method = "MyMusic ID"
        } else if let pathTracks = paths[s.relativePath.precomposedStringWithCanonicalMapping] {
            candidates = pathTracks
        } else if let title = s.title, let artist = s.artist, !Self.normalize(title).isEmpty, !Self.normalize(artist).isEmpty {
            candidates = (metadata[Self.metadataKey(title, artist)] ?? []).filter { s.album == nil || Self.normalize(s.album) == Self.normalize($0.album) }
            method = "メタデータ"
        } else { candidates = [] }
        candidates = candidates.filter { $0.fileSize == s.fileSize && abs($0.duration - s.duration) <= 0.5 }
        return .init(record: r, localTrackID: candidates.count == 1 ? candidates[0].id : nil, status: candidates.count == 1 ? "照合済み（\(method)）" : candidates.isEmpty ? "未照合" : "曖昧")
    }
}

public actor FeatureRepository {
    private let url: URL
    private struct Archive: Codable { var version: Int; var records: [FeatureRecord] }
    public init(url: URL) { self.url = url }
    public static func defaultURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("HomeStereo/track-features.json")
    }
    public func load() throws -> [FeatureRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let archive = try FeatureCodec.decoder().decode(Archive.self, from: Data(contentsOf: url))
        guard archive.version == 1 else { throw FeatureError.invalid("未対応の保存形式です。") }
        for record in archive.records { try FeatureCodec.validate(record) }
        return archive.records
    }
    public func merge(_ incoming: [FeatureRecord], tracks: [Track], links: [MyMusicTrackLink]) throws -> [FeatureRecord] {
        let existing = try load()
        let resolver = FeatureResolver(tracks: tracks, links: links)
        var records = existing
        var keys: [String: Int] = [:]
        var local: [UUID: Int] = [:]
        for (i, r) in records.enumerated() {
            keys[r.identityKey] = i
            if let id = r.homeStereoTrackID ?? resolver.resolve(r).localTrackID { local[id] = i }
        }
        let linkIndex = Dictionary(grouping: links, by: \.homeStereoTrackID)
        for var r in incoming {
            try FeatureCodec.validate(r)
            let resolved = resolver.resolve(r).localTrackID
            r.homeStereoTrackID = r.homeStereoTrackID ?? resolved
            if r.trackID == nil, let resolved, let matches = linkIndex[resolved], matches.count == 1 { r.trackID = matches[0].myMusicTrackID }
            let index = keys[r.identityKey] ?? resolved.flatMap { local[$0] }
            if let i = index {
                let previous = records[i]
                if r.analysisVersion > previous.analysisVersion || (r.analysisVersion == previous.analysisVersion && r.analyzedAt >= previous.analyzedAt) {
                    r.id = previous.id; r.trackID = r.trackID ?? previous.trackID
                    if r.analysisVersion == previous.analysisVersion && r.analyzedAt == previous.analyzedAt {
                        r.modelDescription = r.modelDescription ?? previous.modelDescription
                        r.analysisProfile = r.analysisProfile ?? previous.analysisProfile
                        r.loudnessSource = r.loudnessSource ?? previous.loudnessSource
                    }
                    if !r.features.hasLoudness, previous.features.hasLoudness {
                        r.loudnessSource = previous.loudnessSource ?? FeatureOrigin(record: previous)
                    }
                    r.features = r.features.preservingLoudness(from: previous.features)
                    records[i] = r
                } else {
                    if !previous.features.hasLoudness, r.features.hasLoudness {
                        records[i].loudnessSource = r.loudnessSource ?? FeatureOrigin(record: r)
                    }
                    records[i].features = previous.features.preservingLoudness(from: r.features)
                }
                keys[r.identityKey] = i
                if let resolved { local[resolved] = i }
            } else {
                let i = records.count; records.append(r); keys[r.identityKey] = i
                if let resolved { local[resolved] = i }
            }
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FeatureCodec.encoder().encode(Archive(version: 1, records: records)).write(to: url, options: .atomic)
        return records
    }
}
