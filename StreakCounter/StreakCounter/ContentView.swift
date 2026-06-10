//
//  ContentView.swift
//  StreakCounter
//
//  Created by Ryan Lin on 6/8/26.
//

import SwiftUI

struct ContentView: View {

    @StateObject private var store = StreakStore()
    @EnvironmentObject private var auth: AuthService

    @State private var newGoal = ""
    @State private var showSettings = false

    var body: some View {

        NavigationStack {

            ZStack {
                backgroundView

                ScrollView {

                    VStack(spacing: 16) {

                        if store.streaks.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(store.streaks) { streak in
                                    StreakCardView(streak: streak, store: store)
                                }
                            }
                        }

                        addGoalCard
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
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

    // MARK: - Sections

    private var addGoalCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {

                TextField(
                    "",
                    text: $newGoal,
                    prompt: Text("New goal (e.g. Read 10 pages)")
                        .foregroundColor(Color.gray.opacity(0.6))
                )
                .foregroundStyle(.gray)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.1))
                .clipShape(Capsule())
                .onSubmit(addGoal)

                Button(action: addGoal) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.gray)
                }
                .disabled(newGoal.isEmpty)
            }

            Button {
                store.debugAdvanceDay()
            } label: {
                Label("Simulate Next Day", systemImage: "forward.fill")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .buttonStyle(.bordered)
            .tint(.gray)
            .controlSize(.small)
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.largeTitle)
                .foregroundStyle(.gray)
            Text("No streaks yet")
                .font(.headline)
                .foregroundColor(.primary)
            Text("Add your first goal below to start a streak.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
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
