//
//  NotificationManager.swift
//  StreakCounter
//

import Foundation
import UserNotifications

/// A time of day the user wants a daily reminder to fill out their streaks.
struct ReminderTime: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var hour: Int
    var minute: Int

    /// The time formatted for display, e.g. "8:00 PM".
    var displayString: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Handles the app-icon badge (number of streaks not filled out today),
/// the user's daily reminder schedule, and a silent after-midnight badge
/// refresh so the badge tracks the new day even if the app isn't opened.
enum NotificationManager {

    /// The reminder schedule used until the user customizes it: one nightly 8pm.
    static let defaultReminderTimes = [ReminderTime(hour: 20, minute: 0)]

    /// How many future days we pre-schedule as a safety net for days the
    /// app isn't opened. Refreshed every time the app is used.
    private static let scheduledDayCount = 7

    private static let reminderIdentifierPrefix = "streak-reminder-"
    private static let legacyReminderIdentifierPrefix = "streak-nightly-reminder-"
    private static let badgeResetIdentifierPrefix = "streak-badge-reset-"

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

    // MARK: - Daily reminders

    /// Rebuilds the schedule of daily reminders and midnight badge refreshes.
    ///
    /// - Each user-chosen time gets a reminder scheduled for the next few days.
    ///   Today's reminder is only scheduled if the user still has streaks to
    ///   fill out (and the time hasn't already passed).
    /// - Just after each upcoming midnight a silent, badge-only notification
    ///   resets the app-icon badge to the full streak count, since a new day
    ///   starts with every streak unfilled.
    static func refreshReminders(
        times: [ReminderTime],
        unfilledToday: Int,
        totalStreaks: Int
    ) async {
        let center = UNUserNotificationCenter.current()

        // Clear everything we've scheduled before so the schedule rebuilds cleanly.
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter {
            $0.hasPrefix(reminderIdentifierPrefix)
                || $0.hasPrefix(legacyReminderIdentifierPrefix)
                || $0.hasPrefix(badgeResetIdentifierPrefix)
        }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        // No streaks at all → nothing to remind about or badge.
        guard totalStreaks > 0 else { return }

        let calendar = Calendar.current
        let now = Date()

        for time in times {
            for dayOffset in 0..<scheduledDayCount {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }

                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = time.hour
                components.minute = time.minute

                guard let fireDate = calendar.date(from: components) else { continue }

                // Today: only remind if there's something left to do and the time is still ahead.
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
                    identifier: "\(reminderIdentifierPrefix)\(time.id.uuidString)-\(dayOffset)",
                    content: content,
                    trigger: trigger
                )

                try? await center.add(request)
            }
        }

        // Silent badge refresh just after each upcoming midnight. A new day
        // starts with every streak unfilled, so the badge becomes the total
        // streak count without the app having to run.
        for dayOffset in 1...scheduledDayCount {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = 0
            components.minute = 0
            components.second = 30

            guard let fireDate = calendar.date(from: components) else { continue }

            let content = UNMutableNotificationContent()
            // No title, body, or sound: iOS delivers this silently and only
            // updates the badge.
            content.badge = NSNumber(value: totalStreaks)

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: fireDate
                ),
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: "\(badgeResetIdentifierPrefix)\(dayOffset)",
                content: content,
                trigger: trigger
            )

            try? await center.add(request)
        }
    }

    /// Convenience: refresh both the badge and the scheduled reminders at once.
    static func refresh(times: [ReminderTime], unfilledToday: Int, totalStreaks: Int) async {
        await updateBadge(unfilledCount: unfilledToday)
        await refreshReminders(times: times, unfilledToday: unfilledToday, totalStreaks: totalStreaks)
    }

    // MARK: - Test notification

    /// Fires a one-off notification a few seconds from now so the user can
    /// confirm notifications are enabled and working. Requests authorization
    /// first in case it hasn't been granted yet.
    static func sendTestNotification() async {
        await requestAuthorization()

        let content = UNMutableNotificationContent()
        content.title = "Test notification 🔔"
        content.body = "Notifications are working. Daily reminders arrive at the times you set."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(
            identifier: "streak-test-notification",
            content: content,
            trigger: trigger
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}
