import Foundation
import OSLog

public protocol BackgroundSessionScheduling: AnyObject, Sendable {
    func scheduleUpload(job: UploadJob, upload: UploadInstruction, fileURL: URL) throws
    func attach(completionHandler: @escaping () -> Void, identifier: String)
    func bind(orchestrator: UploadOrchestrator, store: SwiftDataStore)
}

public final class BackgroundSessionManager: NSObject,
                                              URLSessionDelegate,
                                              URLSessionTaskDelegate,
                                              URLSessionDataDelegate,
                                              BackgroundSessionScheduling,
                                              @unchecked Sendable {
    public static let shared = BackgroundSessionManager()

    private let log = Logger(subsystem: Log.subsystem, category: "upload")
    private let queue = DispatchQueue(label: "dev.kindrazki.fastshared.background.session")
    private var orchestrator: UploadOrchestrator?
    private var repository: UploadJobRepository?
    private var completionHandler: (() -> Void)?
    private var _session: URLSession?

    private var session: URLSession {
        if let session = _session { return session }
        let configuration = URLSessionConfiguration.background(withIdentifier: AppGroupConfig.backgroundSessionIdentifier)
        configuration.sharedContainerIdentifier = AppGroupConfig.identifier
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.allowsCellularAccess = true
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        _session = session
        return session
    }

    public func bind(orchestrator: UploadOrchestrator, store: SwiftDataStore) {
        queue.sync {
            self.orchestrator = orchestrator
            self.repository = UploadJobRepository(store: store)
        }
    }

    public func attach(completionHandler: @escaping () -> Void, identifier: String) {
        guard identifier == AppGroupConfig.backgroundSessionIdentifier else { return }
        queue.sync { self.completionHandler = completionHandler }
        _ = session
    }

    public func scheduleUpload(job: UploadJob, upload: UploadInstruction, fileURL: URL) throws {
        var request = URLRequest(url: upload.url)
        request.httpMethod = upload.method.uppercased()
        for (key, value) in upload.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue(job.contentType, forHTTPHeaderField: "Content-Type")
        }
        let task = session.uploadTask(with: request, fromFile: fileURL)
        task.taskDescription = job.clientJobId.uuidString
        task.countOfBytesClientExpectsToSend = job.sizeBytes
        log.info("scheduling upload for \(job.clientJobId.uuidString, privacy: .public)")
        task.resume()
    }

    // MARK: URLSession delegates

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didSendBodyData bytesSent: Int64,
                           totalBytesSent: Int64,
                           totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0,
              let raw = task.taskDescription,
              let clientJobId = UUID(uuidString: raw) else { return }
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        let repo = queue.sync { repository }
        guard let repo else { return }
        Task.detached(priority: .utility) {
            try? await repo.updateProgress(clientJobId: clientJobId, progress: progress)
        }
    }

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didCompleteWithError error: Error?) {
        guard let raw = task.taskDescription,
              let clientJobId = UUID(uuidString: raw) else { return }
        let response = task.response as? HTTPURLResponse
        let orchestrator = queue.sync { self.orchestrator }
        guard let orchestrator else { return }
        Task.detached(priority: .userInitiated) {
            if let error {
                await orchestrator.handleTaskFailure(clientJobId: clientJobId, error: error)
            } else if let response, (200..<300).contains(response.statusCode) {
                let etag = response.value(forHTTPHeaderField: "ETag")
                await orchestrator.handleTaskSuccess(clientJobId: clientJobId, etag: etag)
            } else {
                let status = response?.statusCode ?? 0
                await orchestrator.handleTaskFailure(clientJobId: clientJobId,
                                                     error: APIError.http(status: status, problem: nil))
            }
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = queue.sync { () -> (() -> Void)? in
            let h = self.completionHandler
            self.completionHandler = nil
            return h
        }
        DispatchQueue.main.async {
            handler?()
        }
    }
}
