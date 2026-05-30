import SwiftUI
import FastSharedCore

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

/// Sign in with Apple — Friendly redesign.
///
/// Hero mark + pitch + official Apple button + guest escape hatch + legal.
/// Conta é opcional: o botão "Continue without syncing" permite prosseguir
/// como guest. Sync via CloudKit só ativa depois que o usuário entra.
///
/// State is persisted in App Group defaults so main app + share extension
/// observe the same "signed-in-or-guest" flag.
struct SignInView: View {
    let onComplete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.apiClient) private var apiClient
    @State private var errorMessage: String?
    @State private var isSubmitting: Bool = false

    // WHY: used to (a) pass the guest's anonymous device token to the backend
    // as `claimDeviceToken` and (b) persist the freshly-minted post-sign-in
    // token. Built from the same App Group suite the rest of the app uses.
    private let tokenStore = DeviceTokenStore()

    // Adaptive tokens — HIG semantic; adapts to light/dark.
    private var groundColor: Color { Color.sysBackground }
    private var textColor: Color { Color.sysLabel }
    private var textDim: Color { Color.sysSecondaryLabel }
    private var textFaint: Color { Color.sysTertiaryLabel }

    var body: some View {
        ZStack {
            groundColor.ignoresSafeArea()

            // Soft radial bloom behind the mark (light theme only)
            if colorScheme == .light {
                RadialGradient(
                    colors: [BrandPalette.accentHot.opacity(0.08), .clear],
                    center: .init(x: 0.5, y: 0.22),
                    startRadius: 0,
                    endRadius: 280
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                // Top anchor — small lockup
                BrandLockup(markSize: 22, textSize: 15)
                    .padding(.top, 8)

                // Hero
                VStack(spacing: 0) {
                    PlaneArcMark(size: 108, ambient: true)

                    Text("Sign in to sync\nyour shares.")
                        .font(.system(size: 30, weight: .bold))
                        .tracking(-0.9)
                        .lineSpacing(0.08 * 30)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(textColor)
                        .padding(.top, 28)

                    Text("Your active links stay in sync across iPhone, iPad, and Mac. Nothing about the files themselves leaves your device.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(textDim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(15 * 0.2)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .frame(maxWidth: 300)
                }
                .frame(maxHeight: .infinity)
                .padding(.vertical, 20)

                // Actions
                VStack(spacing: 12) {
                    // WHY: `SignInWithAppleButton` + `APIClient.signInWithApple`
                    // are both cross-platform. This used to be `#if os(iOS)` with
                    // no macOS fallback, so the Mac build shipped with no way to
                    // sign in — the cause of the 1.0.1 App Review rejection.
                    ZStack {
                        SignInWithAppleButton(
                            .signIn,
                            onRequest: { request in
                                request.requestedScopes = [.fullName, .email]
                            },
                            onCompletion: handleAppleResult
                        )
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .disabled(isSubmitting)
                        .opacity(isSubmitting ? 0.55 : 1)

                        if isSubmitting {
                            // WHY: the Apple button is a system control we can't restyle,
                            // so we overlay the spinner instead of trying to swap its label.
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                                .tint(colorScheme == .dark ? .black : .white)
                                .allowsHitTesting(false)
                        }
                    }

                    // Guest escape hatch
                    Button {
                        AuthState.markSignedInOrGuest(mode: .guest)
                        onComplete()
                    } label: {
                        Text("Continue without syncing")
                            .font(.system(size: 15, weight: .medium))
                            .tracking(-0.15)
                            .foregroundStyle(textDim)
                            .frame(height: 48)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)

                    // Legal
                    legalText
                        .padding(.top, -6)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 28)

            if let errorMessage {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(BrandPalette.urgencyCritical, in: Capsule())
                        .padding(.bottom, 120)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(duration: 0.35), value: errorMessage)
    }

    private var legalText: some View {
        HStack(spacing: 0) {
            Text("By continuing you accept our ")
                .foregroundStyle(textFaint)
            Text("Terms")
                .foregroundStyle(textDim)
                .fontWeight(.medium)
            Text(" · ")
                .foregroundStyle(textFaint)
            Text("Privacy")
                .foregroundStyle(textDim)
                .fontWeight(.medium)
        }
        .font(.system(size: 11))
        .multilineTextAlignment(.center)
        .lineSpacing(11 * 0.5)
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Unexpected credential type"
                return
            }
            // WHY: Apple returns the identity token + authorization code as Data
            // (UTF-8 encoded JWT/opaque string). Decode eagerly so we fail the
            // flow before kicking off the server round-trip if either is empty.
            guard
                let identityData = credential.identityToken,
                let identityTokenString = String(data: identityData, encoding: .utf8),
                !identityTokenString.isEmpty
            else {
                errorMessage = "Apple sign-in failed to return an identity token"
                return
            }
            guard
                let authCodeData = credential.authorizationCode,
                let authorizationCodeString = String(data: authCodeData, encoding: .utf8),
                !authorizationCodeString.isEmpty
            else {
                errorMessage = "Apple sign-in failed to return an authorization code"
                return
            }

            // WHY: PersonNameComponentsFormatter.localizedString is the iOS 15+
            // static API — avoids instantiating a formatter per call. Apple only
            // hands us fullName + email on the FIRST auth; subsequent sign-ins
            // return an empty PersonNameComponents which formats to "". The
            // server zod schema is `.string().min(1).optional()` so empty values
            // MUST become nil or the request 400s.
            let fullName: String? = credential.fullName
                .map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default, options: []) }
                .flatMap { $0.isEmpty ? nil : $0 }

            // Same story for email: Apple hides it on second auth. Treat empty
            // as nil so we don't send an empty string that fails .email() validation.
            let appleEmail = credential.email.flatMap { $0.isEmpty ? nil : $0 }
            let appleUserId = credential.user

            Task { await submitSignIn(
                identityToken: identityTokenString,
                authorizationCode: authorizationCodeString,
                fullName: fullName,
                email: appleEmail,
                appleUserId: appleUserId
            ) }

        case .failure(let error):
            let nsErr = error as NSError
            if nsErr.code == ASAuthorizationError.canceled.rawValue { return }
            errorMessage = nsErr.localizedDescription
        }
    }

    @MainActor
    private func submitSignIn(
        identityToken: String,
        authorizationCode: String,
        fullName: String?,
        email: String?,
        appleUserId: String
    ) async {
        isSubmitting = true
        defer { isSubmitting = false }

        // WHY: if the user was browsing as a guest, their uploads are tied to an
        // anonymous device token. Handing it to the backend lets it rebind those
        // rows to the new authenticated user so history isn't orphaned.
        let claimToken = (try? await tokenStore.load())?.token

        do {
            let response = try await apiClient.signInWithApple(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                fullName: fullName,
                email: email,
                claimingDeviceToken: claimToken
            )

            // WHY: we persist the server-issued bearer alongside a locally-minted
            // deviceId UUID. The backend keys auth off the token itself, so the
            // deviceId is just a local tag — not a security boundary.
            let newToken = DeviceToken(deviceId: UUID(), token: response.deviceToken)
            try await tokenStore.save(newToken)

            AuthState.markSignedInOrGuest(
                mode: .apple,
                userId: appleUserId,
                fullName: fullName,
                email: email
            )
            onComplete()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
        }
    }
}

// MARK: - Auth state (App Group persisted)

/// Lightweight auth flag shared between main app and share extension via
/// App Group defaults. This is NOT a real auth layer — real device token /
/// server session is handled by `DeviceTokenStore`. This is just the UX
/// marker ("has the user made a choice yet?").
public enum AuthState {
    public enum Mode: String {
        case apple
        case guest
    }

    public static let modeKey = "auth_mode_v1"
    public static let appleUserIdKey = "auth_apple_user_id"
    public static let appleNameKey = "auth_apple_full_name"
    public static let appleEmailKey = "auth_apple_email"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroupPaths.groupIdentifier) ?? .standard
    }

    public static var currentMode: Mode? {
        guard let raw = defaults.string(forKey: modeKey) else { return nil }
        return Mode(rawValue: raw)
    }

    public static var hasCompletedGate: Bool {
        currentMode != nil
    }

    /// Apple user identifier persisted after a successful Sign in with Apple
    /// round-trip. Read on launch so we can poll `ASAuthorizationAppleIDProvider`
    /// for revocation and force the gate back if the user nuked the app's
    /// permission from Settings → Apple ID → Sign in with Apple.
    public static var appleUserId: String? { defaults.string(forKey: appleUserIdKey) }

    /// Cached display name captured from the FIRST Apple auth (Apple only ships
    /// name/email on initial grant). Surfaced by later profile UIs.
    public static var fullName: String? { defaults.string(forKey: appleNameKey) }

    /// Cached email captured from the FIRST Apple auth.
    public static var email: String? { defaults.string(forKey: appleEmailKey) }

    public static func markSignedInOrGuest(
        mode: Mode,
        userId: String? = nil,
        fullName: String? = nil,
        email: String? = nil
    ) {
        defaults.set(mode.rawValue, forKey: modeKey)
        if let userId { defaults.set(userId, forKey: appleUserIdKey) }
        if let fullName { defaults.set(fullName, forKey: appleNameKey) }
        if let email { defaults.set(email, forKey: appleEmailKey) }
    }

    public static func reset() {
        defaults.removeObject(forKey: modeKey)
        defaults.removeObject(forKey: appleUserIdKey)
        defaults.removeObject(forKey: appleNameKey)
        defaults.removeObject(forKey: appleEmailKey)
    }
}

#Preview("Light") {
    SignInView(onComplete: {})
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SignInView(onComplete: {})
        .preferredColorScheme(.dark)
}
