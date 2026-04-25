# Apple client

Implementation notes for the Apple side of FastShared. Paired with [Upload flow](./upload-flow.md) for runtime behavior and [System design](./system-design.md) for the overall picture.

## Targets

Three targets share code through one local Swift package.

| Target                | Platform(s)        | Responsibility                                                         |
| --------------------- | ------------------ | ---------------------------------------------------------------------- |
| `FastSharedApp`       | iOS, iPadOS, macOS | Main SwiftUI app; owns UI, SwiftData store, background session delegate |
| `FastSharedShareExt`  | iOS, iPadOS        | Share Extension; stages files, enqueues jobs, starts background upload |
| `FastSharedCore`      | local Swift Package | Shared models, networking client, hashing, logging, keychain access   |

Rules:

- `FastSharedCore` has zero UI. It is the single source of truth for `UploadJobEntity`, `ShareLinkEntity`, the `APIClient`, and the shared `URLSession` configuration.
- `FastSharedApp` depends on `FastSharedCore`.
- `FastSharedShareExt` depends on `FastSharedCore` and nothing else.

## App Group

Identifier: `group.com.yourco.fastshared`.

Contents:

| Path inside the group container            | Purpose                                                   |
| ------------------------------------------ | --------------------------------------------------------- |
| `Library/Application Support/store.sqlite` | SwiftData store shared between app and extension          |
| `Caches/Staging/`                          | Incoming files copied from `NSItemProvider` before upload |
| `UserDefaults` (suite name = group)        | Shared non-secret flags, e.g. `lastCompletedJobId`, default retention |

Access patterns:

- The extension obtains the container URL via `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)` and writes the staged file with an `.inProgress` suffix that is renamed atomically on success.
- The app opens the SwiftData store with the same URL. Both targets use a single `ModelContainer` configuration declared in `FastSharedCore`.
- Keychain items are saved with the configured `KEYCHAIN_ACCESS_GROUP` so both targets see the same device token. Legacy App Group `UserDefaults` tokens are migrated once into Keychain and then removed.

## Background URLSession

One configuration, one identifier.

- Identifier: `com.yourco.fastshared.upload`
- `isDiscretionary = false` on foreground app; `= true` from the extension.
- `sharedContainerIdentifier = "group.com.yourco.fastshared"` so temp files are reachable after extension exit.
- `allowsCellularAccess = true`.
- `sessionSendsLaunchEvents = true` so iOS relaunches the app when the session delegate needs attention.

Handoff:

- The extension creates the session with its identifier, starts an `uploadTask(with:fromFile:)`, then calls `extensionContext?.completeRequest(returningItems:)`.
- Later, iOS wakes `FastSharedApp`, calls `application(_:handleEventsForBackgroundURLSession:completionHandler:)`, and we store the completion handler.
- `FastSharedCore` re-instantiates the same session (same identifier). The system delivers pending `urlSession(_:task:didCompleteWithError:)` and `urlSession(_:dataTask:didReceive:)` callbacks to the app's delegate.
- After `urlSessionDidFinishEvents(forBackgroundURLSession:)`, the stored completion handler is called.

## Share Extension lifecycle

1. `NSExtensionPrincipalClass` is `ShareViewController` with `NSExtensionMainStoryboard` disabled.
2. `viewDidLoad` walks `extensionContext?.inputItems` for `NSItemProvider` instances conforming to concrete UTTypes (`public.image`, `public.movie`, `public.file-url`, `com.adobe.pdf`, etc.).
3. For each matching provider, we call `loadFileRepresentation(forTypeIdentifier:completionHandler:)` and stream the result to `App Group/Caches/Staging/<uuid>`. During the stream we compute SHA-256 incrementally using `CryptoKit.SHA256`.
4. **User selects a retention policy** (default `oneDay`, read from Settings). The picker shows the five presets (`oneMinute`, `oneHour`, `oneDay`, `oneWeek`, `oneMonth`) with sub-second tap targets. The chosen policy is carried into `PresignRequest`.
5. Insert an `UploadJobEntity(state: .pending, sha256:, size:, mime:, stagedPath:, clientJobId: UUID(), retentionPolicy:)` into the shared SwiftData store.
6. Call `POST /v1/uploads` via `APIClient` with the retention policy.
7. Server response includes `expiresAt` and `deleteAfter`; we persist them on the job row for the completion step.
8. On response, start the background `uploadTask`.
9. Call `extensionContext?.completeRequest(returningItems: [])` — this unblocks the host app. The extension is torn down within seconds.

## SwiftData schema

Shared store at `group.com.yourco.fastshared/Library/Application Support/store.sqlite`. Two models.

```swift
@Model
public final class UploadJobEntity {
  @Attribute(.unique) public var clientJobId: UUID
  public var sha256: String
  public var size: Int64
  public var mime: String
  public var stagedPath: String?
  public var state: String   // pending | presigned | uploading | retry_scheduled | verifying | completed | deduped | failed
  public var attempts: Int
  public var lastError: String?
  public var serverUploadId: String?
  public var retentionPolicy: String   // oneMinute | oneHour | oneDay | oneWeek | oneMonth | custom
  public var customTtlSeconds: Int?    // set only when retentionPolicy == "custom"
  public var expiresAt: Date?          // filled after presign succeeds
  public var deleteAfter: Date?        // filled after presign succeeds
  public var shortUrl: String?
  public var token: String?            // set on completion
  public var createdAt: Date
  public var updatedAt: Date
}

@Model
public final class ShareLinkEntity {
  @Attribute(.unique) public var token: String       // 22-char base62, not "slug"
  public var shortUrl: String
  public var filename: String
  public var mime: String
  public var size: Int64
  public var retentionPolicy: String
  public var linkStatus: String        // active | expired | revoked | removed
  public var expiresAt: Date
  public var deleteAfter: Date
  public var revokedAt: Date?
  public var lastAccessedAt: Date?
  public var accessCount: Int
  public var createdAt: Date
  public var removedAt: Date?          // set when the object has been deleted server-side
}
```

Mapping to server fields is in [Data model](./data-model.md).

## Tombstones & countdown UI

The history list has four row states and a live countdown.

| Row state | Meaning                                                                         | Visual                                            |
| --------- | ------------------------------------------------------------------------------- | ------------------------------------------------- |
| `active`  | `linkStatus == "active"` and `expiresAt > now()`                                | Countdown badge: green > 6 h, amber ≤ 6 h, red ≤ 30 m |
| `expired` | `expiresAt <= now()` and `removedAt == nil`                                     | Grey `Expired` badge; row non-tappable for copy   |
| `revoked` | `linkStatus == "revoked"` and `removedAt == nil`                                | Grey `Revoked` badge with an amber dot            |
| `removed` | `removedAt != nil` (object deleted server-side)                                 | Grey `Removed` badge; persists 30 days, then reaped |

Implementation notes:

- A single `TimelineView(.periodic(from: .now, by: 30))` refreshes the visible rows every 30 s so badges re-color without user interaction.
- `lazyMarkExpiredIfNeeded` runs on each row render: if `expiresAt <= now()` and the local `linkStatus == "active"`, it flips the row to `expired` in SwiftData without a network call. Server will confirm on next history fetch.
- Tombstones (`expired`, `revoked`, `removed`) are kept for 30 days from their terminal transition, then reaped by a local housekeeping pass on launch.
- Detail view shows `expires at`, `media deleted at` (when known), access count, and the **Revoke link** button.

## Revoke flow

1. User opens `DetailView` for a live `ShareLinkEntity` and taps **Revoke link** (destructive style).
2. SwiftUI confirmation alert. On confirm:
3. `APIClient.revoke(token:)` → `POST /v1/links/:token/revoke`.
4. On success, the local entity flips to `linkStatus = "revoked"` and `revokedAt = .now`. The row re-renders as a revoked tombstone.
5. On network failure, the action is marked pending and retried from the resume-on-launch sweep. Local row stays `active` with a transient "Revoke pending" badge.

The owner cannot re-revoke an already revoked link; the button is hidden for non-`active` rows.

## Keychain access group

All bearer secrets use the configured shared access group (production resolves to `$(AppIdentifierPrefix)dev.kindrazki.fastshared`).

- `device.token` — bearer token returned by `POST /v1/devices`. Stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so the extension can read it after first unlock.
- `device.id` — server-assigned device id, cached next to the token.
- Rotation path (`POST /v1/devices/:id/rotate`, post-MVP) overwrites both.
- Migration path: `DeviceTokenStore.load()` checks Keychain first. If empty and a legacy App Group `UserDefaults` payload exists, it writes that payload to Keychain, deletes the legacy value, and returns it. Keychain write failures are surfaced as errors instead of falling back to less-secure storage.

Share tokens are **not** stored in Keychain — they are metadata tied to a row in SwiftData, and they are displayed and copied as part of normal UI.

## Clipboard abstraction

`FastSharedCore` exposes `protocol Pasteboard { func set(_ text: String) }` with platform-specific concrete types:

- iOS / iPadOS: wraps `UIPasteboard.general`.
- macOS: wraps `NSPasteboard.general`, clearing first with `clearContents()`.

Injecting the protocol makes unit tests trivial.

## Mac-specific features

- **Drop target.** Main window hosts a `DropDelegate` accepting `UTType.fileURL` items. Drop handler applies the default retention from Settings and enqueues jobs.
- **Command menu.** `CommandGroup(after: .newItem)` adds "Upload from Clipboard" (⌘⇧V) and "Open Recent Link" (⌘L).
- **`.fileImporter`.** Primary button opens `fileImporter(isPresented:allowedContentTypes:allowsMultipleSelection:onCompletion:)`. Multi-select produces one `UploadJobEntity` per URL; each picks up the default retention from Settings.
- **Settings pane** exposes a **default-retention picker** (same five presets as the Share Extension) so Mac drops inherit the user's preferred window without a modal.
- **Menu bar extra (future).** Tracked as a post-MVP item; not in scope for MVP.

## Logging

Subsystem: `com.yourco.fastshared`. Categories:

| Category    | Used for                                          |
| ----------- | ------------------------------------------------- |
| `upload`    | Upload state transitions, attempts, retries       |
| `extension` | Extension lifecycle, item providers, staging      |
| `ui`        | View model events in the app                      |
| `net`       | `APIClient` requests and responses                |
| `storage`   | SwiftData and App Group I/O                       |

All logs default to `.info`; `.debug` is used for request bodies and redacted to remove file paths, tokens, and device ids.

## Testing strategy

- **Unit tests** in `FastSharedCoreTests`: hashing, retry math, pasteboard (via protocol), `APIClient` against a mock `URLProtocol`, **retention-policy encoding/decoding**, **countdown badge state derivation** from `(expiresAt, linkStatus, removedAt)`.
- **Snapshot tests** in `FastSharedCoreTests`: **tombstone-state snapshot test** renders the four row states (`active/expired/revoked/removed`) plus each countdown color bucket (green/amber/red) and diffs against a committed reference.
- **Integration tests** in `FastSharedAppTests` using a real temp App Group to validate SwiftData store sharing, background session handoff, and `lazyMarkExpiredIfNeeded` transitions on row render.
- **UI tests** in `FastSharedAppUITests` (XCUITest) cover the happy path: pick file via `.fileImporter` on macOS, confirm retention, wait for link, verify pasteboard and countdown visible.
- **Extension tests** use `XCTest` against a host app that invokes the extension with synthesized `NSItemProvider` inputs and a pre-selected retention.
- **Soak test** (manual, pre-release): queue 50 jobs with mixed retention, kill the app, verify all complete on next launch and the countdown correctly refreshes.
