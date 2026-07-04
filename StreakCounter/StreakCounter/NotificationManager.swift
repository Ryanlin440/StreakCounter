//
//  NotificationManager.swift
//  StreakCounter
//

import Foundation
import UserNotifications

/// Handles the app-icon badge (number of streaks not filled out today) and
/// the nightly 8pm reminder to fill out the day's streaks.
enum NotificationManager {

    /// Hour of day (24h) the nightly reminder fires.
    private static let reminderHour = 20
    private static let reminderMinute = 0

    /// How many future nights we pre-schedule as a safety net for days the
    /// app isn't opened. Refreshed every time the app is used.
    private static let scheduledNightCount = 7

    private static let reminderIdentifierPrefix = "streak-nightly-reminder-"

    // MARK: - Authorization

    /// Ask for permission to show alerts, play sounds, and set the badge.
    static func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Badge

    /// Sets the app-icon badge to the number of streaks still not filled out today.
    static func updateBadge(unfilledCount: Int) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(max(0, unfilledCount))
    }

    // MARK: - Nightly reminder

    /// Rebuilds the schedule of nightly reminders.
    ///
    /// - Tonight's reminder is only scheduled if the user still has streaks to
    ///   fill out (and 8pm hasn't already passed).
    /// - The following nights are scheduled unconditionally as a fallback for
    ///   days the app isn't opened; they get refreshed the next time the app runs.
    static func refreshNightlyReminders(unfilledToday: Int, totalStreaks: Int) async {
        let center = UNUserNotificationCenter.current()

        // Clear our existing pending reminders so we can rebuild cleanly.
        let identifiers = (0..<scheduledNightCount).map { "\(reminderIdentifierPrefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        // No streaks at all → nothing to remind about.
        guard totalStreaks > 0 else { return }

        let calendar = Calendar.current
        let now = Date()

        for dayOffset in 0..<scheduledNightCount {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = reminderHour
            components.minute = reminderMinute

            guard let fireDate = calendar.date(from: components) else { continue }

            // Tonight: only remind if there's something left to do and 8pm is still ahead.
            if dayOffset == 0 {
                if unfilledToday == 0 { continue }
                if fireDate <= now { continue }
            }

            let content = UNMutableNotificationContent()
            content.title = "Keep your streaks alive 🔥"
            if dayOffset == 0 {
                content.body = unfilledToday == 1
                    ? "You have 1 streak left to fill out today."
                    : "You have \(unfilledToday) streaks left to fill out today."
            } else {
                content.body = "Don't forget to fill out your streaks for today."
            }
            content.sound = .default

            let triggerComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: triggerComponents,
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: "\(reminderIdentifierPrefix)\(dayOffset)",
                content: content,
                trigger: trigger
            )

            try? await center.add(request)
        }
    }

    /// Convenience: refresh both the badge and the nightly reminders at once.
    static func refresh(unfilledToday: Int, totalStreaks: Int) async {
        await updateBadge(unfilledCount: unfilledToday)
        await refreshNightlyReminders(unfilledToday: unfilledToday, totalStreaks: totalStreaks)
    }
}
