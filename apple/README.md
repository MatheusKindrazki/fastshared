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

- `Debug.xcconfig` and `Release.xcconfig` both point at `https://api.fastsha.red` and use `https://fastsha.red` as the short-link host. There is currently no separate dev environment; both configs target the single production backend.

## Camera / photo library usage strings

The Info.plist declares `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` even though the MVP does not capture media itself. The strings are present so that future in-app picker flows (and any system prompt triggered by upstream picker code paths) do not crash the app on iOS. Until they are used the strings should be treated as placeholders.

## Layout

```
apple/
  Config/                    xcconfigs for shared/debug/release settings
  FastSharedApp/             main multiplatform SwiftUI app target
  FastSharedShareExt/        iOS/macOS share extension target
  Packages/FastSharedCore/   local SPM package with all business logic
  project.yml                XcodeGen spec
```

All business logic lives in `FastSharedCore`. The two Xcode targets are thin shells that only wire UI into services from the package.
