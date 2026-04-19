import Foundation
import CloudKit

/// Field-name + record-type constants for the `ShareLinkRecord` CKRecord, plus
/// SwiftData ⇄ CKRecord bridging.
///
/// Exactly one source of truth for both the engine's record-zone changes and
/// test fixtures. If you rename a field here, the CloudKit dev dashboard needs
/// the matching schema change.
public enum ShareLinkRecord {
    /// CloudKit record type. Matches the schema registered in the iCloud
    /// container's private DB.
    public static let recordType = "ShareLinkRecord"

    /// CloudKit container identifier — MUST match the entitlement.
    public static let containerID = "iCloud.dev.kindrazki.fastshared"

    /// Dedicated custom zone for FastShared records. Using a named zone (rather
    /// than the default zone) lets us wholesale-delete sync state without
    /// affecting other CloudKit data in the user's private DB.
    public static let zoneName = "FastSharedZone"

    /// CKRecord field names.
    public enum Field {
        public static let token = "token"
        public static let assetId = "assetId"
        public static let filename = "filename"
        public static let contentType = "contentType"
        public static let fileSizeBytes = "fileSizeBytes"
        public static let createdAt = "createdAt"
        public static let expiresAt = "expiresAt"
        public static let deleteAfter = "deleteAfter"
        public static let linkStatus = "linkStatus"
        public static let retentionPolicy = "retentionPolicy"
        public static let revokedAt = "revokedAt"
        public static let deviceId = "deviceId"
        public static let shortURLString = "shortURLString"
    }

    /// Stable record name derived from the share-link token.
    /// WHY: Using the token keeps record names deterministic across devices
    /// without an extra UUID — last-write-wins with `modificationDate` handles
    /// concurrent edits.
    public static func recordID(token: String, in zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: token, zoneID: zoneID)
    }
}

// MARK: - ShareLinkEntity ⇄ CKRecord

public extension ShareLinkEntity {
    /// Projects a local `ShareLinkEntity` into a `CKRecord` ready for
    /// `CKSyncEngine.State.add(pendingRecordZoneChanges:)`.
    func toCKRecord(deviceId: UUID, in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = ShareLinkRecord.recordID(token: token, in: zoneID)
        let record = CKRecord(recordType: ShareLinkRecord.recordType, recordID: recordID)
        record[ShareLinkRecord.Field.token] = token as CKRecordValue
        record[ShareLinkRecord.Field.assetId] = assetId.uuidString as CKRecordValue
        record[ShareLinkRecord.Field.filename] = (originalFilename ?? "") as CKRecordValue
        record[ShareLinkRecord.Field.contentType] = contentType as CKRecordValue
        record[ShareLinkRecord.Field.fileSizeBytes] = sizeBytes as CKRecordValue
        record[ShareLinkRecord.Field.createdAt] = createdAt as CKRecordValue
        record[ShareLinkRecord.Field.expiresAt] = expiresAt as CKRecordValue
        record[ShareLinkRecord.Field.deleteAfter] = deleteAfter as CKRecordValue
        record[ShareLinkRecord.Field.linkStatus] = linkStatus as CKRecordValue
        record[ShareLinkRecord.Field.retentionPolicy] = retentionPolicy as CKRecordValue
        if let revokedAt { record[ShareLinkRecord.Field.revokedAt] = revokedAt as CKRecordValue }
        record[ShareLinkRecord.Field.deviceId] = deviceId.uuidString as CKRecordValue
        record[ShareLinkRecord.Field.shortURLString] = shortURLString as CKRecordValue
        return record
    }
}

public enum ShareLinkRecordDecodeError: Error, Sendable, Equatable {
    case missingField(String)
    case invalidField(String, reason: String)
}

public extension CKRecord {
    /// Decodes this record (assumed to be `ShareLinkRecord`) into a transient
    /// `ShareLinkEntity` suitable for upsert into SwiftData.
    ///
    /// Throws `ShareLinkRecordDecodeError` when mandatory fields are missing
    /// or malformed — the engine skips those records rather than crashing.
    func asShareLinkEntity() throws -> ShareLinkEntity {
        func string(_ key: String) throws -> String {
            guard let raw = self[key] as? String else {
                throw ShareLinkRecordDecodeError.missingField(key)
            }
            return raw
        }
        func date(_ key: String) throws -> Date {
            guard let raw = self[key] as? Date else {
                throw ShareLinkRecordDecodeError.missingField(key)
            }
            return raw
        }
        func int64(_ key: String) throws -> Int64 {
            if let raw = self[key] as? Int64 { return raw }
            if let raw = self[key] as? NSNumber { return raw.int64Value }
            throw ShareLinkRecordDecodeError.missingField(key)
        }

        let token = try string(ShareLinkRecord.Field.token)
        let assetIdString = try string(ShareLinkRecord.Field.assetId)
        guard let assetId = UUID(uuidString: assetIdString) else {
            throw ShareLinkRecordDecodeError.invalidField(ShareLinkRecord.Field.assetId, reason: "not a UUID: \(assetIdString)")
        }
        let shortURLString = try string(ShareLinkRecord.Field.shortURLString)
        let filenameRaw = self[ShareLinkRecord.Field.filename] as? String
        let filename = (filenameRaw?.isEmpty ?? true) ? nil : filenameRaw
        let contentType = try string(ShareLinkRecord.Field.contentType)
        let size = try int64(ShareLinkRecord.Field.fileSizeBytes)
        let createdAt = try date(ShareLinkRecord.Field.createdAt)
        let expiresAt = try date(ShareLinkRecord.Field.expiresAt)
        let deleteAfter = try date(ShareLinkRecord.Field.deleteAfter)
        let linkStatus = try string(ShareLinkRecord.Field.linkStatus)
        let retentionPolicy = try string(ShareLinkRecord.Field.retentionPolicy)
        let revokedAt = self[ShareLinkRecord.Field.revokedAt] as? Date

        return ShareLinkEntity(token: token,
                               assetId: assetId,
                               shortURLString: shortURLString,
                               createdAt: createdAt,
                               visibility: .unlisted,
                               expiresAt: expiresAt,
                               deleteAfter: deleteAfter,
                               linkStatus: linkStatus,
                               retentionPolicy: retentionPolicy,
                               revokedAt: revokedAt,
                               contentType: contentType,
                               sizeBytes: size,
                               originalFilename: filename)
    }
}
