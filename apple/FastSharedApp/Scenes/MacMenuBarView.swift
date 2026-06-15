#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import FastSharedCore
import UniformTypeIdentifiers
import OSLog

extension Notification.Name {
    /// Posted by the tray Settings button to open Settings as a sheet
    /// inside the main LibraryView window instead of a floating window.
    static let openSettings = Notification.Name("dev.kindrazki.fastshared.openSettings")
}

/// macOS menu bar popover — 360pt wide, auto height.
///
/// Shows the brand lockup header, a drag-and-drop upload zone, and a "recent"
/// list of the last 3 shares with urgency dots and countdown labels.
///
/// Wired up as a `MenuBarExtra(.window)` in `FastSharedApp.swift`.
struct MacMenuBarView: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(\.uploadService) private var uploadService
    @Environment(\.clipboard) private var clipboard
    @Environment(\.subscriptionStore) private var subscriptionStore
    @Environment(\.paywallCoordinator) private var paywallCoordinator
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: [SortDescriptor(\ShareLinkEntity.createdAt, order: .reverse)])
    private var allShares: [ShareLinkEntity]

    @State private var isDragTargeted: Bool = false

    // MARK: - Adaptive palette — HIG semantic (NSColor bridges).

    private var groundColor: Color { Color(nsColor: .windowBackgroundColor) }
    private var canvasColor: Color { Color(nsColor: .controlBackgroundColor) }
    private var surface0Color: Color { Color(nsColor: .underPageBackgroundColor) }
    private var textColor: Color { Color(nsColor: .labelColor) }
    private var textDimColor: Color { Color(nsColor: .secondaryLabelColor) }
    private var textFaintColor: Color { Color(nsColor: .tertiaryLabelColor) }
    private var lineColor: Color { Color(nsColor: .separatorColor) }

    // MARK: - Derived data

    private var now: Date { Date() }

    private var recentShares: [ShareLinkEntity] {
        allShares
            .filter { $0.linkStatus == LinkStatus.active.rawValue && $0.expiresAt > now }
            .prefix(3)
            .map { $0 }
    }

    private var activeUpload: UploadProgressMonitor.ActiveUpload? {
        UploadProgressMonitor.shared.current
    }

    private var dropZoneAccent: Color {
        switch activeUpload?.phase {
        case .completed:
            return BrandPalette.successGreen
        case .failed:
            return BrandPalette.accentFade
        case .uploading, nil:
            return BrandPalette.accentHot
        }
    }

    private var dropZoneIsActive: Bool {
        isDragTargeted || activeUpload != nil
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            lineColor.frame(height: 1)
            dropZoneCard
                .padding(12)
            recentBlock
            footer
        }
        .frame(width: 360)
        .background(groundColor)
        .animation(.easeInOut(duration: 0.18), value: activeUpload?.phase)
        .animation(.easeInOut(duration: 0.18), value: activeUpload?.progress)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            BrandLockup(markSize: 22, textSize: 15)

            Spacer()

            Text("⌘⇧S")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(textDimColor)
                .tracking(0.05 * 11)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(surface0Color)
                )
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }

    // MARK: - Drop zone card

    private var dropZoneCard: some View {
        VStack(spacing: 4) {
            dropZoneIcon
                .padding(.bottom, 4)

            Text(dropZoneTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(dropZoneSubtitle)
                .font(.system(size: 11))
                .foregroundStyle(textDimColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(dropZoneAccent.opacity(dropZoneIsActive ? 0.14 : 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            dropZoneAccent.opacity(dropZoneIsActive ? 0.50 : 0.25),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5])
                        )
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isDragTargeted)
        // NOTE: Drop is handled by PopoverDropOverlay (AppKit native) instead
        // of SwiftUI .onDrop because NSItemProvider on macOS cannot reliably
        // coerce Finder drags to NSURL. The overlay forwards drops directly
        // via NSPasteboard which works with every Finder drag type.
        .onChange(of: isDragTargeted) { _, targeted in
            // Visual feedback only — the actual drop is caught by the overlay.
            isDragTargeted = targeted
        }
    }

    @ViewBuilder
    private var dropZoneIcon: some View {
        if let upload = activeUpload {
            switch upload.phase {
            case .uploading:
                Ring(progress: upload.progress, size: 28, stroke: 3, tint: dropZoneAccent)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(dropZoneAccent)
            case .failed:
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(dropZoneAccent)
            }
        } else {
            Text("📎")
                .font(.system(size: 22))
        }
    }

    private var dropZoneTitle: String {
        guard let upload = activeUpload else { return "Drop a file to share" }
        switch upload.phase {
        case .uploading:
            switch upload.stage {
            case .receiving:
                return "File received"
            case .staging:
                return "Preparing file \(percent(upload.progress))"
            case .hashing:
                return "Checking file \(percent(upload.progress))"
            case .presigning:
                return "Creating link…"
            case .finalizing:
                return "Finishing upload…"
            case .uploading:
                break
            }
            if upload.linkReady {
                return "Link copied — uploading"
            }
            return "Uploading \(Int((upload.progress * 100).rounded()))%"
        case .completed:
            return "Link copied"
        case .failed:
            return "Upload failed"
        }
    }

    private var dropZoneSubtitle: String {
        guard let upload = activeUpload else { return "Link copied automatically" }
        switch upload.phase {
        case .uploading:
            if upload.bytesTotal > 0, upload.bytesSent > 0 {
                return "\(formatted(upload.bytesSent)) / \(formatted(upload.bytesTotal))"
            }
            switch upload.stage {
            case .receiving:
                return upload.filename.isEmpty ? "Drop accepted" : upload.filename
            case .staging:
                return upload.filename.isEmpty ? "Preparing local copy…" : upload.filename
            case .hashing:
                return upload.filename.isEmpty ? "Checking file…" : upload.filename
            case .presigning:
                return "Creating secure link before upload"
            case .finalizing:
                return "Finalizing share link"
            case .uploading:
                return upload.filename.isEmpty ? "Uploading…" : upload.filename
            }
        case .completed:
            return upload.filename.isEmpty ? "Upload complete" : upload.filename
        case .failed:
            return upload.error ?? (upload.filename.isEmpty ? "Try again" : upload.filename)
        }
    }

    private func percent(_ progress: Double) -> String {
        "\(Int((max(0, min(1, progress)) * 100).rounded()))%"
    }

    // MARK: - Recent block

    @ViewBuilder
    private var recentBlock: some View {
        if !recentShares.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("RECENT")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(textDimColor)
                    .tracking(0.08 * 11)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                    .padding(.horizontal, 6)

                ForEach(recentShares, id: \.token) { share in
                    MenuBarShareRow(
                        share: share,
                        now: now,
                        textColor: textColor,
                        textDimColor: textDimColor,
                        lineColor: lineColor,
                        onCopy: {
                            clipboard.copy(share.shortURLString)
                        }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            lineColor.frame(height: 1)
            HStack {
                Button {
                    TrayManager.shared.closePopover()
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(textDimColor)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Quit FastShared")
                .accessibilityLabel("Quit FastShared")

                Spacer()

                Button {
                    TrayManager.shared.closePopover()
                    MacLaunchAtLoginController.showMainWindow()
                } label: {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(textDimColor)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Library")

                Button {
                    TrayManager.shared.closePopover()
                    SettingsWindowHolder.shared.open(subscriptionStore: subscriptionStore,
                                                     paywallCoordinator: paywallCoordinator)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(textDimColor)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Settings")
                .padding(.trailing, 8)
            }
            .padding(.vertical, 6)
        }
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Settings window

    /// Opens Settings in a dedicated floating window — sheets inside NSPopover
    /// are unreliable on macOS, so we use a real NSWindow instead.
    private func openSettingsWindow() {
        SettingsWindowHolder.shared.open()
    }

    // MARK: - Drop handler

    /// Called by PopoverDropOverlay when a drop lands inside the popover.
    func handlePopoverDrop(urls: [URL]) {
        NSLog("[MacMenuBarView] handlePopoverDrop — \(urls.count) URL(s)")
        TrayManager.shared.handleTrayDrop(urls: urls)
    }
}

// MARK: - MenuBarShareRow

private struct MenuBarShareRow: View {
    let share: ShareLinkEntity
    let now: Date
    let textColor: Color
    let textDimColor: Color
    let lineColor: Color
    let onCopy: () -> Void

    private var remaining: TimeInterval { max(0, share.expiresAt.timeIntervalSince(now)) }
    private var tier: ExpiryTier { ExpiryTier.tier(for: remaining) }

    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: 10) {
                // Urgency dot
                Circle()
                    .fill(tier.urgencyColor)
                    .frame(width: 8, height: 8)

                // Filename
                Text(share.originalFilename ?? share.token)
                    .font(.system(size: 13))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Remaining time
                Text(ExpiryFormatter.remaining(remaining))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tier.urgencyColor)
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy link")
    }
}

// MARK: - SettingsWindowHolder

/// Holds a strong reference to the Settings window so it stays alive
/// while the user interacts with it. Replaces any previous window.
@MainActor
final class SettingsWindowHolder {
    static let shared = SettingsWindowHolder()
    private var window: NSWindow?

    private init() {}

    /// Opens (or re-opens) a dedicated Settings window.
    func open(subscriptionStore: SubscriptionStoreProtocol = NoopSubscriptionStore(),
              paywallCoordinator: PaywallCoordinator = PaywallCoordinator()) {
        NSLog("[SettingsWindowHolder] open() called")
        // If a window already exists, just bring it to front
        if let existing = window {
            NSLog("[SettingsWindowHolder] existing window found, isVisible=\(existing.isVisible)")
            if existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
        }
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Settings"
        newWindow.identifier = .fastSharedSettingsWindow
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.contentViewController = NSHostingController(
            rootView: SettingsView()
                .environment(\.subscriptionStore, subscriptionStore)
                .environment(\.paywallCoordinator, paywallCoordinator)
        )
        newWindow.center()
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
        NSLog("[SettingsWindowHolder] new window created and shown")
        window = newWindow
    }
}

#Preview("MacMenuBarView") {
    MacMenuBarView()
        .preferredColorScheme(.dark)
}

// MARK: - TrayManager

/// Manages the macOS status-bar item manually so we can implement
/// `NSDraggingDestination` (open popover on drag) and draw a dynamic
/// progress badge on the tray icon.
///
/// Replaces SwiftUI's `MenuBarExtra` which does not expose the
/// `NSStatusItem` for drag handling or custom icon drawing.
@MainActor
final class TrayManager: NSObject {
    static let shared = TrayManager()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var trayView: TrayIconView?
    private var uploadService: UploadServiceProtocol?

    /// Non-zero while a drag is in flight — prevents the popover from
    /// snapping shut when the cursor leaves the tiny tray button on its
    /// way to the drop zone inside the popover.
    private var dragSessionCount = 0

    /// Auto-close work item — cancelled if another drag starts.
    private var scheduledClose: DispatchWorkItem?

    private var progressTimer: Timer?
    private let log = Logger(subsystem: Log.subsystem, category: "tray")

    private override init() {
        super.init()
    }

    // MARK: - Setup

    func configure(with rootView: some View, uploadService: UploadServiceProtocol?) {
        self.uploadService = uploadService
        createStatusItem()
        createPopover(with: rootView)
        startProgressPolling()
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = item

        guard let button = item.button else { return }

        // WHY: NSStatusItem.view replaces the button entirely and the system
        // sometimes refuses to deliver NSDraggingDestination events to a
        // completely custom view in the status bar. Adding our view as a
        // *subview* of the standard NSStatusBarButton keeps the native button
        // alive and allows drag events to flow through.
        let view = TrayIconView(frame: button.bounds)
        view.manager = self
        view.autoresizingMask = [.width, .height]
        button.addSubview(view)
        self.trayView = view

        button.imagePosition = .imageOnly
        refreshIcon()
    }

    private func createPopover(with rootView: some View) {
        let po = NSPopover()
        po.behavior = .transient
        po.contentSize = NSSize(width: 360, height: 400)
        let host = NSViewController()
        let hostView = PopoverDropHostingView(rootView: rootView)
        hostView.manager = self
        host.view = hostView
        po.contentViewController = host
        self.popover = po
    }

    // MARK: - Popover control

    @objc func togglePopover() {
        guard let popover, let view = trayView else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }

    func openPopover() {
        guard let popover, let view = trayView, !popover.isShown else { return }
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    /// Schedules a delayed close so the popover stays open long enough
    /// for the user to drag from the tiny tray icon into the drop zone.
    func scheduleClose(after: TimeInterval = 2.5) {
        scheduledClose?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.dragSessionCount == 0 else { return }
            self.closePopover()
        }
        scheduledClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: work)
    }

    func cancelScheduledClose() {
        scheduledClose?.cancel()
        scheduledClose = nil
    }

    // MARK: - Drag session bookkeeping

    func beginDragSession() {
        dragSessionCount += 1
        cancelScheduledClose()
        openPopover()
    }

    func endDragSession(shouldScheduleClose: Bool = true) {
        dragSessionCount = max(0, dragSessionCount - 1)
        if shouldScheduleClose, dragSessionCount == 0 {
            scheduleClose(after: 3.0)
        }
    }

    /// Called by TrayIconView when the user drops files directly on the tray icon.
    /// Kicks off the upload without requiring the user to move the cursor into
    /// the popover drop zone.
    func handleTrayDrop(urls: [URL]) {
        log.info("Tray drop received \(urls.count) file(s)")
        guard let service = uploadService else {
            log.error("UploadService not available")
            return
        }
        cancelScheduledClose()
        openPopover()

        let receipt = Self.dropReceipt(for: urls)
        UploadProgressMonitor.shared.start(
            clientJobId: receipt.clientJobId,
            filename: receipt.filename,
            contentType: receipt.contentType,
            bytesTotal: receipt.bytesTotal,
            stage: .receiving
        )
        refreshIcon()

        Task {
            do {
                let result = try await service.enqueueDrop(urls: urls,
                                                           retentionPolicy: RetentionPolicy.defaultFromAppGroup(),
                                                           progressClientJobId: receipt.clientJobId)
                switch result {
                case .single(let job):
                    log.info("Single upload started: \(job.clientJobId.uuidString)")
                case .bundle(let bundle):
                    log.info("Bundle upload started: \(bundle.bundleToken)")
                }
            } catch {
                await MainActor.run {
                    if UploadProgressMonitor.shared.current?.clientJobId == receipt.clientJobId {
                        UploadProgressMonitor.shared.finishFailure(
                            clientJobId: receipt.clientJobId,
                            reason: error.localizedDescription
                        )
                    }
                    self.refreshIcon()
                }
                log.error("Tray drop upload failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private struct DropReceipt {
        let clientJobId: UUID
        let filename: String
        let contentType: String
        let bytesTotal: Int64
    }

    private static func dropReceipt(for urls: [URL]) -> DropReceipt {
        let filename = urls.count == 1 ? (urls.first?.lastPathComponent ?? "File") : "\(urls.count) files"
        let contentType: String
        if urls.count == 1, let ext = urls.first?.pathExtension, !ext.isEmpty {
            contentType = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        } else {
            contentType = "application/x-bundle"
        }
        return DropReceipt(
            clientJobId: UUID(),
            filename: filename,
            contentType: contentType,
            bytesTotal: urls.map(fileSize).reduce(0, +)
        )
    }

    private static func fileSize(for url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: - Progress icon

    private func startProgressPolling() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshIcon()
            }
        }
    }

    private func refreshIcon() {
        let monitor = UploadProgressMonitor.shared
        let image: NSImage?

        if let current = monitor.current {
            switch current.phase {
            case .uploading:
                image = Self.progressBadgeImage(
                    systemName: "paperplane.fill",
                    fraction: current.progress
                )
            case .completed:
                image = Self.staticSymbol("checkmark.circle.fill")
            case .failed:
                image = Self.staticSymbol("xmark.circle.fill")
            }
        } else {
            image = Self.staticSymbol("paperplane.fill")
        }

        statusItem?.button?.image = image
        statusItem?.button?.needsDisplay = true
    }

    // MARK: - Image generation

    /// Draws the SF Symbol with a partial progress ring around it.
    private static func progressBadgeImage(systemName: String, fraction: Double) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        return NSImage(size: size, flipped: false) { rect in
            guard let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) else {
                return false
            }

            // Tint-aware: use the label color so it adapts to menubar dark/light
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
                .applying(.init(paletteColors: [NSColor.labelColor]))
            let tinted = symbol.withSymbolConfiguration(config) ?? symbol

            let symbolRect = rect.insetBy(dx: 3, dy: 3)
            tinted.draw(in: symbolRect)

            let clamped = fraction.isFinite ? min(1, max(0, fraction)) : 0
            let visibleFraction = max(0.06, clamped)

            // Progress ring. Always draw a small segment at 0% so a received
            // drop has immediate visual feedback while staging/presign runs.
            let ringRect = rect.insetBy(dx: 1.5, dy: 1.5)
            let trackPath = NSBezierPath(ovalIn: ringRect)
            trackPath.lineWidth = 2.2
            NSColor.tertiaryLabelColor.withAlphaComponent(0.28).setStroke()
            trackPath.stroke()

            let ringPath = NSBezierPath()
            let center = NSPoint(x: ringRect.midX, y: ringRect.midY)
            let radius = min(ringRect.width, ringRect.height) / 2
            let startAngle: CGFloat = 90
            if visibleFraction >= 0.999 {
                ringPath.appendOval(in: ringRect)
            } else {
                let endAngle = startAngle - CGFloat(visibleFraction * 360)
                ringPath.appendArc(withCenter: center,
                                   radius: radius,
                                   startAngle: startAngle,
                                   endAngle: endAngle,
                                   clockwise: true)
            }
            ringPath.lineWidth = 2.5
            NSColor.controlAccentColor.setStroke()
            ringPath.stroke()

            return true
        }
    }

    private static func staticSymbol(_ name: String) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            .applying(.init(paletteColors: [NSColor.labelColor]))
        return symbol.withSymbolConfiguration(config)
    }
}

// MARK: - TrayIconView

/// Custom `NSView` that replaces `NSStatusBarButton` so we can receive
/// drag events and draw a dynamic icon.
private final class TrayIconView: NSView {
    weak var manager: TrayManager?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Register both modern (public.file-url) and legacy (NSFilenamesPboardType)
        // types so Finder drags are always recognised.
        registerForDraggedTypes(PasteboardFileURLs.draggedTypes)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // WHY: Completely transparent — the actual icon is drawn by
    // TrayManager into NSStatusBarButton.image. This view exists
    // only to intercept mouse clicks and drag events.
    override func draw(_ dirtyRect: NSRect) {
        // Intentionally empty — transparent overlay
    }

    override func mouseDown(with event: NSEvent) {
        manager?.togglePopover()
    }

    // MARK: NSDraggingDestination

    override func wantsPeriodicDraggingUpdates() -> Bool {
        true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if PasteboardFileURLs.canReadFileURLs(from: sender.draggingPasteboard) {
            manager?.beginDragSession()
            return .copy
        }
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        manager?.endDragSession()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let mgr = manager else {
            manager?.endDragSession()
            return false
        }

        let fileURLs = PasteboardFileURLs.read(from: sender.draggingPasteboard)

        guard !fileURLs.isEmpty else {
            mgr.endDragSession()
            return false
        }
        mgr.handleTrayDrop(urls: fileURLs)
        mgr.endDragSession(shouldScheduleClose: false)
        return true
    }
}

// MARK: - PopoverDropHostingView

/// Hosting view registered as the popover's AppKit drag destination.
/// SwiftUI `.onDrop` inside an `NSPopover` is unreliable for Finder drags, and
/// installing an overlay before the popover is shown races with view creation.
private final class PopoverDropHostingView<Root: View>: NSHostingView<Root> {
    weak var manager: TrayManager?

    required init(rootView: Root) {
        super.init(rootView: rootView)
        registerForDraggedTypes(PasteboardFileURLs.draggedTypes)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        PasteboardFileURLs.canReadFileURLs(from: sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        PasteboardFileURLs.canReadFileURLs(from: sender.draggingPasteboard) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let fileURLs = PasteboardFileURLs.read(from: sender.draggingPasteboard)
        guard !fileURLs.isEmpty else { return false }
        manager?.handleTrayDrop(urls: fileURLs)
        return true
    }
}

// MARK: - PasteboardFileURLs

private enum PasteboardFileURLs {
    private static let legacyFilenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    static let draggedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        legacyFilenamesType,
        .URL
    ]

    static func canReadFileURLs(from pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || (pasteboard.types?.contains(legacyFilenamesType) ?? false)
            || fileURLString(from: pasteboard) != nil
    }

    static func read(from pasteboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []

        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        for object in objects {
            if let url = object as? URL, url.isFileURL {
                urls.append(url)
            } else if let nsURL = object as? NSURL {
                let url = nsURL as URL
                if url.isFileURL {
                    urls.append(url)
                }
            }
        }

        if urls.isEmpty,
           let paths = pasteboard.propertyList(forType: legacyFilenamesType) as? [String] {
            urls = paths.map { URL(fileURLWithPath: $0) }
        }

        if urls.isEmpty, let url = fileURLString(from: pasteboard) {
            urls.append(url)
        }

        return deduplicated(urls)
    }

    private static func fileURLString(from pasteboard: NSPasteboard) -> URL? {
        for type in [NSPasteboard.PasteboardType.fileURL, NSPasteboard.PasteboardType.URL] {
            guard let raw = pasteboard.string(forType: type),
                  let url = URL(string: raw),
                  url.isFileURL else { continue }
            return url
        }
        return nil
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                result.append(url)
            }
        }
        return result
    }
}
#endif
