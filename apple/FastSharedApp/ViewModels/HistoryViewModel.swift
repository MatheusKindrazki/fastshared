import Foundation
import Observation
import SwiftData
import FastSharedCore

@Observable
@MainActor
final class HistoryViewModel {
    var isRefreshing: Bool = false
    var lastError: String?

    private let apiClient: APIClientProtocol
    private let orchestrator: UploadOrchestrator?
    private let store: SwiftDataStore

    init(apiClient: APIClientProtocol,
         orchestrator: UploadOrchestrator?,
         store: SwiftDataStore = .shared) {
        self.apiClient = apiClient
        self.orchestrator = orchestrator
        self.store = store
    }

    func refresh(visibleLinks: [ShareLinkEntity] = []) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let page = try await apiClient.fetchHistory(cursor: nil, limit: 50)
            await upsert(page.items)
        } catch {
            lastError = error.localizedDescription
        }
        // WHY: in the same pass, flip any visibly-expired rows so the UI reflects reality even before
        // the server next syncs the link status.
        if let orchestrator {
            let expiredTokens = visibleLinks
                .filter { $0.expiresAt <= Date() && $0.linkStatus == LinkStatus.active.rawValue }
                .map { $0.token }
            for token in expiredTokens {
                await orchestrator.lazyMarkExpiredIfNeeded(token: token)
            }
        }
    }

    func revoke(_ entity: ShareLinkEntity) async {
        // WHY: copy the token before awaiting so we never send the @Model reference type across actor hops.
        let token = entity.token
        guard let orchestrator else { return }
        do {
            try await orchestrator.revoke(token: token)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func upsert(_ items: [HistoryItem]) async {
        let context = await store.mainContext()
        for item in items {
            let token = item.token
            let descriptor = FetchDescriptor<ShareLinkEntity>(predicate: #Predicate { $0.token == token })
            do {
                if let existing = try context.fetch(descriptor).first {
                    existing.assetId = item.assetId
                    existing.shortURLString = item.shortUrl.absoluteString
                    existing.expiresAt = item.expiresAt
                    existing.deleteAfter = item.deleteAfter
                    existing.linkStatus = item.linkStatus
                    existing.retentionPolicy = item.retentionPolicy
                    existing.contentType = item.contentType
                    existing.sizeBytes = item.sizeBytes
                    existing.originalFilename = item.originalFilename
                    existing.accessCount = item.accessCount
                } else {
                    let entity = ShareLinkEntity(token: item.token,
                                                 assetId: item.assetId,
                                                 shortURLString: item.shortUrl.absoluteString,
                                                 createdAt: item.createdAt,
                                                 visibility: .unlisted,
                                                 expiresAt: item.expiresAt,
                                                 deleteAfter: item.deleteAfter,
                                                 linkStatus: item.linkStatus,
                                                 retentionPolicy: item.retentionPolicy,
                                                 accessCount: item.accessCount,
                                                 contentType: item.contentType,
                                                 sizeBytes: item.sizeBytes,
                                                 originalFilename: item.originalFilename)
                    context.insert(entity)
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
        try? context.save()
    }
}
