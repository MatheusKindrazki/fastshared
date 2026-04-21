import Foundation
import CryptoKit

public enum SHA256Streamer {
    public static func hash(fileAt url: URL) async throws -> String {
        try await hash(fileAt: url, progress: nil)
    }

    /// Progress callback fires after each 1 MB chunk with cumulative bytes hashed.
    /// WHY: share-ext needs a "Preparing file…" determinate bar so users don't
    /// stare at a frozen 0% while SHA-256 chews through a 125 MB video.
    public static func hash(
        fileAt url: URL,
        progress: (@Sendable (_ bytesHashed: Int64) -> Void)?
    ) async throws -> String {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            var total: Int64 = 0
            while true {
                let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
                total &+= Int64(chunk.count)
                progress?(total)
            }
            let digest = hasher.finalize()
            return digest.map { String(format: "%02x", $0) }.joined()
        }.value
    }
}
