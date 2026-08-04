//
//  BackgroundRefresh.swift
//  StreakCounter
//

import Foundation
import BackgroundTasks
import FirebaseAuth
import FirebaseFirestore

/// Periodically pulls the latest synced snapshot from Firestore while the
/// app isn't running, so the app-icon badge (and the widget) reflect changes
/// made on another device. iOS decides exactly when the refresh runs, so
/// this is best-effort rather than instant.
enum BackgroundRefresh {

    static let taskIdentifier = "com.ryanlin.StreakCounter2.refresh"

    /// Must be called before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    /// Ask the system for another refresh. Safe to call repeatedly; the
    /// scheduler keeps at most one pending request per identifier.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private nonisolated static func handle(_ task: BGAppRefreshTask) {
        let work = Task { @MainActor in
            schedule() // keep the refresh chain alive for next time
            await refreshFromCloud()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// Fetch the user's snapshot straight from the server, cache it locally,
    /// and refresh the badge, reminders, and widget from it.
    static func refreshFromCloud() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let ref = Firestore.firestore().collection("users").document(uid)
        guard let document = try? await ref.getDocument(source: .server),
              let payload = document.data()?["payload"] as? String,
              let payloadData = payload.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(StreakStoreSnapshot.self, from: payloadData)
        else { return }

        // Cache like StreakStore.applyRemoteSnapshot so the next foreground
        // launch starts from this data too.
        if let encoded = try? JSONEncoder().encode(snapshot.streaks) {
            UserDefaults.standard.set(encoded, forKey: "streaks")
        }
        if let times = snapshot.reminderTimes,
           let encoded = try? JSONEncoder().encode(times) {
            UserDefaults.standard.set(encoded, forKey: StreakStore.reminderTimesKey)
        }
        SharedStreakData.write(streaks: snapshot.streaks)

        let times = snapshot.reminderTimes ?? storedReminderTimes()
        let counts = NotificationManager.unfilledCounts(for: snapshot.streaks)
        await NotificationManager.refresh(
            times: times,
            unfilledCounts: counts,
            totalStreaks: snapshot.streaks.count
        )
    }

    private static func storedReminderTimes() -> [ReminderTime] {
        guard let data = UserDefaults.standard.data(forKey: StreakStore.reminderTimesKey),
              let decoded = try? JSONDecoder().decode([ReminderTime].self, from: data) else {
            return NotificationManager.defaultReminderTimes
        }
        return decoded
    }
}
