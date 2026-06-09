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
import GoogleSignIn

final class AuthService: ObservableObject {

    @Published private(set) var user: User?
    @Published private(set) var isWorking: Bool = false
    @Published var errorMessage: String?

    private var stateHandle: AuthStateDidChangeListenerHandle?

    init() {
        guard FirebaseApp.app() != nil else { return }

        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }

        user = Auth.auth().currentUser
        stateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
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

    var isSignedIn: Bool { user != nil }

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

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
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
