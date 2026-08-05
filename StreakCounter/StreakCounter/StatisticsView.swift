//
//  StatisticsView.swift
//  StreakCounter
//

import SwiftUI

/// Settings → Statistics: type-appropriate statistics for every streak,
/// grouped in the same category order as the main page.
struct StatisticsView: View {

    @ObservedObject var store: StreakStore

    var body: some View {
        List {
            if store.streaks.isEmpty {
                Text("No streaks yet. Create one from the main page to see statistics here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.typeGroupedStreaks) { section in
                    Section(section.title ?? "") {
                        ForEach(section.streaks) { streak in
                            streakStats(streak)
                        }
                    }
                }
            }
        }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func streakStats(_ streak: Streak) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(streak.name)
                    .font(.body.weight(.semibold))
                Spacer()
                Text(streak.goalDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch streak.type {
            case .multipleDaily:
                multiDailyRows(streak)
            case .daily:
                dailyRows(streak)
            case .weekly, .monthly:
                periodRows(streak)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Per-type rows

    @ViewBuilder
    private func multiDailyRows(_ streak: Streak) -> some View {
        let days = store.daysSinceCreation(for: streak)
        let total = streak.totalCompletionCount
        let targetMet = streak.targetMetDayCount
        statRow("Total completions", "\(total)")
        statRow("Average per day", String(format: "%.1f", Double(total) / Double(max(1, days))))
        statRow("Target achievement rate", percent(targetMet, of: days))
        statRow("Days target met", "\(targetMet) / \(days)")
        statRow("Current streak", "\(store.currentStreak(for: streak)) days")
        statRow("Longest streak", "\(store.longestStreak(for: streak)) days")
    }

    @ViewBuilder
    private func dailyRows(_ streak: Streak) -> some View {
        let days = store.daysSinceCreation(for: streak)
        let done = store.doneDayCount(for: streak)
        statRow("Completion rate", percent(done, of: days))
        statRow("Completed days", "\(done)")
        statRow("Missed days", "\(store.missedDayCount(for: streak))")
        statRow("Current streak", "\(store.currentStreak(for: streak)) days")
        statRow("Longest streak", "\(store.longestStreak(for: streak)) days")
    }

    @ViewBuilder
    private func periodRows(_ streak: Streak) -> some View {
        let unit = streak.type == .weekly ? "weeks" : "months"
        let completed = streak.completedPeriodCount()
        let elapsed = streak.elapsedPeriodCount()
        statRow("\(unit.capitalized) completed", "\(completed) / \(elapsed)")
        statRow("\(streak.type == .weekly ? "Weekly" : "Monthly") completion rate", percent(completed, of: elapsed))
        statRow("Current streak", "\(store.currentStreak(for: streak)) \(unit)")
        statRow("Longest streak", "\(store.longestStreak(for: streak)) \(unit)")
    }

    // MARK: - Helpers

    private func percent(_ numerator: Int, of denominator: Int) -> String {
        guard denominator > 0 else { return "—" }
        return "\(Int((Double(numerator) / Double(denominator) * 100).rounded()))%"
    }

    @ViewBuilder
    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }
}
