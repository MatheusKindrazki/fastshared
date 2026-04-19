import Foundation
import SwiftData

public actor ShareLinkService {
    private let store: SwiftDataStore

    public init(store: SwiftDataStore) {
        self.store = store
    }

    public func list() throws -> [ShareLinkEntity] {
        let context = store.backgroundContext()
        let descriptor = FetchDescriptor<ShareLinkEntity>(sortBy: [SortDescriptor(\ShareLinkEntity.createdAt, order: .reverse)])
        return try context.fetch(descriptor)
    }

    public func find(token: String) throws -> ShareLinkEntity? {
        let context = store.backgroundContext()
        let descriptor = FetchDescriptor<ShareLinkEntity>(predicate: #Predicate { $0.token == token })
        return try context.fetch(descriptor).first
    }

    public func find(assetId: UUID) throws -> ShareLinkEntity? {
        let context = store.backgroundContext()
        let descriptor = FetchDescriptor<ShareLinkEntity>(predicate: #Predicate { $0.assetId == assetId })
        return try context.fetch(descriptor).first
    }

    public func delete(token: String) throws {
        let context = store.backgroundContext()
        let descriptor = FetchDescriptor<ShareLinkEntity>(predicate: #Predicate { $0.token == token })
        for entity in try context.fetch(descriptor) {
            context.delete(entity)
        }
        try context.save()
    }

    public func setFavorite(token: String, favorite: Bool) throws {
        let context = store.backgroundContext()
        let descriptor = FetchDescriptor<ShareLinkEntity>(predicate: #Predicate { $0.token == token })
        guard let entity = try context.fetch(descriptor).first else { return }
        entity.isFavorited = favorite
        try context.save()
    }
}
