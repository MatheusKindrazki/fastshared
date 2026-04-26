# FastShared - Apple Client

Native iOS/iPadOS/macOS client for FastShared. A user shares a file via the system Share Sheet, a Share Extension stages it in an App Group container, a background `URLSession` uploads it directly to Cloudflare R2 via a presigned URL, and the backend mints a short link that is copied to the clipboard and persisted to history.

## Pro subscription

FastShared Pro is layered on top of the Free experience (3 uploads/day, 100 MB per file, 24h retention, no cross-device sync). The Apple client slice is documented end-to-end in [`docs/plan/pro-feature-B-apple.md`](../docs/plan/pro-feature-B-apple.md).

Key pieces (Plan B):

- `FastSharedCore/Subscription/SubscriptionStore.swift` — StoreKit 2 actor that owns `isPro` / `tier` / `expiresAt` / caps, verifies every JWS against `/v1/iap/verify`, caches the last-known-good snapshot in the App Group.
- `FastSharedCore/Usage/UsageTracker.swift` — UTC-keyed daily upload counter shared between main app + share ext.
- `FastSharedCore/CloudKit/CloudKitSyncEngine.swift` — Pro-gated `CKSyncEngine` wrapper; mirrors `ShareLinkEntity` rows into the user's private CloudKit DB. Stop never deletes cloud data.
- `FastSharedApp/Scenes/PaywallView.swift` + `PaywallTierCard.swift` — the paywall surface, driven by `PaywallCoordinator` and presented from every upsell moment (daily cap, cloud-sync toggle, extended retention, large file, 402 server-forced).
- `FastSharedApp/FastShared.storekit` — hand-authored StoreKit configuration with the three production SKUs (`red.fastsha.pro.monthly|annual|lifetime`).

QA: `docs/plan/pro-feature-B-apple-qa-matrix.md`.

## Bundle uploads

For batches of 2+ files, use `UploadService.enqueueBundle(stagedURLs:retentionPolicy:)`
or the polymorphic `enqueueDrop(urls:)` (which returns `EnqueueResult.single`
or `EnqueueResult.bundle`). The backend mints one bundle link
(`https://fastsha.red/b/{token}`) that covers every file in the batch, the
clipboard receives a single URL, history persists one `ShareLinkEntity` with
`isBundle=true` plus `BundledAssetEntity` children, and the Live Activity
aggregates byte-level progress across all files. Single-file flow remains on
`/s/{token}` and is otherwise untouched.

## Requirements

- Xcode 15 or newer
- macOS 14+ (for building the macOS target)
- iOS 17 / iPadOS 17 simulator or device (for the iOS targets)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Generating the Xcode project

From inside `apple/`:

```bash
cd apple
xcodegen generate
```

This produces `FastShared.xcodeproj`. There is no committed `.xcworkspace`; you can either open the generated project directly, or create a workspace manually in Xcode (File > New > Workspace) and drag `FastShared.xcodeproj` and `Packages/FastSharedCore` into it. For day-to-day work, opening `FastShared.xcodeproj` is sufficient.

```bash
open FastShared.xcodeproj
```

## First-time configuration

1. Open `apple/Config/Shared.xcconfig` and set `DEVELOPMENT_TEAM` to your Apple Developer team ID (replace the `TEAMID` placeholder). The ID is the 10-character string shown in Apple Developer > Membership.
2. In the Apple Developer portal, create or confirm:
   - An App Group: `group.dev.kindrazki.fastshared`
   - App IDs for both `dev.kindrazki.fastshared` (main app) and `dev.kindrazki.fastshared.ShareExt` (share extension), each with the App Groups capability enabled and linked to the group above.
3. The app and extension share:
   - App Group: `group.dev.kindrazki.fastshared` (see `APP_GROUP_IDENTIFIER` in `Config/Shared.xcconfig`).
   - Keychain access group: `$(AppIdentifierPrefix)dev.kindrazki.fastshared`.
   - A single background `URLSession` identifier: `dev.kindrazki.fastshared.upload`.
4. Entitlements live in `FastSharedApp/FastSharedApp.entitlements` and `FastSharedShareExt/FastSharedShareExt.entitlements`. They reference `$(APP_GROUP_IDENTIFIER)` and the keychain access group so both targets can read the same SwiftData store and device token.

## Running the app

Select the `FastSharedApp` scheme in Xcode.

- **iOS / iPadOS simulator**: pick an iOS 17 device and hit Run. To test the share extension in the simulator, run the app once (so the extension is installed), then open Photos or Files, tap Share, and select FastShared. iOS simulator share sheet may require you to scroll and enable the extension once.
- **Mac Catalyst / macOS**: pick "My Mac" and Run. On macOS the share extension is activated from Finder's Share menu after the host app has been launched once.

## Running the share extension directly

In Xcode, select the `FastSharedShareExt` scheme, choose a host app (for iOS, Safari or Photos works well; for macOS, Finder), and Run. Xcode will launch the host app and attach the debugger to the extension process.

## Environments

- `Debug.xcconfig` and `Release.xcconfig` both point at `https://api.fastsha.red` and use `https://fastsha.red` as the short-link host. There is currently no separate dev environment; both configs target the single production backend.

## Camera / photo library usage strings

The Info.plist declares `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` even though the MVP does not capture media itself. The strings are present so that future in-app picker flows (and any system prompt triggered by upstream picker code paths) do not crash the app on iOS. Until they are used the strings should be treated as placeholders.

## Layout

```
apple/
  Config/                    xcconfigs for shared/debug/release settings
  FastSharedApp/             main multiplatform SwiftUI app target
  FastSharedShareExt/        iOS/macOS share extension target
  FastSharedLiveActivity/    iOS Live Activity / Dynamic Island widget
  Packages/FastSharedCore/   local SPM package with all business logic
  ExportOptions.plist        App-Store-Connect export options for xcodebuild
  project.yml                XcodeGen spec
```

All business logic lives in `FastSharedCore`. The two Xcode targets are thin shells that only wire UI into services from the package.

## Release archive

Local dry run (no upload) for either platform:

```bash
cd apple
xcodegen generate

# iOS archive
xcodebuild archive \
  -scheme FastSharedApp \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -archivePath build/FastShared-iOS.xcarchive

xcodebuild -exportArchive \
  -archivePath build/FastShared-iOS.xcarchive \
  -exportPath build/ipa \
  -exportOptionsPlist ExportOptions.plist

# macOS archive (same flags, different -destination)
xcodebuild archive \
  -scheme FastSharedApp \
  -destination 'generic/platform=macOS' \
  -configuration Release \
  -archivePath build/FastShared-macOS.xcarchive

xcodebuild -exportArchive \
  -archivePath build/FastShared-macOS.xcarchive \
  -exportPath build/app \
  -exportOptionsPlist ExportOptions.plist
```

The signed IPA lands in `build/ipa/FastShared.ipa` and the macOS `.pkg`
(or `.app.zip` depending on `method`) lands in `build/app/`.

For real TestFlight uploads, use the fastlane wrapper from the repo root:

```bash
make testflight
```

This is intentionally an all-platform release command: it uploads both the iOS
build and the native macOS build. Use `make testflight-ios` or
`make testflight-macos` only when recovering one failed platform upload.

`CURRENT_PROJECT_VERSION` defaults to the committed fallback (`1`). For a
real App Store Connect submission pass a monotonic build number:

```bash
xcodebuild archive ... CURRENT_PROJECT_VERSION=123
```

`MARKETING_VERSION` comes from `Config/Shared.xcconfig` and is the only
committed version-bump surface.

### CI workflow

`.github/workflows/apple-release.yml` runs the exact same sequence on a
`macos-14` runner. It triggers on:

- git tag push matching `v*`
- manual `workflow_dispatch` (with an optional `build_number` input)

The workflow uploads the xcarchive + exported IPA/app as a build
artifact so a human can inspect entitlements and file size before the
(still manual, see TODO below) push to TestFlight.

### Secrets required for future TestFlight automation

Not configured yet — the workflow currently stops at archive+export.
When we wire up `xcrun altool --upload-app` (or the newer
`xcrun notarytool submit`) the following repo secrets will be needed:

| Secret                       | Source                                                                                           |
| ---------------------------- | ------------------------------------------------------------------------------------------------ |
| `APP_STORE_CONNECT_KEY_ID`   | App Store Connect > Users and Access > Keys — the 10-char Key ID for an Admin- or Developer-role API key |
| `APP_STORE_CONNECT_ISSUER_ID`| Same page; the Issuer ID shown above the keys list (UUID-shaped)                                 |
| `APP_STORE_CONNECT_KEY`      | The `.p8` private key file contents, base64-encoded (`base64 -i AuthKey_XXXXXXXXXX.p8`)          |

Store each via `gh secret set` scoped to this repo. Never commit the
`.p8`; it is revealed once at creation time and cannot be retrieved
afterwards.

## App Store technical readiness

Everything the native app needs to be App Store Connect-submittable
lives in this repo. What a human must still do manually — per the
submission checklist — is called out in the relevant section below.

### Privacy manifests

Each of the three binaries (app, share extension, Live Activity) ships
a `PrivacyInfo.xcprivacy` in its target root. Required by Apple since
May 2024 — missing manifests are an automatic rejection.

| Target                | Declared API categories                         | Reason codes |
| --------------------- | ----------------------------------------------- | ------------ |
| FastSharedApp         | UserDefaults, FileTimestamp                     | CA92.1, C617.1 |
| FastSharedShareExt    | UserDefaults, FileTimestamp                     | CA92.1, C617.1 |
| FastSharedLiveActivity| (none — no Required Reason APIs are invoked)   | —            |

All three declare `NSPrivacyTracking = false`, no tracking domains, and
no SDK-level collected data types in the privacy manifest. The App Store
Connect App Privacy label is broader than this manifest and must still
disclose user-uploaded content, optional Apple identity, purchases, and
operational logs; keep it aligned with `docs/ops/appstore-launch-setup.md`.

### Associated domains / universal links

`FastSharedApp.entitlements` declares:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:fastsha.red</string>
</array>
```

Matching AASA file is served by the Hono worker at:

- `https://fastsha.red/.well-known/apple-app-site-association`

Expected body:

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "YFYB6NKC73.dev.kindrazki.fastshared",
        "paths": ["/s/*", "NOT /api/*"]
      }
    ]
  }
}
```

The `appID` must stay in lockstep with `DEVELOPMENT_TEAM` in
`Config/Shared.xcconfig` and `PRODUCT_BUNDLE_IDENTIFIER` in
`project.yml`. If either of those changes, update both the entitlement
and `backend/src/routes/wellKnown.ts`.

### Export compliance

`Info.plist` declares `ITSAppUsesNonExemptEncryption = false`. We only
use standard HTTPS (URLSession TLS) and the system Security framework,
so ASC's yearly export-compliance self-classification form is skipped.
If we ever ship password-protected links or end-to-end encryption this
MUST flip back to true and the BIS filing becomes relevant again.

### App Store automation

The full release checklist is `docs/ops/appstore-launch-setup.md`. The repo
owns the repeatable parts of the App Store launch:

```bash
make appstore-screenshots
make appstore-sync
```

`make appstore-screenshots` generates and validates iPhone, iPad, macOS, and
IAP review screenshots. `make appstore-sync` regenerates screenshots and uploads
metadata, icon, age rating, and screenshots for iOS/iPadOS + macOS. App Privacy
must be completed manually in App Store Connect from
`apple/fastlane/app_privacy_details.json`.

Apple-account-gated items still need to exist before the automation can finish:

- Create or confirm one App Store Connect app record for
  `dev.kindrazki.fastshared` covering iOS/iPadOS and macOS. Do not create
  separate App Store app records for the share extension or Live Activity;
  those are Developer Portal identifiers embedded in the main app.
- Keep the Privacy Policy URL as `https://fastsha.red/privacy` and Support
  URL as `https://fastsha.red/support`.
- Configure the three Pro IAPs with product IDs
  `red.fastsha.pro.monthly`, `red.fastsha.pro.annual`, and
  `red.fastsha.pro.lifetime`.
- Generate/store the ASC API key outside the repo; local env values live in
  `apple/.env.testflight` and `apple/.env.appstore.local`.
- Decide whether the macOS target goes to the Mac App Store (current
  assumption) or Developer ID direct distribution. Current entitlements
  assume MAS and keep `com.apple.security.app-sandbox = true`.
