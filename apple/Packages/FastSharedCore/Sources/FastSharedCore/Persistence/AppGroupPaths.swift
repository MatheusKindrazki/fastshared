import Foundation

public enum AppGroupPaths {
    public static let fallbackGroupIdentifier = "group.dev.kindrazki.fastshared"

    public static var groupIdentifier: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "APP_GROUP_IDENTIFIER") as? String, !value.isEmpty {
            return value
        }
        return fallbackGroupIdentifier
    }

    public static func containerURL() throws -> URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            throw AppGroupError.missingContainer(groupIdentifier)
        }
        return url
    }

    public static func stagingDirectory() throws -> URL {
        let base = try containerURL().appendingPathComponent("staging", isDirectory: true)
        try ensureDirectory(at: base)
        return base
    }

    public static func thumbnailsDirectory() throws -> URL {
        let base = try containerURL().appendingPathComponent("thumbnails", isDirectory: true)
        try ensureDirectory(at: base)
        return base
    }

    public static func databaseURL() throws -> URL {
        try containerURL().appendingPathComponent("FastShared.sqlite")
    }

    private static func ensureDirectory(at url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

public enum AppGroupError: Error, Sendable {
    case missingContainer(String)
}
