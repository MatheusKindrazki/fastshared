import Foundation
import CloudKit

/// Field-name + record-type constants for the `DeviceRecord` CKRecord, plus
/// SwiftData ⇄ CKRecord bridging.
///
/// Each install publishes ONE `DeviceRecord` describing itself (name, platform,
/// last-seen). Every device fetches all of them so the sidebar can list the
/// user's other devices. Lives in the SAME `FastSharedZone` as `ShareLinkRecord`
/// — the engine discriminates the two by record name (see `recordName(...)`).
public enum DeviceRecord {
    public static let recordType = "DeviceRecord"

    /// Record names are prefixed so `CKSyncEngineKernel.buildRecord(for:)` — which
    /// only receives a `CKRecord.ID` — can tell a device record apart from a
    /// share-link record (whose name is a 22-char token) without a lookup.
    public static let recordNamePrefix = "device:"

    public enum Field {
        public static let deviceId = "deviceId"
        public static let name = "name"
        public static let platform = "platform"
        public static let lastSeenAt = "lastSeenAt"
        public static let appVersion = "appVersion"
    }

    /// Deterministic record name per install so re-publishes overwrite (rather
    /// than duplicate) the device's own record. Last-write-wins on
    /// `modificationDate` handles the periodic last-seen refresh.
    public static func recordName(deviceId: UUID) -> String {
        recordNamePrefix + deviceId.uuidString
    }

    public static func recordID(deviceId: UUID, in zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName(deviceId: deviceId), zoneID: zoneID)
    }

    /// True when a fetched record ID belongs to a device record. Used by the
    /// engine to route `buildRecord`/`applyFetched` without a record-type read.
    public static func isDeviceRecordName(_ name: String) -> Bool {
        name.hasPrefix(recordNamePrefix)
    }
}

// MARK: - DeviceEntity ⇄ CKRecord

public extension DeviceEntity {
    /// Projects a local `DeviceEntity` into a `CKRecord` ready for
    /// `CKSyncEngine.State.add(pendingRecordZoneChanges:)`.
    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = DeviceRecord.recordID(deviceId: deviceId, in: zoneID)
        let record = CKRecord(recordType: DeviceRecord.recordType, recordID: recordID)
        record[DeviceRecord.Field.deviceId] = deviceId.uuidString as CKRecordValue
        record[DeviceRecord.Field.name] = name as CKRecordValue
        record[DeviceRecord.Field.platform] = platform as CKRecordValue
        record[DeviceRecord.Field.lastSeenAt] = lastSeenAt as CKRecordValue
        record[DeviceRecord.Field.appVersion] = appVersion as CKRecordValue
        return record
    }
}

public enum DeviceRecordDecodeError: Error, Sendable, Equatable {
    case missingField(String)
    case invalidField(String, reason: String)
}

public extension CKRecord {
    /// Decodes this record (assumed to be `DeviceRecord`) into a transient
    /// `DeviceEntity` suitable for upsert into SwiftData. Throws when the
    /// device id is missing/malformed; tolerant on the cosmetic fields.
    func asDeviceEntity() throws -> DeviceEntity {
        guard let deviceIdString = self[DeviceRecord.Field.deviceId] as? String else {
            throw DeviceRecordDecodeError.missingField(DeviceRecord.Field.deviceId)
        }
        guard let deviceId = UUID(uuidString: deviceIdString) else {
            throw DeviceRecordDecodeError.invalidField(
                DeviceRecord.Field.deviceId, reason: "not a UUID: \(deviceIdString)")
        }
        let name = self[DeviceRecord.Field.name] as? String ?? ""
        let platform = self[DeviceRecord.Field.platform] as? String ?? ""
        let lastSeenAt = self[DeviceRecord.Field.lastSeenAt] as? Date ?? .distantPast
        let appVersion = self[DeviceRecord.Field.appVersion] as? String ?? ""

        return DeviceEntity(deviceId: deviceId,
                            name: name,
                            platform: platform,
                            lastSeenAt: lastSeenAt,
                            appVersion: appVersion)
    }
}
