import Foundation
import CryptoKit

enum PlaylistImportArchive {
    static func preserve(_ data: Data, prefix: String, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let url = directory.appendingPathComponent("\(prefix)-\(digest).json")
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
        }
        guard try Data(contentsOf: url) == data else { throw CocoaError(.fileReadCorruptFile) }
    }
}
