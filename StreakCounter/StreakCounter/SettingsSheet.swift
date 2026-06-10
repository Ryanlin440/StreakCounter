//
//  SettingsSheet.swift
//  StreakCounter
//

import SwiftUI
import PhotosUI
import FirebaseAuth

struct SettingsSheet: View {

    @ObservedObject var store: StreakStore
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showClearAllConfirm = false
    @State private var showClearAllFinalConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if let user = auth.user {
                        signedInRow(user: user)
                        Button(role: .destructive) {
                            auth.signOut()
                        } label: {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        Button {
                            Task { await auth.signInWithGoogle() }
                        } label: {
                            HStack(spacing: 10) {
                                GoogleGLogo(size: 18)
                                Text("Sign in with Google")
                                    .font(.body.weight(.medium))
                                    .foregroundColor(.primary)
                            }
                        }
                        .disabled(auth.isWorking)
                    }
                }

                Section("Card Size") {
                    Slider(
                        value: Binding(
                            get: { store.cardSize },
                            set: { store.setCardSize($0) }
                        ),
                        in: 0.7...1.5,
                        step: 0.05
                    )
                    HStack {
                        Text("Scale: \(String(format: "%.2fx", store.cardSize))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset to default") {
                            store.setCardSize(StreakStore.defaultCardSize)
                        }
                    }
                }

                Section("Background Color") {
                    ColorTemplateRow(
                        colors: backgroundTemplates,
                        selected: store.backgroundColor.color
                    ) { color in
                        store.setBackgroundColor(color)
                    }
                    ColorPicker(
                        "Custom color",
                        selection: Binding(
                            get: { store.backgroundColor.color },
                            set: { store.setBackgroundColor($0) }
                        ),
                        supportsOpacity: false
                    )
                    Button("Reset to default") {
                        store.setBackgroundColor(CodableColor.appBackground.color)
                    }
                }

                Section {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose photo…", systemImage: "photo.on.rectangle")
                    }
                    if store.backgroundImageData != nil {
                        Button(role: .destructive) {
                            store.setBackgroundImage(data: nil)
                            selectedPhoto = nil
                        } label: {
                            Label("Remove image", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("Background Image")
                } footer: {
                    Text("The image is shown on top of the background color.")
                }

                Section {
                    Button(role: .destructive) {
                        showClearAllConfirm = true
                    } label: {
                        Label("Quick clear all data", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(store.streaks.isEmpty)
                } header: {
                    Text("Data")
                } footer: {
                    Text("Resets progress on every streak and re-locks milestone messages. Streak names, notes, and colors are kept.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                        store.setBackgroundImage(data: data)
                    }
                }
            }
            .confirmationDialog(
                "Clear data for all \(store.streaks.count) streak\(store.streaks.count == 1 ? "" : "s")?",
                isPresented: $showClearAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Continue", role: .destructive) {
                    showClearAllFinalConfirm = true
                }
            } message: {
                Text("Resets progress on every streak and re-locks any milestone messages.")
            }
            .alert(
                "Are you sure?",
                isPresented: $showClearAllFinalConfirm
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Clear all data", role: .destructive) {
                    store.clearAllStreakData()
                }
            } message: {
                Text("All progress will be erased. This cannot be undone.")
            }
        }
    }

    private var backgroundTemplates: [Color] {
        [
            CodableColor.appBackground.color,
            .white,
            Color(red: 0.86, green: 0.93, blue: 1.0),  // sky
            Color(red: 0.88, green: 0.96, blue: 0.89), // mint
            Color(red: 0.94, green: 0.90, blue: 0.99), // lavender
            Color(red: 1.0, green: 0.88, blue: 0.86),  // peach
            Color(red: 0.94, green: 0.94, blue: 0.94), // light gray
            Color(red: 0.18, green: 0.20, blue: 0.24)  // dark slate
        ]
    }

    @ViewBuilder
    private func signedInRow(user: FirebaseAuth.User) -> some View {
        HStack(spacing: 12) {
            if let url = user.photoURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.2))
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .foregroundColor(.gray)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName ?? "Signed in")
                    .font(.body.weight(.medium))
                if let email = user.email {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
