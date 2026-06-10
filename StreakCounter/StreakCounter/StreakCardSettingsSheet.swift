//
//  StreakCardSettingsSheet.swift
//  StreakCounter
//

import SwiftUI
import FirebaseAuth

struct StreakCardSettingsSheet: View {

    let streakID: UUID
    @ObservedObject var store: StreakStore
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var nameDraft: String = ""
    @State private var notesDraft: String = ""
    @State private var showDeleteConfirm = false
    @State private var showFinalDeleteConfirm = false
    @State private var showClearDataConfirm = false
    @State private var showAddMessage = false
    @State private var viewingMessage: MilestoneMessage?

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
                        Button(role: .destructive) {
                            showClearDataConfirm = true
                        } label: {
                            Label("Quick clear data", systemImage: "arrow.counterclockwise")
                        }
                    } footer: {
                        Text("Resets your progress on this streak. Keeps the name, notes, colors, and milestone messages.")
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        saveName()
                        saveNotes()
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                nameDraft = streak?.name ?? ""
                notesDraft = streak?.notes ?? ""
            }
            .onChange(of: notesDraft) { _, _ in
                saveNotes()
            }
            .sheet(isPresented: $showAddMessage) {
                if let s = streak {
                    AddMilestoneMessageSheet(streak: s, store: store)
                }
            }
            .sheet(item: $viewingMessage) { msg in
                MilestoneMessageDetailSheet(
                    message: msg,
                    streakName: streak?.name ?? "",
                    recipientEmail: auth.user?.email
                )
            }
            .confirmationDialog(
                "Delete \"\(streak?.name ?? "this streak")\"?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Continue", role: .destructive) {
                    showFinalDeleteConfirm = true
                }
            } message: {
                Text("This will permanently remove the streak, its history, and any milestone messages.")
            }
            .alert(
                "Are you sure?",
                isPresented: $showFinalDeleteConfirm
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Delete forever", role: .destructive) {
                    if let s = streak { store.deleteStreak(s) }
                    dismiss()
                }
            } message: {
                Text("\"\(streak?.name ?? "This streak")\" will be permanently deleted. This cannot be undone.")
            }
            .confirmationDialog(
                "Clear all data for this streak?",
                isPresented: $showClearDataConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear data", role: .destructive) {
                    if let s = streak { store.clearStreakData(s) }
                }
            } message: {
                Text("Resets your progress and re-locks any milestone messages. Name, notes, and colors are kept.")
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
