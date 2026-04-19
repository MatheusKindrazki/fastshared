# Plan B — Pro Feature (Apple) Followups

Non-blocking items deferred from Plan B execution. Convert to Linear tickets before shipping 2.0.

## Manual blockers (must happen before the first Pro user)

- **ASC iCloud container** — `iCloud.dev.kindrazki.fastshared` must be
  created in App Store Connect under Identifiers → iCloud Containers,
  then enabled on both App IDs (`dev.kindrazki.fastshared` and
  `dev.kindrazki.fastshared.ShareExt`). Without this step the
  `CloudKitSyncEngine` cannot connect; build compiles and runs, but
  `start()` returns a CloudKit auth error on device.
- **ASC In-App Purchases** — the three SKUs in `FastShared.storekit`
  must be registered in ASC with matching product IDs, pricing, and
  subscription group (`pro_access`). Until registered, device purchases
  fail; local `.storekit` file keeps the simulator flow working.
- **Apple App Privacy answers** — the paywall adds IAP. The App
  Store Connect App Privacy form must enumerate "Purchases" and "User ID"
  data collection (for matching JWS → server subscription row). Plan A
  owners should coordinate.

## Known deferrals in code (tracked by grep markers)

- `TODO(tech-debt)` — `PricingFallback.swift` — remove once Plan A ships
  `/v1/pricing-flags` and the snapshot is guaranteed non-nil.
- `TODO(i18n)` — every English string on the paywall UI (`PaywallView`,
  `PaywallTierCard`, `SharePaywallSheet`, `GatedRetentionPicker`). Wrap
  these in `String(localized:)` once the ship-blocker locale set is
  chosen (likely en + pt-BR given the author's market).
- `TODO(post-mvp)` — Family Sharing and promo codes in `PaywallView`.
  Monthly & Annual carry `familyShareable: false` in
  `FastShared.storekit`; Lifetime is `familyShareable: true` but we
  don't surface the "Share with Family" affordance anywhere.

## Architectural defers

- **StoreKit-driven UI tests.** `SubscriptionStoreTests` runs without a
  StoreKit configuration file because SwiftPM test targets don't host an
  app. The full purchase flow is instead exercised manually via the QA
  matrix. Future option: move the StoreKit-facing tests to an XCTest
  target attached to `FastSharedApp` scheme.
- **Paywall snapshot tests (B2.7)** — skipped. `ImageRenderer`-based
  snapshot tests would need a host app scheme, not the package test
  target. Defer to a dedicated UI test target in a follow-up.
- **JWS vs JSON payload for `/v1/iap/verify`.** The client currently
  sends `Transaction.jsonRepresentation`. The backend in Plan A is
  specced to detect JSON-vs-JWS shapes. When Plan A merges, verify the
  decision with their endpoint and adjust if they want pure JWS.
- **Pending transaction polling in the paywall.** `PurchaseOutcome.pending`
  shows a banner but doesn't listen for the eventual approval — the
  `Transaction.updates` actor task picks it up via snapshot stream, so
  UX is fine, but the paywall doesn't auto-dismiss on pending→approved.
  Consider wiring this via the snapshot listener for tighter feedback.

## Review low-severity TODOs

None emitted yet — review checkpoints run inline and produce `TODO(review):` markers only when a non-blocking finding is deferred. Add entries here if any accumulate.
