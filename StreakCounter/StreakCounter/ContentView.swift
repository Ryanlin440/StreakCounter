//
//  ContentView.swift
//  StreakCounter
//
//  Created by Ryan Lin on 6/8/26.
//

import SwiftUI
import PhotosUI
import FirebaseAuth

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

                        addGoalCard

                        if store.streaks.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(store.streaks) { streak in
                                    StreakCardView(streak: streak, store: store)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("🔥 Streaks")
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

                TextField("New goal (e.g. Read 10 pages)", text: $newGoal)
                    .textFieldStyle(.roundedBorder)
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
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.bordered)
            .tint(.gray)
            .controlSize(.small)
        }
        .padding(14)
        .background(neutralCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "flame")
                .font(.largeTitle)
                .foregroundStyle(.gray)
            Text("No streaks yet")
                .font(.headline)
                .foregroundColor(.primary)
            Text("Add your first goal above to start a streak.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(neutralCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        )
    }

    private var neutralCardBackground: Color {
        Color(red: 245/255, green: 245/255, blue: 247/255)
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

// MARK: - Streak card

struct StreakCardView: View {

    let streak: Streak
    @ObservedObject var store: StreakStore

    @State private var showCardSettings = false

    private var textColor: Color {
        streak.textColor.color
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 10) {

            HStack {
                Text(streak.name)
                    .font(.headline)
                    .foregroundColor(textColor)

                Spacer()

                Button {
                    showCardSettings = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(textColor.opacity(0.8))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 16) {
                statCounter(
                    value: store.currentStreak(for: streak),
                    title: "Current",
                    systemImage: "flame.fill"
                )
                statCounter(
                    value: store.longestStreak(for: streak),
                    title: "Best",
                    systemImage: "trophy.fill"
                )
                Spacer()
                Text("Started \(streak.startDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.7))
            }

            HStack(spacing: 8) {
                ForEach(DayStatus.allCases, id: \.self) { status in
                    StatusButton(
                        status: status,
                        isSelected: store.status(for: Date(), on: streak) == status
                    ) {
                        store.setStatus(status, for: Date(), on: streak)
                    }
                }

                NavigationLink {
                    StreakCalendarView(streakID: streak.id, store: store)
                } label: {
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundColor(textColor)
                        .padding(8)
                        .background(textColor.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(streak.cardColor.color)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
        .sheet(isPresented: $showCardSettings) {
            StreakCardSettingsSheet(streakID: streak.id, store: store)
        }
    }

    @ViewBuilder
    private func statCounter(value: Int, title: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text("\(value)")
                    .font(.title3.weight(.bold))
            }
            .foregroundColor(textColor)
            Text(title)
                .font(.caption2)
                .foregroundColor(textColor.opacity(0.7))
        }
    }
}

// MARK: - Per-card settings sheet

struct StreakCardSettingsSheet: View {

    let streakID: UUID
    @ObservedObject var store: StreakStore
    @Environment(\.dismiss) private var dismiss

    @State private var nameDraft: String = ""
    @State private var showDeleteConfirm = false

    private var streak: Streak? {
        store.streaks.first(where: { $0.id == streakID })
    }

    var body: some View {
        NavigationStack {
            Form {
                if let streak = streak {
                    Section("Name") {
                        TextField("Goal name", text: $nameDraft)
                            .onSubmit(saveName)
                    }

                    Section("Card color") {
                        cardColorTemplatesRow(streak: streak)
                        ColorPicker(
                            "Custom card color",
                            selection: Binding(
                                get: { streak.cardColor.color },
                                set: { store.setCardColor($0, for: streak) }
                            ),
                            supportsOpacity: false
                        )
                    }

                    Section("Text color") {
                        textColorTemplatesRow(streak: streak)
                        ColorPicker(
                            "Custom text color",
                            selection: Binding(
                                get: { streak.textColor.color },
                                set: { store.setTextColor($0, for: streak) }
                            ),
                            supportsOpacity: false
                        )
                    }

                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete streak", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Card Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        saveName()
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                nameDraft = streak?.name ?? ""
            }
            .confirmationDialog(
                "Delete this streak?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let s = streak { store.deleteStreak(s) }
                    dismiss()
                }
            } message: {
                Text("This will permanently remove the streak and its history.")
            }
        }
    }

    private func saveName() {
        guard let s = streak else { return }
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != s.name else { return }
        store.renameStreak(s, to: trimmed)
    }

    @ViewBuilder
    private func cardColorTemplatesRow(streak: Streak) -> some View {
        ColorTemplateRow(
            colors: cardColorTemplates,
            selected: streak.cardColor.color
        ) { color in
            store.setCardColor(color, for: streak)
        }
    }

    @ViewBuilder
    private func textColorTemplatesRow(streak: Streak) -> some View {
        ColorTemplateRow(
            colors: textColorTemplates,
            selected: streak.textColor.color
        ) { color in
            store.setTextColor(color, for: streak)
        }
    }

    private var cardColorTemplates: [Color] {
        [
            .white,
            Color(red: 1.0, green: 0.95, blue: 0.85),  // cream
            Color(red: 0.86, green: 0.93, blue: 1.0),  // sky
            Color(red: 0.88, green: 0.96, blue: 0.89), // mint
            Color(red: 0.94, green: 0.90, blue: 0.99), // lavender
            Color(red: 1.0, green: 0.88, blue: 0.86),  // peach
            Color(red: 0.94, green: 0.94, blue: 0.94), // light gray
            Color(red: 0.18, green: 0.20, blue: 0.24)  // dark slate
        ]
    }

    private var textColorTemplates: [Color] {
        [
            .black,
            .white,
            Color(red: 0.24, green: 0.27, blue: 0.30),
            Color(red: 0.55, green: 0.55, blue: 0.58),
            Color(red: 0.85, green: 0.20, blue: 0.27),
            Color(red: 0.05, green: 0.45, blue: 0.80),
            Color(red: 0.18, green: 0.55, blue: 0.34),
            Color(red: 0.50, green: 0.30, blue: 0.65)
        ]
    }
}

// MARK: - Color template row

struct ColorTemplateRow: View {

    let colors: [Color]
    let selected: Color
    var onSelect: (Color) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Button {
                        onSelect(color)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(color)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                                )
                            if matches(color, selected) {
                                Circle()
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                                    .frame(width: 38, height: 38)
                            }
                        }
                        .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func matches(_ a: Color, _ b: Color) -> Bool {
        CodableColor(a) == CodableColor(b)
    }
}

// MARK: - Status button

struct StatusButton: View {

    let status: DayStatus
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: status.symbol)
                .font(.body.weight(.bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? status.color : status.color.opacity(0.35))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status.displayName)
    }
}

// MARK: - Settings sheet

struct SettingsSheet: View {

    @ObservedObject var store: StreakStore
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhoto: PhotosPickerItem?

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

#Preview {
    ContentView()
        .environmentObject(AuthService())
}
