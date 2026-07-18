//
//  StreakStore.swift
//  StreakCounter
//
//  Created by Ryan Lin on 6/8/26.
//

import Foundation
import Combine
import SwiftUI
import UIKit
import FirebaseAuth

@MainActor
class StreakStore: ObservableObject {

    @Published var streaks: [Streak] = []
    @Published var backgroundImageData: Data?
    /// Per-card background photos, keyed by streak ID. Stored on-device only
    /// (like `backgroundImageData`) — not part of the synced snapshot, so a
    /// full-res photo can't push the Firestore document over its size limit.
    @Published var cardImages: [UUID: Data] = [:]
    @Published var backgroundColor: CodableColor = .appBackground
    @Published var cardSize: Double = 1.0
    /// Times of day the user wants daily reminders. Stored on-device.
    @Published var reminderTimes: [ReminderTime] = NotificationManager.defaultReminderTimes

    static let defaultCardSize: Double = 1.0

    /// Hard cap so the pre-scheduled reminder requests stay well under
    /// iOS's 64 pending-notification limit.
    static let maxReminderTimes = 8

    private let backgroundColorKey = "backgroundColor"
    private let cardSizeKey = "cardSize"
    /// Also read by BackgroundRefresh, which reschedules reminders without a store.
    static let reminderTimesKey = "reminderTimes"

    private var sync: FirestoreSync?
    private var authHandle: AuthStateDidChangeListenerHandle?

    init() {
        load()
        loadCardImages()
        loadBackgroundImage()
        loadBackgroundColor()
        loadCardSize()
        loadReminderTimes()
        setupSync()
        // Seed the widget on launch so it has data before the first change.
        SharedStreakData.write(streaks: streaks)
    }

    deinit {
        if let authHandle {
            Auth.auth().removeStateDidChangeListener(authHandle)
        }
    }

    // MARK: - Sync wiring

    private func setupSync() {
        sync = FirestoreSync(store: self)

        if let uid = Auth.auth().currentUser?.uid {
            sync?.start(for: uid)
        }

        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                if let user {
                    self.sync?.start(for: user.uid)
                } else {
                    self.sync?.stop()
                    self.clearLocalData()
                }
            }
        }
    }

    /// Wipes the on-device cache. Used when the user signs out so the
    /// next person to open the app on this device sees a fresh slate.
    /// Remote data in Firestore is untouched.
    private func clearLocalData() {
        for id in cardImages.keys {
            try? FileManager.default.removeItem(at: cardImageURL(for: id))
        }
        cardImages = [:]

        streaks = []
        cardSize = StreakStore.defaultCardSize
        backgroundColor = .appBackground
        backgroundImageData = nil
        reminderTimes = NotificationManager.defaultReminderTimes

        UserDefaults.standard.removeObject(forKey: "streaks")
        UserDefaults.standard.removeObject(forKey: backgroundColorKey)
        UserDefaults.standard.removeObject(forKey: cardSizeKey)
        UserDefaults.standard.removeObject(forKey: Self.reminderTimesKey)
        try? FileManager.default.removeItem(at: backgroundImageURL)

        SharedStreakData.clear()
        refreshNotifications()
    }

    /// Pause/resume the Firestore listener. Used while deleting the account
    /// so the listener doesn't recreate the user document we just removed.
    func stopSync() {
        sync?.stop()
    }

    func resumeSync() {
        if let uid = Auth.auth().currentUser?.uid {
            sync?.start(for: uid)
        }
    }

    func snapshotForSync() -> StreakStoreSnapshot {
        StreakStoreSnapshot(
            streaks: streaks,
            cardSize: cardSize,
            backgroundColor: backgroundColor,
            reminderTimes: reminderTimes
        )
    }

    /// Apply a snapshot received from Firestore. Writes to the local
    /// cache so the offline UI sees the merged state too.
    func applyRemoteSnapshot(_ snapshot: StreakStoreSnapshot) {
        self.streaks = snapshot.streaks
        self.cardSize = snapshot.cardSize
        self.backgroundColor = snapshot.backgroundColor
        if let times = snapshot.reminderTimes {
            self.reminderTimes = times
            saveReminderTimes()
        }

        if let data = try? JSONEncoder().encode(streaks) {
            UserDefaults.standard.set(data, forKey: "streaks")
        }
        if let data = try? JSONEncoder().encode(backgroundColor) {
            UserDefaults.standard.set(data, forKey: backgroundColorKey)
        }
        UserDefaults.standard.set(cardSize, forKey: cardSizeKey)

        SharedStreakData.write(streaks: streaks)
        refreshNotifications()
    }

    // MARK: - Streak CRUD

    func addStreak(name: String) {

        let streak = Streak(
            id: UUID(),
            name: name,
            startDate: Date(),
            completedDates: [],
            dayStatuses: [:],
            cardColor: .white
        )

        streaks.append(streak)
        save()
    }

    func deleteStreak(_ streak: Streak) {
        streaks.removeAll { $0.id == streak.id }
        setCardImage(data: nil, for: streak)
        save()
    }

    func moveStreak(from offsets: IndexSet, to destination: Int) {
        streaks.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    func renameStreak(_ streak: Streak, to newName: String) {
        guard let index = streaks.firstIndex(where: { $0.id == streak.id }) else { return }
        streaks[index].name = newName
        save()
    }

    func setNotes(_ notes: String, for streak: Streak) {
        guard let index = streaks.firstIndex(where: { $0.id == streak.id }) else { return }
        streaks[index].notes = notes
        save()
    }

    func addMilestoneMessage(targetDays: Int, message: String, for streak: Streak) {
        guard let index = streaks.firstIndex(where: { $0.id == streak.id }) else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = MilestoneMessage(targetDays: targetDays, message: trimmed)
        streaks[index].milestoneMessages.append(new)
        streaks[index].milestoneMessages.sort { $0.targetDays < $1.targetDays }
        unlockMilestonesIfNeeded(at: index)
        save()
    }

    func deleteMilestoneMessage(id: UUID, for streak: Streak) {
        guard let index = streaks.firstIndex(where: { $0.id == streak.id }) else { return }
        streaks[index].milestoneMessages.removeAll { $0.id == id }
        save()
    }

    func clearStreakData(_ streak: Streak) {
        guard let index = streaks.firstIndex(where: { $0.id == streak.id }) else { return }
        streaks[index].completedDates = []
        streaks[index].dayStatuses = [:]
        streaks[index].startDate = Date()
        for i in streaks[index].milestoneMessages.indices {
            streaks[index].milestoneMessages[i].unlockedAt = nil
        }
        save()
    }

    func clearAllStreakData() {
        for i in streaks.indices {
            streaks[i].completedDates = []
            streaks[i].dayStatuses = [:]
            streaks[i].startDate = Date()
            for j in streaks[i].milestoneMessages.indices {
                streaks[i].milestoneMessages[j].unlockedAt = nil
            }
        }
        save()
    }

    func setStatus(_ status: DayStatus, for date: Date, on streak: Streak) {

        guard let index = streaks.firstIndex(where: {
            $0.id == streak.id
        }) else {
            return
        }

        let key = Streak.dateKey(date)
        streaks[index].dayStatuses[key] = status

        if status == .done {
            if !streaks[index].completedDates.contains(where: {
                Calendar.current.isDate($0, inSameDayAs: date)
            }) {
                streaks[index].completedDates.append(date)
            }
        } else {
            streaks[index].completedDates.removeAll {
                Calendar.current.isDate($0, inSameDayAs: date)
            }
        }

        unlockMilestonesIfNeeded(at: index)
        save()
    }

    private func unlockMilestonesIfNeeded(at index: Int) {
        let current = currentStreak(for: streaks[index])
        let now = Date()
        for i in streaks[index].milestoneMessages.indices {
            if streaks[index].milestoneMessages[i].unlockedAt == nil,
               current >= streaks[index].milestoneMessages[i].targetDays {
                streaks[index].milestoneMessages[i].unlockedAt = now
            }
        }
    }

    func status(for date: Date, on streak: Streak) -> DayStatus? {
        streak.dayStatuses[Streak.dateKey(date)]
    }

    func setCardColor(_ color: Color, for streak: Streak) {

        guard let index = streaks.firstIndex(where: {
            $0.id == streak.id
        }) else {
            return
        }

        streaks[index].cardColor = CodableColor(color)
        save()
    }

    func setTextColor(_ color: Color, for streak: Streak) {

        guard let index = streaks.firstIndex(where: {
            $0.id == streak.id
        }) else {
            return
        }

        streaks[index].textColor = CodableColor(color)
        save()
    }

    func completedToday(_ streak: Streak) -> Bool {
        status(for: Date(), on: streak) == .done
    }

    /// Number of streaks the user hasn't meaningfully filled out today.
    /// A streak counts as unfilled if no status is set yet, or if it's still
    /// on the default middle "Neutral" — so switching a Done/Not Done answer
    /// back to Neutral re-increments the badge.
    /// Used for the app-icon badge and the nightly reminder text.
    var unfilledTodayCount: Int {
        streaks.filter { $0.isUnfilledToday() }.count
    }

    /// Push the current badge count and daily reminders to the system.
    func refreshNotifications() {
        let unfilled = unfilledTodayCount
        let total = streaks.count
        let times = reminderTimes
        Task {
            await NotificationManager.refresh(
                times: times,
                unfilledToday: unfilled,
                totalStreaks: total
            )
        }
    }

    // MARK: - Reminder times

    /// Adds a daily reminder at the hour/minute of the given date.
    func addReminderTime(from date: Date) {
        guard reminderTimes.count < StreakStore.maxReminderTimes else { return }
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let new = ReminderTime(hour: components.hour ?? 20, minute: components.minute ?? 0)
        reminderTimes.append(new)
        reminderTimes.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        saveReminderTimes()
        pushToCloud()
        refreshNotifications()
    }

    func removeReminderTimes(at offsets: IndexSet) {
        reminderTimes.remove(atOffsets: offsets)
        saveReminderTimes()
        pushToCloud()
        refreshNotifications()
    }

    private func saveReminderTimes() {
        if let data = try? JSONEncoder().encode(reminderTimes) {
            UserDefaults.standard.set(data, forKey: Self.reminderTimesKey)
        }
    }

    private func loadReminderTimes() {
        guard let data = UserDefaults.standard.data(forKey: Self.reminderTimesKey),
              let decoded = try? JSONDecoder().decode([ReminderTime].self, from: data) else {
            return
        }
        reminderTimes = decoded
    }

    // MARK: - Missed days

    /// True if `date` is a past day (since the card was created) left on
    /// Neutral — either never filled out (it defaults to Neutral when the day
    /// resets) or explicitly marked Neutral.
    func isMissedDay(_ date: Date, for streak: Streak) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        guard day < today, day >= calendar.startOfDay(for: streak.startDate) else {
            return false
        }
        let status = streak.dayStatuses[Streak.dateKey(day)]
        return status == nil || status == .neutral
    }

    /// Whether the streak has any past days still on Neutral.
    func hasMissedDays(for streak: Streak) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var day = calendar.startOfDay(for: streak.startDate)
        while day < today {
            let status = streak.dayStatuses[Streak.dateKey(day)]
            if status == nil || status == .neutral { return true }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return false
    }

    func currentStreak(for streak: Streak) -> Int {
        streak.currentStreakValue()
    }

    func longestStreak(for streak: Streak) -> Int {

        let calendar = Calendar.current

        let uniqueDays = Set(streak.completedDates.map { calendar.startOfDay(for: $0) })
        let dates = uniqueDays.sorted(by: <)

        guard !dates.isEmpty else {
            return 0
        }

        var longest = 1
        var current = 1

        for i in 1..<dates.count {
            let diff = calendar.dateComponents(
                [.day],
                from: dates[i - 1],
                to: dates[i]
            ).day ?? 0

            if diff == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }

        return longest
    }

    // MARK: - Not-done statistics

    /// A day counts as "not done" if the user pressed Not Done or Neutral, or
    /// if the day passed without being filled out (which defaults to Neutral).
    private func countsAsNotDone(_ date: Date, for streak: Streak) -> Bool {
        let status = streak.dayStatuses[Streak.dateKey(date)]
        if status == .notDone || status == .neutral { return true }
        guard status == nil else { return false }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        return day < today && day >= calendar.startOfDay(for: streak.startDate)
    }

    func currentNotDoneStreak(for streak: Streak) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayStatus = streak.dayStatuses[Streak.dateKey(today)]

        // Marking today as done breaks the not-done run.
        if todayStatus == .done { return 0 }

        var anchor: Date
        if todayStatus == .notDone || todayStatus == .neutral {
            anchor = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  countsAsNotDone(yesterday, for: streak) {
            anchor = yesterday
        } else {
            return 0
        }

        var count = 1
        while let prev = calendar.date(byAdding: .day, value: -1, to: anchor),
              countsAsNotDone(prev, for: streak) {
            count += 1
            anchor = prev
        }
        return count
    }

    func longestNotDoneStreak(for streak: Streak) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var day = calendar.startOfDay(for: streak.startDate)

        var longest = 0
        var current = 0

        while day <= today {
            if countsAsNotDone(day, for: streak) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        // The current run can reach back before the start date via explicitly
        // marked days, so make sure the best is never smaller than it.
        return max(longest, currentNotDoneStreak(for: streak))
    }

    /// Number of distinct days marked Done.
    func doneDayCount(for streak: Streak) -> Int {
        Set(streak.completedDates.map { Calendar.current.startOfDay(for: $0) }).count
    }

    /// Days that have passed since the card was created, counting today.
    func daysSinceCreation(for streak: Streak) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: streak.startDate)
        let today = calendar.startOfDay(for: Date())
        let diff = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        return max(1, diff + 1)
    }

    func debugAdvanceDay() {

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for i in streaks.indices {

            streaks[i].completedDates =
                streaks[i].completedDates.map {
                    Calendar.current.date(
                        byAdding: .day,
                        value: -1,
                        to: $0
                    )!
                }

            var shifted: [String: DayStatus] = [:]
            for (key, value) in streaks[i].dayStatuses {
                if let date = formatter.date(from: key),
                   let newDate = Calendar.current.date(byAdding: .day, value: -1, to: date) {
                    shifted[Streak.dateKey(newDate)] = value
                }
            }
            streaks[i].dayStatuses = shifted
        }

        save()
    }

    // MARK: - Background image

    func setBackgroundImage(data: Data?) {
        backgroundImageData = data
        if let data = data {
            try? data.write(to: backgroundImageURL)
        } else {
            try? FileManager.default.removeItem(at: backgroundImageURL)
        }
    }

    private var backgroundImageURL: URL {
        let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        return docs.appendingPathComponent("backgroundImage.dat")
    }

    private func loadBackgroundImage() {
        backgroundImageData = try? Data(contentsOf: backgroundImageURL)
    }

    // MARK: - Per-card image

    /// The photo shown behind a given card, if one has been set.
    func cardImageData(for streak: Streak) -> Data? {
        cardImages[streak.id]
    }

    /// Set or clear a card's background photo. Pass `nil` to remove it.
    /// The image is downscaled before storing to keep memory and disk small.
    func setCardImage(data: Data?, for streak: Streak) {
        let url = cardImageURL(for: streak.id)
        if let data {
            let stored = downscaledJPEG(data) ?? data
            cardImages[streak.id] = stored
            try? stored.write(to: url)
        } else {
            cardImages[streak.id] = nil
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func cardImageURL(for id: UUID) -> URL {
        let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        return docs.appendingPathComponent("cardImage-\(id.uuidString).dat")
    }

    private func loadCardImages() {
        var map: [UUID: Data] = [:]
        for streak in streaks {
            if let data = try? Data(contentsOf: cardImageURL(for: streak.id)) {
                map[streak.id] = data
            }
        }
        cardImages = map
    }

    /// Resize an image to fit within `maxDimension` and re-encode as JPEG.
    /// Returns nil if the data isn't a decodable image.
    private func downscaledJPEG(
        _ data: Data,
        maxDimension: CGFloat = 1200,
        quality: CGFloat = 0.8
    ) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longestSide = max(image.size.width, image.size.height)
        let scale = longestSide > maxDimension ? maxDimension / longestSide : 1
        if scale >= 1 {
            return image.jpegData(compressionQuality: quality)
        }
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    // MARK: - Background color

    func setBackgroundColor(_ color: Color) {
        let codable = CodableColor(color)
        backgroundColor = codable
        if let data = try? JSONEncoder().encode(codable) {
            UserDefaults.standard.set(data, forKey: backgroundColorKey)
        }
        pushToCloud()
    }

    private func loadBackgroundColor() {
        guard let data = UserDefaults.standard.data(forKey: backgroundColorKey),
              let decoded = try? JSONDecoder().decode(CodableColor.self, from: data) else {
            return
        }
        backgroundColor = decoded
    }

    // MARK: - Card size

    func setCardSize(_ size: Double) {
        cardSize = size
        UserDefaults.standard.set(size, forKey: cardSizeKey)
        pushToCloud()
    }

    private func loadCardSize() {
        let saved = UserDefaults.standard.double(forKey: cardSizeKey)
        if saved > 0 {
            cardSize = saved
        }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(streaks) {
            UserDefaults.standard.set(data, forKey: "streaks")
        }
        SharedStreakData.write(streaks: streaks)
        pushToCloud()
        refreshNotifications()
    }

    private func pushToCloud() {
        sync?.push(snapshot: snapshotForSync())
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "streaks") else { return }
        if let decoded = try? JSONDecoder().decode([Streak].self, from: data) {
            streaks = decoded
        }
    }
}
