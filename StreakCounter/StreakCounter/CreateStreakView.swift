//
//  CreateStreakView.swift
//  StreakCounter
//

import SwiftUI

/// Dedicated creation screen for new streaks. Shows the fields relevant to
/// the selected streak type: a daily target for Multiple Times a Day, and a
/// weekday schedule or days-per-period target for Weekly/Monthly.
struct CreateStreakView: View {

    @ObservedObject var store: StreakStore
    @Environment(\.dismiss) private var dismiss

    @State private var type: StreakType = .daily
    @State private var name = ""
    @State private var notes = ""
    @State private var dailyTarget = 2
    @State private var goalMode: GoalMode = .specificWeekdays
    @State private var scheduledWeekdays: [Int] = []
    @State private var periodTarget = 3

    private var canCreate: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        if (type == .weekly || type == .monthly), goalMode == .specificWeekdays {
            return !scheduledWeekdays.isEmpty
        }
        return true
    }

    private var typeFooter: String {
        switch type {
        case .multipleDaily:
            return "For habits done several times a day, like drinking water 8 times."
        case .daily:
            return "One completion per day, like the classic streak."
        case .weekly:
            return "Either specific weekdays (e.g. Mon, Wed, Fri) or any N days per week."
        case .monthly:
            return "Either specific weekdays (e.g. every Monday) or any N days per month."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Streak type", selection: $type) {
                        ForEach(StreakType.displayOrder) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Type")
                } footer: {
                    Text(typeFooter)
                }

                Section("Name") {
                    TextField("e.g. Exercise", text: $name)
                }

                goalSection

                Section {
                    TextField("Optional note for this streak", text: $notes, axis: .vertical)
                        .lineLimit(1...5)
                } header: {
                    Text("Notes")
                } footer: {
                    Text("Shown under the streak name on the card. You can also add notes for individual days later, from the card or the calendar.")
                }
            }
            .navigationTitle("New Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .bold()
                        .disabled(!canCreate)
                }
            }
        }
    }

    @ViewBuilder
    private var goalSection: some View {
        switch type {
        case .daily:
            EmptyView()
        case .multipleDaily:
            Section("Goal") {
                Stepper("Times per day: \(dailyTarget)", value: $dailyTarget, in: 1...50)
            }
        case .weekly, .monthly:
            Section {
                Picker("Goal type", selection: $goalMode) {
                    Text("Specific weekdays").tag(GoalMode.specificWeekdays)
                    Text(type == .weekly ? "Days per week" : "Days per month")
                        .tag(GoalMode.countPerPeriod)
                }
                .pickerStyle(.segmented)

                if goalMode == .specificWeekdays {
                    WeekdayPicker(selection: $scheduledWeekdays)
                } else {
                    Stepper(
                        "\(type == .weekly ? "Days per week" : "Days per month"): \(periodTarget)",
                        value: $periodTarget,
                        in: 1...(type == .weekly ? 7 : 31)
                    )
                }
            } header: {
                Text("Goal")
            } footer: {
                if goalMode == .specificWeekdays {
                    Text("The card is only active on the selected days. Other days are greyed out and never count against you.")
                } else {
                    Text(type == .weekly
                        ? "Complete it on any days — the week counts once you hit the target."
                        : "Complete it on any days — the month counts once you hit the target.")
                }
            }
        }
    }

    private func create() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let clampedPeriodTarget = min(periodTarget, type == .weekly ? 7 : 31)
        let streak = Streak(
            name: trimmedName,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            dailyTarget: dailyTarget,
            goalMode: goalMode,
            scheduledWeekdays: scheduledWeekdays,
            periodTarget: clampedPeriodTarget
        )
        store.addStreak(streak)
        dismiss()
    }
}
