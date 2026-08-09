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
    // Defaults to "every day" for Daily and "count per period" for Weekly.
    @State private var goalMode: GoalMode = .countPerPeriod
    @State private var scheduledWeekdays: [Int] = []
    @State private var periodTarget = 3

    private var canCreate: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        // A specific-days goal needs at least one day selected.
        if type != .monthly, goalMode == .specificWeekdays {
            return !scheduledWeekdays.isEmpty
        }
        return true
    }

    private var typeFooter: String {
        switch type {
        case .multipleDaily:
            return "For habits done several times a day, like drinking water 8 times."
        case .daily:
            return "Every day, or only on specific days (e.g. Mon, Wed, Fri)."
        case .weekly:
            return "Either specific days (e.g. Mon, Wed, Fri) or any N days per week."
        case .monthly:
            return "Complete it any N times within the month."
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
            Section {
                Picker("Goal type", selection: $goalMode) {
                    Text("Every day").tag(GoalMode.countPerPeriod)
                    Text("Specific days").tag(GoalMode.specificWeekdays)
                }
                .pickerStyle(.segmented)

                if goalMode == .specificWeekdays {
                    WeekdayPicker(selection: $scheduledWeekdays)
                }
            } header: {
                Text("Goal")
            } footer: {
                if goalMode == .specificWeekdays {
                    Text("The card is only active on the selected weekdays. Other days are greyed out and never count against you.")
                } else {
                    Text("One completion every day, like the classic streak.")
                }
            }
        case .multipleDaily:
            Section {
                Picker("Goal type", selection: $goalMode) {
                    Text("Every day").tag(GoalMode.countPerPeriod)
                    Text("Specific days").tag(GoalMode.specificWeekdays)
                }
                .pickerStyle(.segmented)

                if goalMode == .specificWeekdays {
                    WeekdayPicker(selection: $scheduledWeekdays)
                }

                Stepper("Times per day: \(dailyTarget)", value: $dailyTarget, in: 1...50)
            } header: {
                Text("Goal")
            } footer: {
                if goalMode == .specificWeekdays {
                    Text("The card is only active on the selected days. Other days are greyed out and never count against you.")
                } else {
                    Text("Hit the target every day to keep the streak going.")
                }
            }
        case .weekly:
            Section {
                Picker("Goal type", selection: $goalMode) {
                    Text("Days per week").tag(GoalMode.countPerPeriod)
                    Text("Specific days").tag(GoalMode.specificWeekdays)
                }
                .pickerStyle(.segmented)

                if goalMode == .specificWeekdays {
                    WeekdayPicker(selection: $scheduledWeekdays)
                } else {
                    Stepper(
                        "Days per week: \(periodTarget)",
                        value: $periodTarget,
                        in: 1...7
                    )
                }
            } header: {
                Text("Goal")
            } footer: {
                if goalMode == .specificWeekdays {
                    Text("The card is only active on the selected days. Other days are greyed out and never count against you.")
                } else {
                    Text("Complete it on any days — the week counts once you hit the target.")
                }
            }
        case .monthly:
            Section {
                Stepper(
                    "Times per month: \(periodTarget)",
                    value: $periodTarget,
                    in: 1...31
                )
            } header: {
                Text("Goal")
            } footer: {
                Text("Complete it on any days — the month counts once you hit the target.")
            }
        }
    }

    private func create() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let clampedPeriodTarget = min(periodTarget, type == .weekly ? 7 : 31)
        // Monthly is always count-per-period now; ignore any stray schedule.
        let finalGoalMode: GoalMode = type == .monthly ? .countPerPeriod : goalMode
        let weekdays = finalGoalMode == .specificWeekdays ? scheduledWeekdays : []
        let streak = Streak(
            name: trimmedName,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            dailyTarget: dailyTarget,
            goalMode: finalGoalMode,
            scheduledWeekdays: weekdays,
            periodTarget: clampedPeriodTarget
        )
        store.addStreak(streak)
        dismiss()
    }
}
