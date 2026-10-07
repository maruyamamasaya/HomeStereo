import Foundation

public enum PlaylistTagRules {
    public static let maximumTagCount = 20
    public static let maximumTagLength = 40

    public static func comparisonKey(for value: String) -> String {
        value.precomposedStringWithCanonicalMapping.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    /// Match MyMusic's tag limits, while rejecting over-limit input instead of silently truncating it.
    public static func validatedTags(_ values: [String]) throws -> [String] {
        var keys = Set<String>()
        var result: [String] = []
        for value in values {
            let tag = value.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }.joined(separator: " ")
            guard !tag.isEmpty else { continue }
            guard tag.count <= maximumTagLength else {
                throw UserFacingError.persistenceFailed("タグは1個につき40文字以内にしてください。")
            }
            if keys.insert(comparisonKey(for: tag)).inserted { result.append(tag) }
        }
        guard result.count <= maximumTagCount else {
            throw UserFacingError.persistenceFailed("タグはプレイリストごとに20個まで設定できます。")
        }
        return result
    }
}
