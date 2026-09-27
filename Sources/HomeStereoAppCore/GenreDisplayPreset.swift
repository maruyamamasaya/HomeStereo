import Foundation

public struct GenreDisplayPreset: Identifiable, Equatable, Codable, Sendable {
    public static let unassignedGenreID = "maruyama.MyMusic.genre.unassigned"
    public static let fixedGenreNames: Set<String> = ["作業用BGM", "ハイレゾ"]

    public let id: UUID
    public var name: String
    public var enabledGenreNames: [String]
    public var includesUnassignedGenreSetting: Bool?

    public init(
        id: UUID = UUID(), name: String, enabledGenreNames: [String],
        includesUnassignedGenreSetting: Bool? = true
    ) {
        self.id = id
        self.name = name
        self.enabledGenreNames = enabledGenreNames
        self.includesUnassignedGenreSetting = includesUnassignedGenreSetting
    }

    public var includesUnassignedGenre: Bool {
        if includesUnassignedGenreSetting != true { return true }
        return enabledGenreNames.contains(Self.unassignedGenreID)
    }

    public var displayGenreNames: [String] {
        enabledGenreNames.filter { $0 != Self.unassignedGenreID }
    }
}

public struct GenreDisplayPresetDocument: Codable, Equatable, Sendable {
    public static let kind = "mymusic.genre-display-presets"
    public static let version = 1
    public let kind: String
    public let version: Int
    public let presets: [GenreDisplayPreset]

    public init(presets: [GenreDisplayPreset]) {
        self.kind = Self.kind; self.version = Self.version; self.presets = presets
    }
}

public enum GenreDisplayPresetError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case let .invalid(message): message }
    }
}

public enum GenreDisplayPresetCodec {
    public static let fileName = "MyMusic-Genre-Display-Presets.json"

    public static func decode(_ data: Data) throws -> GenreDisplayPresetDocument {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GenreDisplayPresetError.invalid("JSONのルートがobjectではありません。")
        }
        try requireExactKeys(Set(root.keys), allowed: ["kind", "version", "presets"], context: "文書")
        guard root["kind"] as? String == GenreDisplayPresetDocument.kind,
              let version = root["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.intValue == 1,
              let rawPresets = root["presets"] as? [[String: Any]] else {
            throw GenreDisplayPresetError.invalid("kind、version、presetsが正しくありません。")
        }
        for (index, value) in rawPresets.enumerated() {
            try requireExactKeys(
                Set(value.keys),
                allowed: ["id", "name", "enabledGenreNames", "includesUnassignedGenreSetting"],
                context: "presets[\(index)]"
            )
            guard value["id"] is String, value["name"] is String,
                  let genres = value["enabledGenreNames"] as? [Any], genres.allSatisfy({ $0 is String }) else {
                throw GenreDisplayPresetError.invalid("presets[\(index)]の型が正しくありません。")
            }
            if let setting = value["includesUnassignedGenreSetting"], !(setting is Bool) {
                throw GenreDisplayPresetError.invalid("presets[\(index)]の未分類設定が真偽値ではありません。")
            }
        }
        let document = try JSONDecoder().decode(GenreDisplayPresetDocument.self, from: data)
        try validate(document)
        return document
    }

    public static func encode(_ presets: [GenreDisplayPreset]) throws -> Data {
        let document = GenreDisplayPresetDocument(presets: presets)
        try validate(document)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    public static func validate(_ document: GenreDisplayPresetDocument) throws {
        guard document.kind == GenreDisplayPresetDocument.kind,
              document.version == GenreDisplayPresetDocument.version else {
            throw GenreDisplayPresetError.invalid("対応していないジャンルプリセット文書です。")
        }
        var ids = Set<UUID>(), names = Set<String>()
        for preset in document.presets {
            guard ids.insert(preset.id).inserted else {
                throw GenreDisplayPresetError.invalid("プリセットIDが重複しています。")
            }
            let name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw GenreDisplayPresetError.invalid("プリセット名が空です。") }
            guard names.insert(normalized(name)).inserted else {
                throw GenreDisplayPresetError.invalid("プリセット名「\(name)」が重複しています。")
            }
            var genres = Set<String>()
            for rawGenre in preset.enabledGenreNames {
                let genre = rawGenre.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !genre.isEmpty else { throw GenreDisplayPresetError.invalid("空のジャンル名は保存できません。") }
                guard genres.insert(normalized(genre)).inserted else {
                    throw GenreDisplayPresetError.invalid("「\(name)」のジャンルが重複しています。")
                }
            }
        }
    }

    public static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func requireExactKeys(_ actual: Set<String>, allowed: Set<String>, context: String) throws {
        guard actual.isSubset(of: allowed) else {
            throw GenreDisplayPresetError.invalid("\(context)に未知のfieldがあります。")
        }
        guard context != "文書" || actual == allowed else {
            throw GenreDisplayPresetError.invalid("文書に必要なfieldがありません。")
        }
    }
}

public protocol GenreDisplayPresetPersisting: Sendable {
    func loadGenreDisplayPresets() async throws -> [GenreDisplayPreset]
    func replaceGenreDisplayPresets(_ presets: [GenreDisplayPreset]) async throws
}
