import Foundation

public struct Track: Identifiable, Hashable, Sendable {
    public let id: URL
    public let url: URL
    public let title: String
    public let artist: String?
    public let album: String?
    public let duration: TimeInterval

    public init(
        url: URL,
        title: String,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval = 0
    ) {
        self.id = url.standardizedFileURL
        self.url = url.standardizedFileURL
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration.isFinite ? max(0, duration) : 0
    }
}

public enum SidebarDestination: String, CaseIterable, Identifiable, Sendable {
    case songs
    case settings

    public var id: Self { self }
}

public enum PlaybackState: Equatable, Sendable {
    case stopped
    case playing
    case paused
}

public enum UserFacingError: LocalizedError, Equatable, Sendable {
    case folderAccessLost
    case folderUnavailable
    case noPlayableAudio
    case playbackFailed(String)
    case scanFailed(String)

    public var errorDescription: String? {
        switch self {
        case .folderAccessLost:
            return "音楽フォルダへのアクセス権が失われました。フォルダをもう一度選択してください。"
        case .folderUnavailable:
            return "選択した音楽フォルダが見つかりません。移動または削除されていないか確認してください。"
        case .noPlayableAudio:
            return "このフォルダに再生可能な音源が見つかりませんでした。"
        case let .playbackFailed(message):
            return "再生できませんでした。ファイルが存在し、読み取り可能か確認してください。\n\(message)"
        case let .scanFailed(message):
            return "音楽フォルダを読み込めませんでした。\n\(message)"
        }
    }
}
