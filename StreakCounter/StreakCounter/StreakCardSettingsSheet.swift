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
    /// Marked as opened only after the detail sheet closes — writing to the
    /// store while the sheet is presenting re-renders the Form mid-animation
    /// and makes the first tap unreliable.
    @State private var pendingOpenedMessageID: UUID?

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
                        Text("Notes appear under the streak name on the card. Notes for individual days are added from the card or the calendar.")
                    }

                    if streak.type != .daily {
                        goalSection(streak: streak)
                    }

                    statisticsSection(streak: streak)

                    Section {
                        if streak.milestoneMessages.isEmpty {
                            Text("No messages yet. Write one to your future self.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(streak.milestoneMessages) { msg in
                                Button {
                                    pendingOpenedMessageID = msg.id
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
            .sheet(item: $viewingMessage, onDismiss: {
                if let id = pendingOpenedMessageID, let s = streak {
                    store.markMilestoneMessageOpened(id: id, for: s)
                }
                pendingOpenedMessageID = nil
            }) { msg in
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

    // MARK: - Goal editing

    /// Live bindings that read from the store (not a captured Streak copy),
    /// so consecutive edits inside the sheet never act on stale data.
    private var liveStreak: Streak? {
        store.streaks.first(where: { $0.id == streakID })
    }

    @ViewBuilder
    private func goalSection(streak: Streak) -> some View {
        Section {
            switch streak.type {
            case .multipleDaily:
                Stepper(
                    "Times per day: \(streak.dailyTarget)",
                    value: Binding(
                        get: { liveStreak?.dailyTarget ?? 1 },
                        set: { store.setDailyTarget($0, for: streak) }
                    ),
                    in: 1...50
                )
            case .weekly, .monthly:
                Picker("Goal type", selection: Binding(
                    get: { liveStreak?.goalMode ?? .countPerPeriod },
                    set: { newMode in
                        guard let s = liveStreak else { return }
                        store.setGoal(
                            mode: newMode,
                            weekdays: s.scheduledWeekdays,
                            periodTarget: s.periodTarget,
                            for: s
                        )
                    }
                )) {
                    Text("Specific weekdays").tag(GoalMode.specificWeekdays)
                    Text(streak.type == .weekly ? "Days per week" : "Days per month")
                        .tag(GoalMode.countPerPeriod)
                }

                if streak.goalMode == .specificWeekdays {
                    WeekdayPicker(selection: Binding(
                        get: { liveStreak?.scheduledWeekdays ?? [] },
                        set: { newDays in
                            guard let s = liveStreak else { return }
                            store.setGoal(
                                mode: .specificWeekdays,
                                weekdays: newDays,
                                periodTarget: s.periodTarget,
                                for: s
                            )
                        }
                    ))
                } else {
                    Stepper(
                        "\(streak.type == .weekly ? "Days per week" : "Days per month"): \(streak.periodTarget)",
                        value: Binding(
                            get: { liveStreak?.periodTarget ?? 1 },
                            set: { newTarget in
                                guard let s = liveStreak else { return }
                                store.setGoal(
                                    mode: .countPerPeriod,
                                    weekdays: s.scheduledWeekdays,
                                    periodTarget: newTarget,
                                    for: s
                                )
                            }
                        ),
                        in: 1...(streak.type == .weekly ? 7 : 31)
                    )
                }
            case .daily:
                EmptyView()
            }
        } header: {
            Text("Goal — \(streak.type.displayName)")
        } footer: {
            Text("Changing the goal re-evaluates past days against the new goal. The streak type itself can't be changed after creation.")
        }
    }

    // MARK: - Statistics

    @ViewBuilder
    private func statisticsSection(streak: Streak) -> some View {
        Section {
            switch streak.type {
            case .daily:
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
            case .multipleDaily:
                statRow(
                    label: "Total completions",
                    value: "\(streak.totalCompletionCount)"
                )
                statRow(
                    label: "Days target met",
                    value: "\(streak.targetMetDayCount) / \(store.daysSinceCreation(for: streak)) days"
                )
                statRow(
                    label: "Current streak",
                    value: "\(store.currentStreak(for: streak)) days"
                )
            case .weekly, .monthly:
                let unit = streak.type == .weekly ? "weeks" : "months"
                statRow(
                    label: "\(unit.capitalized) completed",
                    value: "\(streak.completedPeriodCount()) / \(streak.elapsedPeriodCount()) \(unit)"
                )
                statRow(
                    label: "Current streak",
                    value: "\(store.currentStreak(for: streak)) \(unit)"
                )
                statRow(
                    label: "Best streak",
                    value: "\(store.longestStreak(for: streak)) \(unit)"
                )
            }
        } header: {
            Text("Statistics")
        } footer: {
            if streak.type == .daily {
                Text("Not-done streaks treat Neutral and skipped days as not done. Days done compares the days you marked Done against every day since this card was created.")
            } else {
                Text("See Settings → Statistics for the full breakdown of every streak.")
            }
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
            if message.openedAt == nil {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.orange)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        // Plain buttons in a Form only hit-test their visible content, so
        // without this the gap around the Spacer ignores taps.
        .contentShape(Rectangle())
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
