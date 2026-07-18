//
//  AuthService.swift
//  StreakCounter
//
//  Created by Ryan Lin on 6/8/26.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import AuthenticationServices
import CryptoKit

final class AuthService: NSObject, ObservableObject {

    @Published private(set) var user: User?
    @Published private(set) var isWorking: Bool = false
    @Published var errorMessage: String?

    // Guest mode lets reviewers (and users without a Google/Apple account)
    // use the full app without authenticating.
    @Published var isGuest: Bool = false
    @Published var guestEmail: String = ""

    private var stateHandle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    /// Set while account deletion is re-running Sign in with Apple to get a
    /// fresh credential; the delegate resumes it instead of signing in.
    private var appleReauthContinuation:
        CheckedContinuation<(credential: AuthCredential, authorizationCode: String?), Error>?

    private let guestModeKey = "isGuestMode"
    private let guestEmailKey = "guestEmail"

    override init() {
        super.init()

        isGuest = UserDefaults.standard.bool(forKey: guestModeKey)
        guestEmail = UserDefaults.standard.string(forKey: guestEmailKey) ?? ""

        guard FirebaseApp.app() != nil else { return }

        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }

        user = Auth.auth().currentUser
        stateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                self.user = user
                // Signing into a real account exits guest mode automatically.
                if user != nil, self.isGuest {
                    self.exitGuestMode()
                }
            }
        }

        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] gidUser, _ in
            guard let gidUser = gidUser else { return }
            Task { @MainActor in
                await self?.firebaseSignIn(with: gidUser)
            }
        }
    }

    deinit {
        if let handle = stateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    var isSignedIn: Bool { user != nil || isGuest }

    /// Email we should send milestone messages to. Prefers the signed-in
    /// account's email; falls back to the guest-supplied address.
    var effectiveEmail: String? {
        if let email = user?.email, !email.isEmpty { return email }
        if isGuest, !guestEmail.isEmpty { return guestEmail }
        return nil
    }

    // MARK: - Guest mode

    func continueAsGuest() {
        isGuest = true
        UserDefaults.standard.set(true, forKey: guestModeKey)
    }

    func exitGuestMode() {
        isGuest = false
        UserDefaults.standard.set(false, forKey: guestModeKey)
    }

    func setGuestEmail(_ email: String) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guestEmail = trimmed
        UserDefaults.standard.set(trimmed, forKey: guestEmailKey)
    }

    // MARK: - Google

    @MainActor
    func signInWithGoogle() async {
        guard let rootVC = Self.topMostViewController() else {
            errorMessage = "Could not find a window to present sign-in."
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            await firebaseSignIn(with: result.user)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Apple

    @MainActor
    func signInWithApple() {
        let nonce = Self.randomNonceString()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        isWorking = true
        controller.performRequests()
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Account deletion

    /// Permanently deletes the user's synced data and their Firebase account.
    ///
    /// Deletes immediately when the login is recent. Firebase refuses to
    /// delete an account with a stale login, so only in that case is the
    /// user re-authenticated first. Returns true if the account was deleted.
    @MainActor
    func deleteAccount() async -> Bool {
        guard let user = Auth.auth().currentUser else { return false }

        isWorking = true
        defer { isWorking = false }

        do {
            // Remove the synced data first (only possible while still signed
            // in — Firestore rules require the matching uid), then the account.
            try await Firestore.firestore().collection("users").document(user.uid).delete()

            do {
                try await user.delete()
            } catch let error as NSError
                where error.domain == AuthErrorDomain
                    && error.code == AuthErrorCode.requiresRecentLogin.rawValue {
                try await reauthenticate(user)
                try await user.delete()
            }

            GIDSignIn.sharedInstance.signOut()
            return true
        } catch {
            let nsError = error as NSError
            let cancelledApple = nsError.domain == ASAuthorizationErrorDomain
                && nsError.code == ASAuthorizationError.canceled.rawValue
            let cancelledGoogle = nsError.domain == kGIDSignInErrorDomain
                && nsError.code == GIDSignInError.canceled.rawValue
            if !cancelledApple && !cancelledGoogle {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    /// Confirms the user's identity with their original provider. For Apple,
    /// the fresh authorization code also lets us revoke the Apple token,
    /// which App Review requires when deleting Sign in with Apple accounts.
    @MainActor
    private func reauthenticate(_ user: User) async throws {
        if user.providerData.contains(where: { $0.providerID == "apple.com" }) {
            let result = try await requestAppleReauthorization()
            try await user.reauthenticate(with: result.credential)
            if let code = result.authorizationCode {
                try await Auth.auth().revokeToken(withAuthorizationCode: code)
            }
        } else if user.providerData.contains(where: { $0.providerID == "google.com" }) {
            guard let rootVC = Self.topMostViewController() else {
                throw NSError(
                    domain: "AuthService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not find a window to present sign-in."]
                )
            }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            guard let idToken = result.user.idToken?.tokenString else {
                throw NSError(
                    domain: "AuthService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing Google ID token."]
                )
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            try await user.reauthenticate(with: credential)
        }
    }

    /// Runs the Sign in with Apple flow and returns the Firebase credential
    /// plus the authorization code needed to revoke the Apple token.
    @MainActor
    private func requestAppleReauthorization() async throws
        -> (credential: AuthCredential, authorizationCode: String?) {
        try await withCheckedThrowingContinuation { continuation in
            appleReauthContinuation = continuation

            let nonce = Self.randomNonceString()
            currentNonce = nonce

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.nonce = Self.sha256(nonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    @MainActor
    private func firebaseSignIn(with gidUser: GIDGoogleUser) async {
        guard let idToken = gidUser.idToken?.tokenString else {
            errorMessage = "Missing Google ID token."
            return
        }
        let accessToken = gidUser.accessToken.tokenString
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: accessToken
        )

        do {
            try await Auth.auth().signIn(with: credential)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func topMostViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow })
        else { return nil }

        var top = window.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: - Nonce helpers (Apple Sign In)

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            guard status == errSecSuccess else {
                fatalError("Unable to generate random bytes: \(status)")
            }
            for byte in randoms where remaining > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Apple Sign In delegates

extension AuthService: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer {
            Task { @MainActor in self.isWorking = false }
        }

        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let nonce = currentNonce,
              let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            if let continuation = appleReauthContinuation {
                appleReauthContinuation = nil
                continuation.resume(throwing: NSError(
                    domain: "AuthService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Apple sign-in did not return a valid token."]
                ))
                return
            }
            Task { @MainActor in
                self.errorMessage = "Apple sign-in did not return a valid token."
            }
            return
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )

        // Account deletion re-auth: hand the credential back instead of signing in.
        if let continuation = appleReauthContinuation {
            appleReauthContinuation = nil
            let authorizationCode = appleIDCredential.authorizationCode
                .flatMap { String(data: $0, encoding: .utf8) }
            continuation.resume(returning: (credential, authorizationCode))
            return
        }

        Task { @MainActor in
            do {
                try await Auth.auth().signIn(with: credential)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let continuation = appleReauthContinuation {
            appleReauthContinuation = nil
            continuation.resume(throwing: error)
            return
        }
        Task { @MainActor in
            self.isWorking = false
            // Don't surface cancellations as an error.
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }
}

// MARK: - Google branded UI

struct GoogleGLogo: View {

    var size: CGFloat = 18

    var body: some View {
        Text("G")
            .font(.system(size: size, weight: .bold, design: .default))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 234/255, green: 67/255, blue: 53/255),
                        Color(red: 251/255, green: 188/255, blue: 5/255),
                        Color(red: 52/255, green: 168/255, blue: 83/255),
                        Color(red: 66/255, green: 133/255, blue: 244/255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

struct GoogleSignInButton: View {

    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GoogleGLogo(size: 18)
                Text("Sign in with Google")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 0.24, green: 0.27, blue: 0.30))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.white)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.gray.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

struct GoogleAccountPill: View {

    let user: User
    var onSignOut: () -> Void

    var body: some View {
        Menu {
            if let name = user.displayName {
                Text(name)
            }
            if let email = user.email {
                Text(email)
            }
            Divider()
            Button(role: .destructive, action: onSignOut) {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            HStack(spacing: 8) {
                avatar
                Text(firstName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 0.24, green: 0.27, blue: 0.30))
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .background(Color.white)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.gray.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
        }
    }

    private var firstName: String {
        user.displayName?.components(separatedBy: " ").first
            ?? user.email
            ?? "Account"
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = user.photoURL {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle().fill(Color.gray.opacity(0.2))
            }
            .frame(width: 28, height: 28)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 28, height: 28)
                .foregroundColor(.gray)
        }
    }
}
