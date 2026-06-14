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
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        List {
            if auth.user == nil {
                signInBanner
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
            }

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

    private var signInBanner: some View {
        Button {
            Task { await auth.signInWithGoogle() }
        } label: {
            HStack(spacing: 12) {
                GoogleGLogo(size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign in to save your streaks")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text("Back them up and sync across your devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(auth.isWorking)
    }

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
                            endRadius: 110
                        )
                    )
                    .frame(width: 220, height: 220)
                    .scaleEffect(flameGlow ? 1.05 : 0.95)

                Image(systemName: "flame.fill")
                    .font(.system(size: 96, weight: .black))
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
                    .shadow(color: Color.orange.opacity(0.5), radius: 12, x: 0, y: 6)
                    .scaleEffect(flameGlow ? 1.04 : 0.96)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    flameGlow = true
                }
            }

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
