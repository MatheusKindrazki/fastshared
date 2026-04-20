import Foundation

public struct StagedScreenshot: Sendable, Equatable {
    public let url: URL
    public let sizeBytes: Int64
    public let capturedAt: Date?
    public let filename: String

    public init(url: URL, sizeBytes: Int64, capturedAt: Date?, filename: String) {
        self.url = url
        self.sizeBytes = sizeBytes
        self.capturedAt = capturedAt
        self.filename = filename
    }
}

public enum LastScreenshotError: Error, LocalizedError, Sendable {
    case authorizationDenied
    case noScreenshotFound
    case export(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "FastShared needs access to your most recent screenshot. Grant Photos permission in Settings and try again."
        case .noScreenshotFound:
            return "No screenshots yet — take one and try again."
        case .export(let underlying):
            return "Couldn't read that screenshot: \(underlying)"
        }
    }
}

#if canImport(Photos) && os(iOS)
import Photos

public enum LastScreenshotFetcher {
    /// Returns the newest screenshot, PNG-written into the staging directory and ready to feed
    /// into `UploadService.enqueue(...)`.
    public static func staged() async throws -> StagedScreenshot {
        try await ensureAuthorization()

        guard let asset = newestScreenshotAsset() else {
            throw LastScreenshotError.noScreenshotFound
        }

        let (data, _) = try await loadImageData(for: asset)
        let pngData = try convertToPNG(data: data)

        let stagingRoot = try AppGroupPaths.stagingDirectory()
        let destination = stagingRoot.appendingPathComponent(UUID().uuidString + ".png")
        do {
            try pngData.write(to: destination, options: .atomic)
        } catch {
            throw LastScreenshotError.export(underlying: error.localizedDescription)
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: destination.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? Int64(pngData.count)

        return StagedScreenshot(
            url: destination,
            sizeBytes: size,
            capturedAt: asset.creationDate,
            filename: defaultFilename(for: asset.creationDate ?? Date())
        )
    }

    // MARK: - Authorization

    // WHY: `.readWrite` is required — PHPhotoLibrary has exactly two access
    // levels, `.addOnly` (write-only, no fetchAssets) and `.readWrite`. We
    // need to *read* the newest screenshot asset, so `.readWrite` is the
    // minimum viable scope. `.limited` still grants read access to the
    // user's selection, so we treat it as success too.
    private static func ensureAuthorization() async throws {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch current {
        case .authorized, .limited:
            return
        case .denied, .restricted:
            throw LastScreenshotError.authorizationDenied
        case .notDetermined:
            let next = await withCheckedContinuation { (continuation: CheckedContinuation<PHAuthorizationStatus, Never>) in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                    continuation.resume(returning: status)
                }
            }
            switch next {
            case .authorized, .limited: return
            default: throw LastScreenshotError.authorizationDenied
            }
        @unknown default:
            throw LastScreenshotError.authorizationDenied
        }
    }

    // MARK: - Asset lookup

    private static func newestScreenshotAsset() -> PHAsset? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaSubtype & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        let result = PHAsset.fetchAssets(with: .image, options: options)
        return result.firstObject
    }

    // MARK: - Export

    private static func loadImageData(for asset: PHAsset) async throws -> (Data, String?) {
        let options = PHImageRequestOptions()
        options.version = .current
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false

        return try await withCheckedThrowingContinuation { continuation in
            // WHY: PhotoKit calls back on an arbitrary queue. The only mutable state we touch is the
            // continuation, which is single-shot by contract — safe without additional locking.
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, info in
                if let error = info?[PHImageErrorKey] as? NSError {
                    continuation.resume(throwing: LastScreenshotError.export(underlying: error.localizedDescription))
                    return
                }
                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    continuation.resume(throwing: LastScreenshotError.export(underlying: "cancelled"))
                    return
                }
                guard let data else {
                    continuation.resume(throwing: LastScreenshotError.export(underlying: "empty image data"))
                    return
                }
                continuation.resume(returning: (data, uti))
            }
        }
    }

    private static func convertToPNG(data: Data) throws -> Data {
        // WHY: screenshots on iOS are already PNGs, but PhotoKit can hand back HEIC-encoded
        // captures too (edited screenshots, shared-album re-imports). Re-encode to guarantee PNG.
        #if canImport(UIKit)
        if let image = UIImage(data: data), let png = image.pngData() {
            return png
        }
        #endif
        return data
    }

    // MARK: - Naming

    private static func defaultFilename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return "Screenshot \(formatter.string(from: date)).png"
    }
}

#if canImport(UIKit)
import UIKit
#endif

#else

public enum LastScreenshotFetcher {
    public static func staged() async throws -> StagedScreenshot {
        // WHY: macOS builds don't ship the intent / banner surface. We still compile the type so
        // FastSharedCore stays one library across platforms — consumers gate calls with #if os(iOS).
        throw LastScreenshotError.noScreenshotFound
    }
}

#endif
