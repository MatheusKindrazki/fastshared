import Foundation
import SwiftData

public enum SchemaVersion: Int, Sendable, CaseIterable {
    case v1 = 1
    // WHY: .v2 - added expires_at / delete_after / link_status / retention_policy / token rename (ephemeral-first lifecycle).
    case v2 = 2
}

public struct SchemaMigrator: Sendable {
    public init() {}

    public func migrate(from oldVersion: SchemaVersion, to newVersion: SchemaVersion, in container: ModelContainer) throws {
        // WHY: MVP assumes no existing users yet; migration path exists as a structural placeholder
        // so future releases have a single known call site when we do ship a non-trivial migration.
        guard oldVersion != newVersion else { return }
        fatalError("TODO: implement migration from \(oldVersion) to \(newVersion)")
    }
}
