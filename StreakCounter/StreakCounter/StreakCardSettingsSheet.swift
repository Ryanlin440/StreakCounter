//
//  StreakCardSettingsSheet.swift
//  StreakCounter
//

import SwiftUI
import PhotosUI
import FirebaseAuth

struct StreakCardSettingsSheet: View {

    let streakID: UUID
    @ObservedObject var store: StreakStore
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var nameDraft: String
    @State private var notesDraft: String
    @State private var selectedPhoto: PhotosPickerItem?
    // Inline confirmations (rendered right in the Form / bottom bar). Alerts and
    // confirmationDialogs presented from inside this sheet don't fire reliably,
    // so we confirm with plain conditional views instead.
    @State private var confirmingClear = false
    @State private var confirmingDelete = false
    @State private var showAddMessage = false
    @State private var viewingMessage: MilestoneMessage?

    init(streakID: UUID, store: StreakStore) {
        self.streakID = streakID
        _store = ObservedObject(wrappedValue: store)
        // Seed the drafts up front so the Form measures its full height on the
        // first render — otherwise the notes field grows after `onAppear` and
        // the first scroll can't reach the bottom / bounces.
        let streak = store.streaks.first(where: { $0.id == streakID })
        _nameDraft = State(initialValue: streak?.name ?? "")
        _notesDraft = State(initialValue: streak?.notes ?? "")
    }

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

                    Section {
                        TextField(
                            "Optional note for this streak",
                            text: $notesDraft,
                            axis: .vertical
                        )
                        .lineLimit(1...5)
                    } header: {
                        Text("Notes")
                    } footer: {
                        Text("Notes appear under the streak name on the card.")
                    }

                    Section {
                        statRow(
                            label: "Current not-done streak",
                            value: "\(store.currentNotDoneStreak(for: streak)) days"
                        )
                        statRow(
                            label: "Longest not-done streak",
                            value: "\(store.longestNotDoneStreak(for: streak)) days"
                        )
                        statRow(
                            label: "Days done",
                            value: "\(store.doneDayCount(for: streak)) done / \(store.daysSinceCreation(for: streak)) days"
                        )
                    } header: {
                        Text("Statistics")
                    } footer: {
                        Text("Not-done streaks treat Neutral and skipped days as not done. Days done compares the days you marked Done against every day since this card was created.")
                    }

                    Section {
                        if streak.milestoneMessages.isEmpty {
                            Text("No messages yet. Write one to your future self.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(streak.milestoneMessages) { msg in
                                Button {
                                    viewingMessage = msg
                                } label: {
                                    milestoneRow(message: msg)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                for index in offsets {
                                    let msg = streak.milestoneMessages[index]
                                    store.deleteMilestoneMessage(id: msg.id, for: streak)
                                }
                            }
                        }
                        Button {
                            showAddMessage = true
                        } label: {
                            Label("Add a message", systemImage: "envelope.badge")
                        }
                    } header: {
                        Text("Messages to future self")
                    } footer: {
                        Text("Write a note now that unlocks when you reach a milestone day. You can email it to yourself when it unlocks.")
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
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Choose photo…", systemImage: "photo.on.rectangle")
                        }
                        if store.cardImageData(for: streak) != nil {
                            Button(role: .destructive) {
                                store.setCardImage(data: nil, for: streak)
                                selectedPhoto = nil
                            } label: {
                                Label("Remove photo", systemImage: "trash")
                            }
                        }
                    } header: {
                        Text("Card image")
                    } footer: {
                        Text("Shown behind this card's content. Stored on this device only.")
                    }

                    Section {
                        if confirmingClear {
                            Text("Clear all progress for this streak?")
                                .font(.subheadline.weight(.semibold))
                            Button(role: .destructive) {
                                store.clearStreakData(streak)
                                confirmingClear = false
                            } label: {
                                Label("Yes, clear streaks", systemImage: "arrow.counterclockwise")
                            }
                            Button("Cancel") {
                                confirmingClear = false
                            }
                        } else {
                            Button(role: .destructive) {
                                confirmingClear = true
                            } label: {
                                Label("Clear streaks", systemImage: "arrow.counterclockwise")
                            }
                        }
                    } footer: {
                        Text("Resets your progress on this streak. Keeps the name, notes, colors, and milestone messages.")
                    }
                }
            }
            .navigationTitle("Card Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        saveName()
                        saveNotes()
                        dismiss()
                    }
                    .bold()
                }
            }
            .onChange(of: nameDraft) { _, _ in
                saveName()
            }
            .onChange(of: notesDraft) { _, _ in
                saveNotes()
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    guard let streak = streak,
                          let data = try? await newValue?.loadTransferable(type: Data.self)
                    else { return }
                    store.setCardImage(data: data, for: streak)
                }
            }
            .sheet(isPresented: $showAddMessage) {
                if let s = streak {
                    AddMilestoneMessageSheet(streak: s, store: store)
                }
            }
            .sheet(item: $viewingMessage) { msg in
                MilestoneMessageDetailSheet(
                    message: msg,
                    streakName: streak?.name ?? ""
                )
                .environmentObject(auth)
            }
            .safeAreaInset(edge: .bottom) {
                // Pinned so the destructive action is always reachable without
                // scrolling to the bottom of a lazily-rendered Form. Confirmation
                // is inline (no alert), which fires reliably from inside a sheet.
                VStack(spacing: 8) {
                    if confirmingDelete {
                        Text("Delete this streak permanently? This can't be undone.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            Button {
                                confirmingDelete = false
                            } label: {
                                Text("Cancel")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)

                            Button(role: .destructive) {
                                if let s = streak { store.deleteStreak(s) }
                                dismiss()
                            } label: {
                                Text("Delete forever")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    } else {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label("Delete streak", systemImage: "trash")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
    }

    private func saveName() {
        guard let s = streak else { return }
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != s.name else { return }
        store.renameStreak(s, to: trimmed)
    }

    private func saveNotes() {
        guard let s = streak else { return }
        if notesDraft != s.notes {
            store.setNotes(notesDraft, for: s)
        }
    }

    @ViewBuilder
    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func milestoneRow(message: MilestoneMessage) -> some View {
        HStack {
            Image(systemName: message.isUnlocked ? "envelope.open.fill" : "lock.fill")
                .foregroundColor(message.isUnlocked ? .orange : .gray)
            VStack(alignment: .leading, spacing: 2) {
                Text("Day \(message.targetDays)")
                    .font(.body.weight(.medium))
                Text(message.isUnlocked
                    ? "Unlocked — tap to read"
                    : "Locked until you reach \(message.targetDays) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
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
