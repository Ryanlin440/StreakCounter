//
//  ContentView.swift
//  StreakCounter
//
//  Created by Ryan Lin on 6/8/26.
//

import SwiftUI

struct ContentView: View {

    // Caps the main column so iPad / Mac / landscape iPhone match the
    // portrait iPhone layout instead of stretching cards full-width.
    static let phoneContentMaxWidth: CGFloat = 480

    @StateObject private var store = StreakStore()
    @EnvironmentObject private var auth: AuthService

    @State private var newGoal = ""
    @State private var showSettings = false
    @State private var flameGlow = false

    var body: some View {
        Group {
            if auth.user == nil {
                signInGate
            } else {
                signedInRoot
            }
        }
        .alert(
            "Sign-in error",
            isPresented: Binding(
                get: { auth.errorMessage != nil },
                set: { if !$0 { auth.errorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { auth.errorMessage = nil }
            },
            message: {
                Text(auth.errorMessage ?? "")
            }
        )
    }

    // MARK: - Sign-in gate

    private var signInGate: some View {
        ZStack {
            backgroundView

            VStack(spacing: 28) {
                Spacer()

                flameMark

                VStack(spacing: 8) {
                    Text("StreakCounter")
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(.primary)
                    Text("Sign in to start your streaks and keep them in sync across every device.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                Button {
                    Task { await auth.signInWithGoogle() }
                } label: {
                    HStack(spacing: 14) {
                        GoogleGLogo(size: 32)
                        Text(auth.isWorking ? "Signing in…" : "Sign in with Google")
                            .font(.title3.weight(.bold))
                            .foregroundColor(Color(red: 0.10, green: 0.11, blue: 0.14))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.gray.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(auth.isWorking)
                .padding(.horizontal, 24)

                Text("Your streaks are private to your Google account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: ContentView.phoneContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private var flameMark: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.orange.opacity(0.35),
                            Color.orange.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 130
                    )
                )
                .frame(width: 260, height: 260)
                .scaleEffect(flameGlow ? 1.05 : 0.95)

            Image(systemName: "flame.fill")
                .font(.system(size: 120, weight: .black))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.85, blue: 0.25),
                            Color(red: 1.0, green: 0.45, blue: 0.10),
                            Color(red: 0.85, green: 0.15, blue: 0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color.orange.opacity(0.5), radius: 14, x: 0, y: 8)
                .scaleEffect(flameGlow ? 1.05 : 0.95)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                flameGlow = true
            }
        }
    }

    // MARK: - Signed-in root

    private var signedInRoot: some View {
        NavigationStack {

            ZStack {
                backgroundView

                content
                    .frame(maxWidth: ContentView.phoneContentMaxWidth)
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !store.streaks.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                            .foregroundStyle(Color(red: 0.12, green: 0.13, blue: 0.16))
                            .font(.body.weight(.semibold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                addGoalCard
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .frame(maxWidth: ContentView.phoneContentMaxWidth)
                    .frame(maxWidth: .infinity)
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(store: store)
                    .environmentObject(auth)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        List {
            if store.streaks.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 16, trailing: 16))
            } else {
                ForEach(store.streaks) { streak in
                    StreakCardView(streak: streak, store: store)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                .onMove { from, to in
                    store.moveStreak(from: from, to: to)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Sections

    private var addGoalCard: some View {
        HStack(spacing: 12) {

            TextField(
                "",
                text: $newGoal,
                prompt: Text("New goal (e.g. Read 10 pages)")
                    .foregroundColor(Color.gray.opacity(0.6))
            )
            .font(.system(size: 17))
            .foregroundStyle(.gray)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.gray.opacity(0.1))
            .clipShape(Capsule())
            .onSubmit(addGoal)

            Button(action: addGoal) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(newGoal.isEmpty ? Color.gray.opacity(0.5) : Color.accentColor)
            }
            .disabled(newGoal.isEmpty)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            flameMark
                .scaleEffect(0.7)
                .padding(.bottom, -16)

            VStack(spacing: 6) {
                Text("Light your first streak")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)
                Text("Add a goal below and start a daily fire.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var backgroundView: some View {
        ZStack {
            store.backgroundColor.color
            if let data = store.backgroundImageData,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            }
        }
        .ignoresSafeArea()
    }

    private func addGoal() {
        let trimmed = newGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addStreak(name: trimmed)
        newGoal = ""
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthService())
}
