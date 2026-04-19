# FastShared Pro — Apple Client Slice (Plan B)

> **For Agents:** REQUIRED SUB-SKILL: Use ring-default:executing-plans to implement this plan task-by-task.
> This plan covers ONLY the Apple client slice. Backend (Plan A) and landing/legal copy (Plan C) are parallel plans — out of scope here.

**Goal:** Ship StoreKit 2 + paywall + Free-tier gating + CloudKit metadata sync for FastShared iOS/macOS, gated on three ASC product IDs.

**Architecture:** A `SubscriptionStore` actor fronts StoreKit 2, owning `isPro` / `tier` / `expiresAt` and submitting every JWS transaction to `/v1/iap/verify`. A `UsageTracker` actor (App Group `UserDefaults`–backed) enforces Free-tier daily upload caps across main app and share extension. `PaywallView` is presented as a sheet from upsell moments via a `PaywallCoordinator`. When Pro, `CloudKitSyncEngine` (iOS 17 `CKSyncEngine`) mirrors `ShareLinkEntity` rows to the user's private CloudKit DB, gated on `SubscriptionStore.isPro`.

**Tech Stack:** Swift 5.10, SwiftUI, SwiftData, StoreKit 2, StoreKitTest, CloudKit (`CKSyncEngine`), XCTest. Strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`). iOS 17+ / macOS 14+.

**Global Prerequisites:**
- Xcode 15.3+, iOS Simulator 17.4+, `xcodegen` 2.38+ (`brew install xcodegen`).
- Apple Developer team already in `apple/Config/*.xcconfig`; ASC access to create IAP products + iCloud container.
- Plan A ships `POST /v1/iap/verify`, `GET /v1/me`, `GET /v1/pricing-flags`. Client consumes only — if shape drifts, patch `APIClient` only.
- Branch `feat/pro-apple` from clean `main`.

**Verification before starting:**
```bash
cd apple
xcodebuild -version                   # Xcode 15.3+
xcodegen --version                    # 2.38+
swift --version                       # Apple Swift 5.10+
xcodegen generate                     # Created project at apple/FastShared.xcodeproj
xcodebuild -project FastShared.xcodeproj -scheme FastSharedApp \
  -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -3
# Expected: ** BUILD SUCCEEDED **
```

**Codebase anchors (do NOT duplicate):**
- `apple/Packages/FastSharedCore/Sources/FastSharedCore/Branding/BrandPalette.swift` — only color source.
- `apple/Packages/FastSharedCore/Sources/FastSharedCore/Models/RetentionPolicy.swift` — `.shareable` drives TTL picker.
- `apple/Packages/FastSharedCore/Sources/FastSharedCore/Persistence/SwiftDataStore.swift` — `ShareLinkEntity`/`UploadJobEntity`. Container wires `cloudKitDatabase: .none` deliberately — keep as-is; we manage CloudKit manually.
- `apple/Packages/FastSharedCore/Sources/FastSharedCore/AppGroup/AppGroupPaths.swift` — `group.dev.kindrazki.fastshared`.
- `apple/Packages/FastSharedCore/Sources/FastSharedCore/Networking/{APIClient,APIEndpoint,APIError}.swift` — extend here; reuse `attachAuth` + `Problem`.
- `apple/FastSharedShareExt/ShareViewController.swift` — staging + `performUpload` pipeline. Free-cap + size pre-flights go here.
- `apple/FastSharedApp/Scenes/SettingsView.swift` — Sync toggle + caps row.
- `apple/FastSharedApp/Scenes/HistoryView.swift` — main-app "share new file" affordance; inspect before Part 3.
- `apple/FastSharedApp/UploadServiceLocator.swift` — locator pattern to mirror for `SubscriptionStoreLocator`.

**Out of scope:** Backend endpoints; pricing landing / legal; upload compression (explicitly rejected). Family Sharing and promo codes deferred (leave `TODO(post-mvp)`).

---

## Part 1 — StoreKit 2 Integration

### B1.1 — Domain types (`ProTier`, `TierCaps`, `Tier`)

**Files (create):** `apple/Packages/FastSharedCore/Sources/FastSharedCore/Subscription/ProTier.swift`, `.../Subscription/TierCaps.swift`.

**Intent:** `ProTier: String, Sendable, Codable, CaseIterable { case monthly, annual, lifetime }` with `var productID: String` returning the hardcoded ASC IDs. `TierCaps: Sendable, Codable` with `dailyUploadLimit: Int?` (nil = unlimited), `maxFileSizeBytes: Int64`, `maxRetentionSeconds: TimeInterval`, `allowsCloudSync: Bool`. Statics: `.free` = (3, 100 MB, 86_400 s, false); `.pro` = (nil, 5 GB, 2_592_000 s, true). Broader `enum Tier: Sendable { case free; case pro(ProTier) }` with computed `caps: TierCaps`.

**Verification:** `swift build --package-path apple/Packages/FastSharedCore` → Build complete.

**Acceptance:** Types compile; `TierCaps.free.dailyUploadLimit == 3`; `ProTier.monthly.productID == "dev.kindrazki.fastshared.pro.monthly"`. Parallel-safe with B1.5, B1.7, B5.1, B5.2.

---

### B1.2 — `SubscriptionStoreProtocol` + actor shell

**Files (create):** `.../Subscription/SubscriptionStore.swift`.

**Intent:** Declare the public surface — stub bodies first.

```swift
public struct SubscriptionSnapshot: Sendable, Equatable {
    public var isPro: Bool
    public var tier: ProTier?
    public var expiresAt: Date?
    public var caps: TierCaps
    public var products: [StoreProductView]
    public var pricingFlags: PricingFlags?
}

public protocol SubscriptionStoreProtocol: Sendable {
    var snapshotStream: AsyncStream<SubscriptionSnapshot> { get }
    func currentSnapshot() async -> SubscriptionSnapshot
    func refreshProducts() async throws
    func purchase(_ productID: String) async throws -> PurchaseOutcome
    func restore() async throws
    func syncCurrentEntitlements() async
}
```

`final actor SubscriptionStore: SubscriptionStoreProtocol` with defaults returning `.free`. `StoreProductView { id, displayName, displayPrice, subscriptionPeriodISO8601: String? }` is a lightweight projection — SwiftUI previews never touch StoreKit directly.

**Depends:** B1.1. **Verify:** `swift build`. **Acceptance:** Protocol + stub compile.

---

### B1.3 — Wire `Product.products(for:)` + `Transaction.updates`

**Files (modify):** `.../Subscription/SubscriptionStore.swift`.

**Intent:** Import StoreKit. `refreshProducts()` calls `Product.products(for: ProTier.allCases.map(\.productID))`. `syncCurrentEntitlements()` iterates `Transaction.currentEntitlements`, picks the latest non-revoked, updates the snapshot. Actor `init` spawns a detached `Task` consuming `Transaction.updates` forever; each update: skip `.unverified`, finish the transaction, then call an injected `onNewTransaction: (VerificationResult<Transaction>) async -> Void` hook (real impl in B1.6).

**Decision — verification scope:** Apple's `VerificationResult` is the first gate (skip `.unverified`); `/v1/iap/verify` is the authoritative gate. Never trust the client to grant Pro, but flip optimistically for UX and revert on server refusal.

**Depends:** B1.2. **Verify:** `swift build` clean, zero strict-concurrency warnings. **Acceptance:** Actor starts its `updates` task on init.

---

### B1.4 — `purchase(_:)` + `restore()`

**Files (modify):** `.../Subscription/SubscriptionStore.swift`.

**Intent:** `purchase(productID:)` resolves from cache (refetch if missing), calls `product.purchase()`, maps to:

```swift
public enum PurchaseOutcome: Sendable, Equatable {
    case success            // verified locally + sent to /v1/iap/verify
    case userCancelled
    case pending            // Ask-to-Buy / SCA
    case verificationFailed
}
```

On `.success(.verified)` → finish transaction + `syncCurrentEntitlements()`. On `.success(.unverified)` → do NOT finish, return `.verificationFailed`. `restore()` → `try await AppStore.sync()` then re-sync entitlements.

**Depends:** B1.3. **Verify:** `swift build`. **Acceptance:** Public API matches B1.2 protocol.

---

### B1.5 — Extend `APIClient` with `/v1/iap/verify`, `/v1/me`, `/v1/pricing-flags`

**Files (modify):** `.../Networking/APIEndpoint.swift`, `.../Networking/APIClient.swift`.

**Intent:** Three new `APIEndpoint` cases + three new `APIClientProtocol` methods:

```swift
func verifyIAP(signedTransactionJWS: String) async throws -> IAPVerifyResponse
func fetchMe() async throws -> MeResponse
func fetchPricingFlags() async throws -> PricingFlags
```

New types (alongside existing endpoint types): `IAPVerifyRequest { signedTransaction: String }`, `IAPVerifyResponse { isPro, tier: String?, expiresAt: Date?, caps: TierCapsDTO }`, `MeResponse { isPro, tier, expiresAt, caps }`, `PricingFlags { earlyAccessLifetimeActive: Bool, earlyAccessEndsAt: Date? }`. Add `TierCapsDTO → TierCaps` mapping extension. Reuse existing `perform<Body,Response>` helper. Auth required on all three.

**Depends:** B1.1. **Verify:** `swift test --filter APIEndpointTests` — existing tests pass. **Acceptance:** Protocol extended; compiles. Parallel-safe with B1.2–B1.4.

---

### B1.6 — Wire `SubscriptionStore` → `APIClient` on every new transaction

**Files (modify):** `.../Subscription/SubscriptionStore.swift`. **Create:** `.../Subscription/SubscriptionSnapshotCache.swift`.

**Intent:** Inject `APIClientProtocol` in init. In the `Transaction.updates` closure (B1.3), extract `result.jwsRepresentation`, call `apiClient.verifyIAP(signedTransactionJWS:)`, merge server response into the snapshot (authoritative). On network failure: do NOT revoke Pro locally — keep optimistic state, log warning, schedule debounced retry (`Task.sleep(5s)`, max 3 attempts). `SubscriptionSnapshotCache` (free function enum, not in the actor to avoid churn) persists the last-known-good snapshot in App Group defaults key `pro_last_snapshot_v1` so a cold launch post-network-flap still shows Pro until proven otherwise.

**Depends:** B1.4, B1.5. **Verify:** `swift build`. **Acceptance:** Manual trace: buy monthly in Sandbox → JWS → backend → Pro snapshot → emitted on stream.

---

### B1.7 — `.storekit` config for local testing

**Files (create):** `apple/FastSharedApp/FastShared.storekit`. **Modify:** `apple/project.yml`.

**Intent:** Hand-author JSON (keep version-controlled; do NOT generate via Xcode UI):
- `dev.kindrazki.fastshared.pro.monthly` — auto-renewable, 1 month, USD 4.99.
- `dev.kindrazki.fastshared.pro.annual` — auto-renewable, 1 year, USD 29.99 (≈45% savings vs monthly drives the badge copy).
- `dev.kindrazki.fastshared.pro.lifetime` — non-consumable, USD 69.00.

Group the two subscriptions under subscription group `pro_access` so they're mutually exclusive (native upgrade/crossgrade).

In `project.yml` under `schemes.FastSharedApp.test`, add `storeKitConfiguration: FastSharedApp/FastShared.storekit`, then `xcodegen generate`.

**Depends:** B1.1. **Verify:** `plutil -lint apple/FastSharedApp/FastShared.storekit` → OK. Build succeeds. Xcode StoreKit transactions inspector shows three products. **Acceptance:** Scheme runs with config attached.

---

### B1.8 — Composition root wiring

**Files (modify):** `apple/FastSharedApp/FastSharedApp.swift`. **Create:** `apple/FastSharedApp/Platform/SubscriptionStoreEnvironment.swift`, `apple/FastSharedApp/SubscriptionStoreLocator.swift`.

**Intent:** One `SubscriptionStore` instance in `FastSharedApp.init()` with the existing `apiClient`. On launch `Task`: `refreshProducts()` + `syncCurrentEntitlements()`. Inject via `.environment(\.subscriptionStore, store)`. Share extension gets it through a `SubscriptionStoreLocator.shared` mirroring `UploadServiceLocator`'s pattern (same file shape).

**Depends:** B1.6. **Verify:** `xcodegen generate && xcodebuild … build`. **Acceptance:** App launches, Console.app shows product refresh log line.

---

### B1.9 — StoreKitTest unit tests

**Files (create):** `apple/Packages/FastSharedCore/Tests/FastSharedCoreTests/SubscriptionStoreTests.swift`, `.../FakeAPIClient.swift` (shared double, reused Parts 2–5), `.../Resources/FastSharedTest.storekit`.

**Intent:** `SKTestSession` per `setUp` (fresh). Cover:

1. `test_freeByDefault_whenNoTransactions`.
2. `test_purchaseMonthly_flipsToPro_andCallsVerify` — fake API returns `isPro: true`, `tier: "monthly"`; stream emits Pro snapshot.
3. `test_unverifiedTransaction_returnsVerificationFailed` — `session.failTransactionsEnabled` or tamper; returns `.verificationFailed`; snapshot stays free.
4. `test_restore_afterFreshInstall_restoresPro` — pre-seed prior sub; `restore()` → Pro.
5. `test_networkFailure_keepsOptimisticPro_andCaches` — fake throws `.transport`; Pro sticks; `SubscriptionSnapshotCache` file written.

`FakeAPIClient` stubs every `APIClientProtocol` method with `unimplemented` defaults + closure overrides. `Package.swift` testTarget gets `resources: [.process("Resources")]`.

**Depends:** B1.6, B1.7. **Verify:** `swift test --filter SubscriptionStoreTests 2>&1 | tail -5` → "Executed 5 tests, 0 failures". **Acceptance:** All 5 green.

---

### B1.10 — Code Review Checkpoint (Part 1) — `/ring-default:codereview`

Focus: strict concurrency on actor boundaries; JWS handling never trusts `.unverified`; snapshot cache has no sensitive data (no PII, no tokens — just `isPro`/`tier`/`expiresAt`); retry loop has finite max count.

**Severity rules (unchanged):** Critical/High/Medium → fix + re-run. Low → `TODO(review):`. Cosmetic → `FIXME(nitpick):`.

**Acceptance:** Zero C/H/M open → proceed to Part 2.

---

## Part 2 — Paywall UI

### B2.1 — `PaywallTriggerContext` + `PaywallCoordinator`

**Files (create):** `.../Subscription/PaywallTriggerContext.swift`, `.../Subscription/PaywallCoordinator.swift`.

**Intent:** Shape the presenter before the view.

```swift
public enum PaywallTriggerContext: Sendable, Identifiable {
    case dailyCapReached(used: Int, cap: Int)
    case cloudSyncRequested
    case longRetentionRequested(policy: RetentionPolicy)
    case largeFileRequested(sizeBytes: Int64)
    case serverForced(errorCode: String)
    public var id: String { /* synthetic discriminant */ }
}
```

`@Observable` (iOS 17) `@MainActor` `PaywallCoordinator` class with `var pending: PaywallTriggerContext?`, `func present(_:)`, `func dismiss()`. One per process; injected via environment. Any view attaches `.sheet(item: $coordinator.pending) { PaywallView(trigger: $0) }`.

**Depends:** B1.1 (for `RetentionPolicy`). **Verify:** `swift build`. **Acceptance:** Compiles. Parallel-safe with B2.2.

---

### B2.2 — `PaywallView` scaffold + layout

**Files (create):** `apple/FastSharedApp/Scenes/PaywallView.swift`.

**Intent:** Full-screen modal. `ScrollView` with: header (`fastshared.pro` wordmark reusing `BrandPalette.amber` dot from `ShareRootView`), trigger-specific hero copy (one line derived from `PaywallTriggerContext`), three tier cards stacked via `ViewThatFits` (VStack compact / HStack regular), shared "Restore Purchases" `Button`, footer with Privacy/Terms links, top-leading "Not now" close. Background: `BrandPalette.canvas`. Primary CTA color: `BrandPalette.amber`. Accept `trigger: PaywallTriggerContext`, `@Environment(\.subscriptionStore)`, `@Environment(\.dismiss)`. iOS: `.presentationDetents([.large])`. macOS: natural 520×720 sheet.

**Depends:** B2.1. **Verify:** Build. SwiftUI preview renders all 5 `PaywallTriggerContext` cases. **Acceptance:** Compiles with all preview variants.

---

### B2.3 — `PaywallTierCard` subview

**Files (create):** `apple/FastSharedApp/Scenes/PaywallTierCard.swift`.

**Intent:** Props: `product: StoreProductView`, `tier: ProTier`, `features: [String]`, `badge: CardBadge?` (`.savePercentage(Int)` / `.earlyAccess(endsAt: Date?)` / nil), `isLoading: Bool`, `onPurchase: () -> Void`. VStack: title3 tier name, `.largeTitle.monospacedDigit()` price, caption cadence, checkmark-bulleted features (`Image(systemName: "checkmark.circle.fill")` in `BrandPalette.ember`), CTA button bottom. Badge pill via `.overlay(alignment: .topTrailing)`. Card chrome: `RoundedRectangle(cornerRadius: 16)` filled `BrandPalette.paper`, `BrandPalette.line` stroke. Annual card uses `BrandPalette.arc` gradient stroke ("recommended" signal).

Feature copy (English, flag `TODO(i18n)`):
- Monthly: unlimited daily uploads · files up to 5 GB · retention up to 30 days · cross-device sync.
- Annual: same + "Save ~45% vs monthly".
- Lifetime: all monthly features · one-time payment · future Pro features included.

**Depends:** B2.2. **Verify:** Build, preview all three tiers. **Acceptance:** CTA disables when `isLoading`.

---

### B2.4 — Purchase flow + haptic + dismiss animation

**Files (modify):** `apple/FastSharedApp/Scenes/PaywallView.swift`.

**Intent:** CTA → `Task { await subscriptionStore.purchase(productID) }`. Track `@State var purchasing: String? = nil` keyed by product ID. On `.success`: iOS `UINotificationFeedbackGenerator().notificationOccurred(.success)`; macOS `NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)`. Dismiss with `.animation(.spring(response: 0.4, dampingFraction: 0.8))`. `.userCancelled` → reset loading. `.pending` → inline info banner "Waiting for approval". `.verificationFailed` → inline error banner + "Try again". Restore → `Task { try await subscriptionStore.restore() }`, same post-flow. Privacy/Terms → `openURL` to `https://fastsha.red/privacy|/terms` (Plan C stubs are fine).

**Depends:** B2.3, B1.4. **Verify:** Build; manual in simulator with `.storekit` config → buy monthly → dismisses with spring; `isPro` flips. **Acceptance:** All `PurchaseOutcome` cases handled.

---

### B2.5 — Lifetime Early-Access badge (client flag + deferred server flag)

**Files (modify):** `apple/FastSharedApp/Scenes/PaywallView.swift`, `.../Subscription/SubscriptionStore.swift`. **Create:** `.../Subscription/PricingFallback.swift`.

**Intent:** `refreshProducts()` also calls `apiClient.fetchPricingFlags()` and stores on snapshot. MVP rule: if snapshot's `pricingFlags` is nil (server not shipped yet) AND `FastSharedPricingFallback.lifetimeEarlyAccessActive == true` (hardcoded `true` in `PricingFallback.swift`), show the badge. Add `TODO(tech-debt): remove once Plan A ships /v1/pricing-flags`. Badge copy: `"Early Access — ends \(formattedDate)"` if `earlyAccessEndsAt` provided, else `"Early Access"`.

**Depends:** B2.3, B1.5. **Verify:** Preview with flag off → no badge; with flag on → badge. **Acceptance:** No crash when flags nil.

---

### B2.6 — Accessibility / Dynamic Type / Reduce Motion

**Files (modify):** `PaywallView.swift`, `PaywallTierCard.swift`.

**Intent:**
- Every interactive element gets `.accessibilityLabel` + `.accessibilityHint` where action is non-obvious. Restore hint: "Reactivates your existing Pro subscription on this device". Close button: `.accessibilityAddTraits(.isButton)`, label "Close paywall".
- Replace all `.font(.system(size: N))` with Dynamic Type variants (`.title3`/`.body`/`.caption`). Clamp range: `.dynamicTypeSize(.xSmall ... .accessibility3)` on the root `ScrollView`.
- `@Environment(\.accessibilityReduceMotion) var reduceMotion`. When true: dismiss wraps `.transaction { $0.animation = nil }`; spring becomes no-op; scale/opacity transitions skip.
- Tier card: `.accessibilityElement(children: .combine)` with full spoken label (example annual): `"Annual plan, 29 dollars 99 cents per year, save 45 percent vs monthly. Unlimited uploads. Files up to 5 gigabytes. Retention up to 30 days. Cross-device sync. Double tap to subscribe."`

**Depends:** B2.4. **Verify:** Simulator + Accessibility Inspector → VoiceOver walks the sheet with meaningful labels, no unlabeled buttons; Dynamic Type `.accessibility1` renders without truncation on iPhone 15. **Acceptance:** Reduce Motion disables animations.

---

### B2.7 — Snapshot test at three trigger contexts

**Files (create):** `apple/Packages/FastSharedCore/Tests/FastSharedCoreTests/PaywallSnapshotTests.swift`, `.../Resources/PaywallSnapshots/*.png`.

**Intent:** Use `ImageRenderer` (zero deps). Render `PaywallView` at fixed 390×844 for three `PaywallTriggerContext` cases; hash the PNG; compare to baseline. WHY not pixel-diff: one-file, dep-free signal against silent regressions. If flaky across Xcode versions, swap to `swift-snapshot-testing` later.

**Depends:** B2.6. **Verify:** `swift test --filter PaywallSnapshotTests`. **Acceptance:** Passes on first run after baselines captured; re-run identical.

---

### B2.8 — Code Review Checkpoint (Part 2) — `/ring-default:codereview`

Focus: inherits `preferredColorScheme(.light)` (doesn't override); `TODO(i18n)` present on every English string; a11y labels comprehensive without redundancy; zero hardcoded hex (BrandPalette exclusively).

**Acceptance:** Zero C/H/M open.

---

## Part 3 — Upsell Triggers

### B3.1 — Install `PaywallCoordinator` + sheet host at roots

**Files (modify):** `apple/FastSharedApp/RootView.swift`, `apple/FastSharedApp/FastSharedApp.swift`, `apple/FastSharedShareExt/ShareRootView.swift` (add a second coordinator attachment here).

**Intent:** One `PaywallCoordinator` at `FastSharedApp` level; inject into env. `RootView.mainContent` attaches `.sheet(item: $coordinator.pending) { PaywallView(trigger: $0) }`. Share extension instantiates its own coordinator (separate process, no state shared) and attaches the same sheet in `ShareRootView`.

**Depends:** B2.1, B2.6. **Verify:** Debug button calling `coordinator.present(.dailyCapReached(used: 3, cap: 3))` → sheet appears in both surfaces. **Acceptance:** Sheet present + dismiss clean in both.

---

### B3.2 — Trigger 1: 4th link-of-day (Free)

**Files (modify):** `apple/Packages/FastSharedCore/Sources/FastSharedCore/Upload/UploadService.swift`, `apple/FastSharedApp/Scenes/HistoryView.swift`, `apple/FastSharedShareExt/ShareViewController.swift`.

**Intent:** `UploadService.enqueue` grows a `try await preflightQuotaAndCaps(size:, retention:, tier:)` call that consults `UsageTracker.currentCount()` + `TierCaps.dailyUploadLimit`. On cap reached, throws `SubscriptionGate.dailyCapReached(used:, cap:)`. Callers (main app + share ext + App Intent via `UploadServiceLocator`) catch and call `coordinator.present(.dailyCapReached(used:, cap:))`. WHY at service layer: single funnel covers all three UI surfaces — findability-before-duplication.

**Depends:** B3.1, B4.1–B4.3 (schedule AFTER Part 4 starts). **Verify:** Manual: 3 uploads OK as Free; 4th → paywall in both main app and share sheet; no staged-file leak on block. **Acceptance:** Block surfaces paywall without upload side effects.

---

### B3.3 — Trigger 2: "Sync across devices" Settings toggle

**Files (modify):** `apple/FastSharedApp/Scenes/SettingsView.swift`.

**Intent:** New `Section("Pro")` above "Backend". Row: `Toggle(isOn: $syncEnabled)` labelled "Sync across devices". Free tier: toggle visually `off` + `disabled(true)`, with a transparent full-row `Button` overlay that captures taps and calls `coordinator.present(.cloudSyncRequested)` (WHY overlay: disabled controls don't accept taps). Trailing `lock.fill` in `BrandPalette.dust`. Pro tier: toggle live; ON → start `CloudKitSyncEngine` (Part 5); OFF → stop engine but KEEP cloud data. Persist pref in App Group defaults key `cloud_sync_enabled_v1` (default `true` for Pro).

**Depends:** B3.1. **Verify:** Manual both tiers. **Acceptance:** Free → paywall; Pro → toggle persists across launches.

---

### B3.4 — Trigger 3: gated TTL picker (>24h presents paywall)

**Files (create):** `apple/FastSharedApp/Components/GatedRetentionPicker.swift`. **Modify:** `apple/FastSharedShareExt/ShareRootView.swift` (`IdleStage.retentionSection`), `apple/FastSharedApp/Scenes/SettingsView.swift` (default retention picker).

**Intent:** Replace both in-place `Picker("Link valid for"/"Default retention", selection:)` call sites with `GatedRetentionPicker(selection:, tier:, onPaywall:)`. Behavior:
- Shows all `.shareable` options always (`oneHour`/`oneDay`/`oneWeek`/`oneMonth`).
- For Free, options where `ttlSeconds > 86_400` render a trailing `lock.fill` (`BrandPalette.dust`). On `onChange`, if the new value is gated, revert the binding and call `onPaywall(.longRetentionRequested(policy: newValue))`.
- For Pro, vanilla behavior.
- WHY show-with-lock, not hide: one-tap discovery of Pro, aligned with scope.

**Depends:** B3.1. **Verify:** Build; manual in share ext: Free taps "1 week" → paywall opens; selection stays on "1 day". **Acceptance:** No double-fire, binding reverts cleanly.

---

### B3.5 — Trigger 4: 402 Payment Required handler

**Files (modify):** `apple/Packages/FastSharedCore/Sources/FastSharedCore/Networking/APIError.swift` (add `.paymentRequired(errorCode: String, problem: Problem?)`); `APIClient.swift` `validate(_:data:)` → map 402 to new case; `HistoryView.swift` + `ShareViewController.swift` → catch and route to `coordinator.present(.serverForced(errorCode:))`.

**Intent:** Belt-and-suspenders above Part 4 client gates. Server-side Plan A may refuse with 402 + `Problem.code` (e.g. `pro_required`, `file_too_large_free`). Code is passed through for analytics.

**Depends:** B3.1. **Verify:** Unit test `APIErrorTests.test_402_decodes_to_paymentRequired` with synthetic HTTP stub. **Acceptance:** Typed error surfaces; caller maps to paywall.

---

### B3.6 — Code Review Checkpoint (Part 3) — `/ring-default:codereview`

Focus: all three triggers route through `PaywallCoordinator` (no rogue `.sheet(isPresented:)`); gated picker doesn't leak selection to persistence; single source of truth in `GatedRetentionPicker`.

**Acceptance:** Zero C/H/M open.

---

## Part 4 — Free-Tier Gating (UsageTracker)

### B4.1 — `UsageTracker` actor

**Files (create):** `apple/Packages/FastSharedCore/Sources/FastSharedCore/Usage/UsageTracker.swift`.

**Intent:** Actor with:

```swift
public protocol UsageTrackerProtocol: Sendable {
    func currentCount() async -> Int
    func increment() async -> Int
    func remaining(for tier: Tier) async -> Int
    #if DEBUG
    func reset() async
    #endif
}
```

State: `counts: [String: Int]` keyed `"yyyy-MM-dd"` in **UTC**. Every read/mutation prunes keys older than 3 days. WHY UTC: cross-device Pro syncing across timezones must not double-count; local midnight is UX-only (Part 6). Persistence: `UserDefaults(suiteName: AppGroupPaths.groupIdentifier)`, key `usage_counts_v1`, JSON-encoded `[String: Int]`. WHY UserDefaults (not SwiftData): the share extension reads/writes before SwiftData wiring; cheap; already used for onboarding + retention. Lazy-load on first call. Writes debounce via single-flight task, 250 ms.

Inject a `Clock` protocol (one method `func todayKey() -> String`) so calendar rollover tests aren't flaky; prod default: `Calendar.current` + UTC `TimeZone`.

**Depends:** B1.1. **Verify:** `swift build`. **Acceptance:** Strict concurrency clean.

---

### B4.2 — `UsageTracker` unit tests

**Files (create):** `apple/Packages/FastSharedCore/Tests/FastSharedCoreTests/UsageTrackerTests.swift`.

**Intent:** Cover:
1. `test_initialCount_isZero`.
2. `test_increment_isMonotonic` — 3 sequential increments → 1, 2, 3.
3. `test_persistsAcrossActorRestarts` — discard + re-init with same suite.
4. `test_dayRollover_viaInjectedClock` — fake "yesterday", increment, advance to "today", count is 0.
5. `test_remaining_forFree_cappedAt3` — after 2 increments → 1 remaining.
6. `test_remaining_forPro_returnsIntMax` (or `.unlimited` sentinel).
7. `test_prunesOldKeys` — 10-day-old key is gone after flush.

**Depends:** B4.1. **Verify:** `swift test --filter UsageTrackerTests 2>&1 | tail -5` → 7 tests, 0 failures. **Acceptance:** All 7 pass.

---

### B4.3 — Wire `UsageTracker.increment()` into successful uploads

**Files (modify):** `apple/Packages/FastSharedCore/Sources/FastSharedCore/Upload/UploadOrchestrator.swift`.

**Intent:** On transition to `succeeded` (after `complete` API returns 2xx), call `UsageTracker.shared.increment()`. Do NOT increment on dedupe hits (`PresignResponse.deduped` path): server-recognized idempotency doesn't consume quota. Code comment: `// WHY: deduped responses don't consume the quota; they're server-side idempotency.` `UsageTracker.shared` is singleton — both share ext and main app funnel via `UploadOrchestrator`.

**Depends:** B4.1. **Verify:** `swift test --filter UploadServiceTests` green + two new tests: `test_successfulUpload_incrementsUsage`, `test_dedupedResponse_doesNotIncrement`. **Acceptance:** Existing tests unaffected.

---

### B4.4 — Pre-flight file-size check (Free + >100 MB → paywall)

**Files (modify):** `apple/FastSharedShareExt/ShareViewController.swift` (before `service.enqueue` in `performUpload`), `apple/FastSharedApp/Scenes/HistoryView.swift` (drag-drop / file-picker accept path — inspect first).

**Intent:** Read `TierCaps.maxFileSizeBytes` from `SubscriptionStore.currentSnapshot().caps`. If `sizeBytes > cap`, call `coordinator.present(.largeFileRequested(sizeBytes:))` and abort. Keep staged file for 30 s in share ext (user might buy Pro and retry immediately). Use cancellable `Task`: on paywall dismiss without purchase within 30 s, clean up staging; on Pro granted, retry upload.

**Depends:** B1.1, B3.1. **Verify:** Manual — 200 MB file as Free → paywall; cancel → staging cleaned; purchase → upload proceeds. **Acceptance:** No staging leak on cancel.

---

### B4.5 — Pre-flight quota check

**Files (modify):** `apple/Packages/FastSharedCore/Sources/FastSharedCore/Upload/UploadService.swift`.

**Intent:** Backs B3.2 with actual `UsageTracker` data. `preflightQuotaAndCaps` consults `UsageTracker.currentCount()`; throws `SubscriptionGate.dailyCapReached(used:, cap:)` when `used >= cap`. Callers already handle via B3.2.

**Depends:** B4.1, B3.2. **Verify:** Unit test `test_enqueue_onFreeAtCap_throwsSubscriptionGate`. **Acceptance:** Error is typed (`SubscriptionGate`), not generic `.transport` or `.http`.

---

### B4.6 — Code Review Checkpoint (Part 4) — `/ring-default:codereview`

Focus: UTC vs local correctness; actor write-coalescing doesn't drop increments; pre-flight size path has clean rollback (no half-staged files on cancel).

**Acceptance:** Zero C/H/M open.

---

## Part 5 — CloudKit Metadata Sync (Pro-only)

### B5.1 — Entitlements for CloudKit (+ manual ASC container step)

**Files (modify):** `apple/FastSharedApp/FastSharedApp.entitlements`, `apple/FastSharedShareExt/FastSharedShareExt.entitlements`.

**Intent:** Add to BOTH entitlements:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array><string>iCloud.dev.kindrazki.fastshared</string></array>
<key>com.apple.developer.icloud-services</key>
<array><string>CloudKit</string></array>
```

Do NOT add `ubiquity-container-identifiers` or `ubiquity-kvstore-identifier` — no iCloud Drive / KVS. WHY share ext too: share ext pushes on upload success.

**Manual blocker (flag in PR description):** ASC → Identifiers → iCloud Containers → create `iCloud.dev.kindrazki.fastshared`, enable for both App IDs. Without this, no code below works.

**Depends:** none. **Verify:** `plutil -lint` both → OK. `xcodegen generate && xcodebuild … build` succeeds (provisioning may warn pre-container registration — flag, don't block). **Acceptance:** Builds; container registered in portal.

---

### B5.2 — `ShareLinkRecord` schema constants

**Files (create):** `apple/Packages/FastSharedCore/Sources/FastSharedCore/CloudKit/ShareLinkRecord.swift`.

**Intent:** Pure-data file. One source of truth for field names:

```swift
public enum ShareLinkRecord {
    public static let recordType = "ShareLinkRecord"
    public static let containerID = "iCloud.dev.kindrazki.fastshared"
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
}
```

Plus two extensions in the same file:
- `extension ShareLinkEntity { func toCKRecord(deviceId: UUID, in zoneID: CKRecordZone.ID) -> CKRecord }`
- `extension CKRecord { func asShareLinkEntity() throws -> ShareLinkEntity }`

**Depends:** none. **Verify:** `swift build`. **Acceptance:** Builds.

---

### B5.3 — `CloudKitSyncEngine` actor skeleton using `CKSyncEngine`

**Files (create):** `apple/Packages/FastSharedCore/Sources/FastSharedCore/CloudKit/CloudKitSyncEngine.swift`.

**Intent:** `actor CloudKitSyncEngine` wrapping `CKSyncEngine`.

```swift
public protocol CloudKitSyncEngineProtocol: Sendable {
    func start() async throws
    func stop() async
    var isRunning: Bool { get async }
}
```

Init deps: `SwiftDataStore`, `SubscriptionStoreProtocol`, `deviceId: UUID`, `UserDefaults` for `CKSyncEngine.State.Serialization` (key `cksync_state_v1`).

Sketch:
- `start()` guards `isPro` (else throws `.notSubscribed`). Builds `CKSyncEngine.Configuration` for `iCloud.dev.kindrazki.fastshared` private DB; state loaded from defaults if present.
- `CKSyncEngineDelegate` nested class handles three event families: `.stateUpdate` (persist `event.stateSerialization`); `.fetchedRecordZoneChanges` (each `.modification` decodes `CKRecord → ShareLinkEntity` and upserts via SwiftData main context; each `.deletion` hard-deletes by token); `.sentRecordZoneChanges` (logs success; partial failures pushed back into `state.pendingRecordZoneChanges`).
- `stop()` nils out engine + cancels observation tasks; does NOT delete any cloud records.

Check `CKSyncEngineDelegate` actor isolation at implementation time (iOS 17.4 variants differ) — hop as needed.

**Depends:** B5.1, B5.2. **Verify:** `swift build`. **Acceptance:** Compiles; no sync yet.

---

### B5.4 — SwiftData change observation → `pendingRecordZoneChanges`

**Files (modify):** `apple/Packages/FastSharedCore/Sources/FastSharedCore/Persistence/SwiftDataStore.swift` (add `AsyncStream<PersistenceEvent>` surface), `apple/Packages/FastSharedCore/Sources/FastSharedCore/ShareLinks/ShareLinkService.swift` (fire events on each write — inspect this file first), `CloudKitSyncEngine.swift` (subscribe + translate).

**Intent:** Today `SwiftDataStore` has no observation surface. Add lightweight `AsyncStream<PersistenceEvent>` where `PersistenceEvent = { .shareLinkInserted(token), .shareLinkUpdated(token), .shareLinkDeleted(token) }`. Fire from every `ShareLinkEntity` mutation site. Engine translates each event to `.saveRecord(recordID)` / `.deleteRecord(recordID)` and `engine.state.add(pendingRecordZoneChanges:)`. WHY AsyncStream not `NotificationCenter`: cleaner `Sendable` story under strict concurrency; `Notification.userInfo` is not `Sendable`.

**Depends:** B5.3. **Verify:** `swift build`. **Acceptance:** Inserting an entity shows up in `pendingRecordZoneChanges`.

---

### B5.5 — Gate engine on `isPro && settingsToggle`

**Files (modify):** `apple/FastSharedApp/FastSharedApp.swift`, `CloudKitSyncEngine.swift`, `apple/FastSharedShareExt/ShareViewController.swift`.

**Intent:** One `CloudKitSyncEngine` per process. Task observes `subscriptionStore.snapshotStream`:
- First Pro snapshot with `allowsCloudSync` → `await engine.start()`.
- Transition to not-Pro → `await engine.stop()`. DO NOT delete records (Apple retains them in the user's private DB until they disable iCloud for the app).
- User may also manually toggle sync off while Pro; engine run state is `(isPro) && (settingsToggleOn)`.

Settings pref in `cloud_sync_enabled_v1` (default `true` for Pro). Share extension has its OWN engine (separate process); CKSyncEngine handles server-side coordination via shared zone state.

**Depends:** B5.4. **Verify:** Manual: Pro → `isRunning == true`; simulate refund via `.storekit` `interruptionFlag` → `false` within ~2 s. Console.app log lines. **Acceptance:** Start/stop tracks `(isPro && toggleOn)`.

---

### B5.6 — `CloudKitSyncEngine` tests with a mock kernel

**Files (create):** `apple/Packages/FastSharedCore/Tests/FastSharedCoreTests/CloudKitSyncEngineTests.swift`.

**Intent:** `CKSyncEngine` is final / CloudKit-owned and not easily mockable. Wrap behind `protocol SyncEngineKernel` with `addPending(_:)`, `subscribe(delegate:)`, `isRunning: Bool`. Production adapter → `CKSyncEngine`; tests → `InMemorySyncEngineKernel` recording calls.

Tests:
1. `test_start_whenNotPro_throwsNotSubscribed`.
2. `test_start_whenPro_setsRunningTrue`.
3. `test_localInsert_schedulesPendingSave` — fire `.shareLinkInserted`; mock kernel's pending list contains `.saveRecord` for that token.
4. `test_localDelete_schedulesPendingDelete`.
5. `test_remoteFetchedRecord_upsertsSwiftData` — hand synthetic `CKRecord` to delegate; assert entity present in in-memory SwiftData.
6. `test_proToFree_transitionStopsEngine`.
7. `test_conflictResolution_lastWriteWins` — two updates with different `modificationDate`; later wins.

**Depends:** B5.5. **Verify:** `swift test --filter CloudKitSyncEngineTests 2>&1 | tail -5` → 7 tests, 0 failures. **Acceptance:** All 7 pass.

---

### B5.7 — Code Review Checkpoint (Part 5) — `/ring-default:codereview`

Focus: data retention on Free transition (code MUST NOT call `.deleteRecord` on downgrade); state serialization loss on uninstall is expected + handled (fresh state); no MainActor hops in hot paths; share ext engine doesn't race main app on shared zone.

**Acceptance:** Zero C/H/M open.

---

## Part 6 — Tier Caps UX

### B6.1 — Cache caps from `/v1/me`

**Files (modify):** `apple/Packages/FastSharedCore/Sources/FastSharedCore/Subscription/SubscriptionStore.swift`.

**Intent:** Extends B1.6. After any successful `verifyIAP` and once on app launch, call `apiClient.fetchMe()` and merge caps into snapshot. Server-supplied caps OVERRIDE local defaults — lets us tune tiers server-side without a new app build. Cache full `MeResponse` in App Group defaults so cold launch renders last-known caps instantly.

**Depends:** B1.6. **Verify:** Add test `test_afterVerify_fetchesMe_andMergesCaps`. **Acceptance:** Snapshot caps reflect server response.

---

### B6.2 — "Uploads today" row in Settings

**Files (modify):** `apple/FastSharedApp/Scenes/SettingsView.swift`.

**Intent:** New `Section("Usage")` above Pro section. Row "Uploads today" trailing `"2 / 3"` for Free or `"47 / ∞"` for Pro (`∞` via `Image(systemName: "infinity")`). Quieter second line: "Resets at \(localMidnight.formatted(.dateTime.hour().minute()))" — local midnight for display, even though counter is UTC-keyed. Use `TimelineView(.periodic(from: .now, by: 60))` so the reset line stays fresh. Data: `@Environment(\.subscriptionStore)` for caps, `UsageTracker.shared` for count.

**Depends:** B4.1, B6.1. **Verify:** Manual both tiers. **Acceptance:** Renders correctly; `TimelineView` scoped to the row only.

---

### B6.3 — Silent re-verify on cold launch (app + share ext)

**Files (modify):** `apple/FastSharedApp/FastSharedApp.swift`, `apple/FastSharedShareExt/ShareViewController.swift`.

**Intent:** On launch, after `syncCurrentEntitlements()`, iterate `Transaction.currentEntitlements` once more and explicitly `await apiClient.verifyIAP(signedTransactionJWS:)` for each signed tx. Backend is idempotent, safe. WHY: device-local Apple state may be ahead of our server (e.g. user renewed on another device via Family); this nudges server forward. Log `verify replay count=\(n)`. Share ext does this too — live surface must not render stale Free UI for a known-Pro user.

**Depends:** B1.6, B6.1. **Verify:** Fresh install, existing Pro sub → no "Free flash" on launch; Pro visible within 1–2 s. **Acceptance:** Idempotent; not spammed on every foreground.

---

### B6.4 — Code Review Checkpoint (Part 6) — `/ring-default:codereview`

Focus: replay is idempotent + not per-foreground; `TimelineView` scope isn't burning CPU; Pro unlimited renders as `∞`, never `nil`/`"999"`.

**Acceptance:** Zero C/H/M open.

---

## Part 7 — Integration + Handoff

### B7.1 — E2E manual test matrix

**Files (create):** `docs/plan/pro-feature-B-apple-qa-matrix.md`.

**Intent:** One-page checklist run on physical iPhone + Simulator + Mac with Sandbox Apple ID. Matrix:
- Fresh install Free → 3 uploads OK, 4th → paywall.
- Buy monthly → 4th upload succeeds; caps row flips.
- Buy annual → cancel in TestFlight → after expiry window, Pro downgrades cleanly (engine stops; no data deletion).
- Buy lifetime → reinstall → `restore()` reinstates Pro.
- Two-device sync: Pro on A → sync on → upload → Pro on B (sync on) receives `ShareLinkEntity` within 30 s.
- 200 MB file as Free → paywall; as Pro → uploads.
- "1 week" TTL as Free → paywall; as Pro → uploads with correct TTL.

Not automated — Apple Sandbox + physical-device dependent.

**Depends:** All of Parts 1–6. **Acceptance:** Checklist committed; manual pass logged in PR description.

---

### B7.2 — Docs + TODO sweep

**Files (modify):** `apple/README.md` (short "Pro subscription" section linking to this plan).

**Intent:** Grep for `TODO(review)`, `FIXME(nitpick)`, `TODO(i18n)`, `TODO(tech-debt)`, `TODO(post-mvp)`. Each must be expected and tracked (Linear ticket or this doc). Low-severity review TODOs from checkpoints must still be present (not silently removed).

**Verify:** `rg "TODO\(review\)|FIXME\(nitpick\)|TODO\(i18n\)|TODO\(tech-debt\)|TODO\(post-mvp\)" apple/` → every line expected.

**Acceptance:** README updated; TODO sweep clean.

---

### B7.3 — Final code review (full-plan sweep) — `/ring-default:codereview`

Reviewers cover every file touched in B1–B7. Focus: no hardcoded Apple team / product / container strings outside `ProTier` and `ShareLinkRecord`; strict concurrency clean package-wide; every new public API in `FastSharedCore` has a doc comment.

**Acceptance:** Zero C/H/M open → Plan B ready for PR merge.

---

## Parallelism map

- **Wave 1 (parallel):** B1.1, B1.5, B1.7, B5.1, B5.2.
- **Wave 2 (serial chain):** B1.2 → B1.3 → B1.4 → B1.6. **Parallel lane:** B4.1 → B4.2.
- **Wave 3 (parallel):** B1.8, B1.9, B2.1.
- **Wave 4 (serial chain):** B2.2 → B2.3 → B2.4 → B2.5 → B2.6 → B2.7.
- **Wave 5:** B3.1 → then {B3.2 (needs Part 4), B3.3, B3.4, B3.5} in parallel. B4.3 → B4.4 → B4.5 feed B3.2.
- **Wave 6 (serial):** B5.3 → B5.4 → B5.5 → B5.6.
- **Wave 7 (serial):** B6.1 → B6.2 → B6.3.
- **Wave 8:** B7.1, B7.2, B7.3 (B7.3 last).

## Failure recovery (universal)

1. **Build broken after entitlement/xcconfig edit:** `xcodegen generate` + `xcodebuild clean`. xcconfig/entitlement changes don't reach Xcode until regen.
2. **Strict concurrency error:** do NOT silence with `nonisolated(unsafe)`. Prefer actor isolation / `@MainActor` adjustments.
3. **StoreKitTest: "unable to find storekit configuration":** confirm `project.yml` scheme `test.storeKitConfiguration` set + regenerate.
4. **Simulator CloudKit auth failure:** Settings → Apple ID → Sign In. Last resort `xcrun simctl erase booted`.
5. **Provisioning fails for CloudKit container:** container not in ASC. See B5.1 manual blocker.
6. **Paywall doesn't dismiss on macOS:** `@Environment(\.dismiss)` works on iOS; on macOS sheet semantics differ — use `NSApp.keyWindow?.endSheet(_:)` if needed.
7. **Can't recover:** write a scratch file `docs/plan/pro-feature-B-apple-notes.md` describing the failure; stop; escalate.

## Plan checklist

- [x] Header with goal, architecture, tech stack, prerequisites, verification.
- [x] Tasks bite-sized; intent-level descriptions; brief stubs only where shape clarifies.
- [x] Exact file paths for every file.
- [x] Verification commands with expected output.
- [x] Code review checkpoint per Part (B1.10, B2.8, B3.6, B4.6, B5.7, B6.4, B7.3).
- [x] Failure recovery + parallelism map.
- [x] BrandPalette-only (no hardcoded hex in tasks).
- [x] App Group counter reachable by both processes.
- [x] Pro downgrade never deletes cloud records.
- [x] Zero-Context Test: any Swift engineer can pick up any task.
