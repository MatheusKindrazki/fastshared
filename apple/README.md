# FastShared - Apple Client

Native iOS/iPadOS/macOS client for FastShared. A user shares a file via the system Share Sheet, a Share Extension stages it in an App Group container, a background `URLSession` uploads it directly to Cloudflare R2 via a presigned URL, and the backend mints a short link that is copied to the clipboard and persisted to history.

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

- `Debug.xcconfig` points at `https://api.dev.fastshared.app` and uses `https://fsh.dev` as the short-link host.
- `Release.xcconfig` points at `https://api.fastshared.app` and uses `https://fsh.re`.

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
no collected data types. FastShared is anonymous-bearer by design (see
`docs/architecture/security.md`) — no user identifiers, no analytics
SDKs, no ATT tracker table.

### Associated domains / universal links

`FastSharedApp.entitlements` declares:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:fastsha.red</string>
    <string>applinks:fsh.re</string>
</array>
```

Matching AASA file is served by the Hono worker at:

- `https://fastsha.red/.well-known/apple-app-site-association`
- `https://fsh.re/.well-known/apple-app-site-association`

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

### Still-manual submission checklist

The following steps live in App Store Connect / the Apple Developer
portal and cannot be automated from this repo yet:

- Create the three App Store Connect app records:
  - `dev.kindrazki.fastshared`       (main app — iOS, iPadOS, macOS)
  - `dev.kindrazki.fastshared.ShareExt`    (share extension)
  - `dev.kindrazki.fastshared.LiveActivity` (widget extension)
- Upload a privacy policy URL (will be `https://fastsha.red/privacy`
  once the web landing page ships).
- Fill the App Privacy section in ASC (all-negatives given our
  privacy manifest — no data collected, no tracking).
- Complete the age-rating questionnaire.
- Upload screenshots (see Track B for the spec sheet).
- Generate an ASC API key (Admin role) and store the three secrets
  above in the repo so CI can push to TestFlight.
- Decide whether the macOS target goes to the Mac App Store (current
  assumption) or Developer ID direct distribution. Current entitlements
  assume MAS and keep `com.apple.security.app-sandbox = true`.
