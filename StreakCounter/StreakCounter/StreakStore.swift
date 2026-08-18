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

/// Card shape on the main page: full-width rows, or a two-column grid of
/// smaller cards.
enum CardLayout: String, Codable, CaseIterable, Identifiable {
    case fullWidth
    case grid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fullWidth: return "Full Width"
        case .grid: return "Grid"
        }
    }
}

/// A group of cards on the main page. `type` is nil for the single
/// unsectioned group used when card labels are turned off.
struct StreakSection: Identifiable {
    let type: StreakType?
    let streaks: [Streak]

    var id: String { type?.rawValue ?? "all" }
    var title: String? { type?.displayName }
}

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
    /// The day the main page is showing/editing. Defaults to today and is
    /// never persisted — reopening the app always starts on today.
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    /// Whether cards are grouped under type headers ("card labels"). The
    /// user's drag-to-reorder arrangement is kept either way.
    @Published var showCardLabels = true
    @Published var cardLayout: CardLayout = .fullWidth

    static let defaultCardSize: Double = 1.0

    /// Hard cap so the pre-scheduled reminder requests stay well under
    /// iOS's 64 pending-notification limit.
    static let maxReminderTimes = 8

    private let backgroundColorKey = "backgroundColor"
    private let cardSizeKey = "cardSize"
    private let showCardLabelsKey = "showCardLabels"
    private let cardLayoutKey = "cardLayout"
    /// Also read by BackgroundRefresh, which reschedules reminders without a store.
    static let reminderTimesKey = "reminderTimes"

    private var sync: FirestoreSync?
    private var authHandle: AuthStateDidChangeListenerHandle?

    init() {
        load()
        // Monthly "specific weekdays" is no longer a supported combination —
        // those cards are now Daily specific-weekday cards. Convert any that
        // linger in the local cache so they land in the Daily section.
        if Self.migrateTypeChanges(&streaks) {
            persistStreaksLocally()
        }
        loadCardImages()
        loadBackgroundImage()
        loadBackgroundColor()
        loadCardSize()
        loadReminderTimes()
        loadDisplayPreferences()
        setupSync()
        // Fill in any days that elapsed unmarked, per each streak's setting.
        applyAutoFillForAll()
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
        showCardLabels = true
        cardLayout = .fullWidth
        selectedDate = Calendar.current.startOfDay(for: Date())

        UserDefaults.standard.removeObject(forKey: "streaks")
        UserDefaults.standard.removeObject(forKey: backgroundColorKey)
        UserDefaults.standard.removeObject(forKey: cardSizeKey)
        UserDefaults.standard.removeObject(forKey: Self.reminderTimesKey)
        UserDefaults.standard.removeObject(forKey: showCardLabelsKey)
        UserDefaults.standard.removeObject(forKey: cardLayoutKey)
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
            reminderTimes: reminderTimes,
            showCardLabels: showCardLabels,
            cardLayout: cardLayout.rawValue
        )
    }

    /// Apply a snapshot received from Firestore. Writes to the local
    /// cache so the offline UI sees the merged state too.
    func applyRemoteSnapshot(_ snapshot: StreakStoreSnapshot) {
        self.streaks = snapshot.streaks
        // Convert any legacy monthly + specific-weekday cards arriving from
        // another device / older app version.
        _ = Self.migrateTypeChanges(&self.streaks)
        // Re-derive the auto-fill on top of the fresh remote data, replacing
        // any fill computed earlier from a stale local cache.
        for i in streaks.indices {
            resolveAutoFill(at: i)
        }
        self.cardSize = snapshot.cardSize
        self.backgroundColor = snapshot.backgroundColor
        if let times = snapshot.reminderTimes {
            self.reminderTimes = times
            saveReminderTimes()
        }
        // Snapshots from app versions without display preferences leave the
        // local settings untouched.
        if let labels = snapshot.showCardLabels {
            self.showCardLabels = labels
            UserDefaults.standard.set(labels, forKey: showCardLabelsKey)
        }
        if let raw = snapshot.cardLayout, let layout = CardLayout(rawValue: raw) {
            self.cardLayout = layout
            UserDefaults.standard.set(raw, forKey: cardLayoutKey)
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

    // MARK: - Selected date

    /// Change the day the main page shows/edits. Future days are clamped
    /// to today — history can be corrected, but not written ahead of time.
    func selectDate(_ date: Date) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        selectedDate = min(day, today)
    }

    var isViewingToday: Bool {
        Calendar.current.isDate(selectedDate, inSameDayAs: Date())
    }

    // MARK: - Sections & sorting

    /// The card groups shown on the main page. Cards keep the user's custom
    /// order; labels only group them under type headers.
    var sectionedStreaks: [StreakSection] {
        guard !streaks.isEmpty else { return [] }
        if showCardLabels {
            return StreakType.displayOrder.compactMap { type in
                let group = streaks.filter { $0.type == type }
                return group.isEmpty ? nil : StreakSection(type: type, streaks: group)
            }
        }
        return [StreakSection(type: nil, streaks: streaks)]
    }

    /// Sections always grouped by type, regardless of the user's sort mode.
    /// Used by the Statistics page, which is organized by category.
    var typeGroupedStreaks: [StreakSection] {
        StreakType.displayOrder.compactMap { type in
            let group = streaks.filter { $0.type == type }
            return group.isEmpty ? nil : StreakSection(type: type, streaks: group)
        }
    }

    func setShowCardLabels(_ show: Bool) {
        showCardLabels = show
        UserDefaults.standard.set(show, forKey: showCardLabelsKey)
        pushToCloud()
    }

    func setCardLayout(_ layout: CardLayout) {
        cardLayout = layout
        UserDefaults.standard.set(layout.rawValue, forKey: cardLayoutKey)
        pushToCloud()
    }

    private func loadDisplayPreferences() {
        if let labels = UserDefaults.standard.object(forKey: showCardLabelsKey) as? Bool {
            showCardLabels = labels
        }
        if let raw = UserDefaults.standard.string(forKey: cardLayoutKey),
           let layout = CardLayout(rawValue: raw) {
            cardLayout = layout
        }
    }

    // MARK: - Streak CRUD

    /// Add a fully-configured streak built by the creation screen.
    func addStreak(_ streak: Streak) {
        streaks.append(streak)
        save()
    }

    func deleteStreak(_ streak: Streak) {
        streaks.removeAll { $0.id == streak.id }
        setCardImage(data: nil, for: streak)
        save()
    }

    /// Reorder rows within one section of the list. When card labels are on,
    /// the section's local indices are mapped back to positions in the master
    /// `streaks` array so the other types keep their relative order.
    func moveStreak(type: StreakType?, from offsets: IndexSet, to destination: Int) {
        guard let type else {
            streaks.move(fromOffsets: offsets, toOffset: destination)
            save()
            return
        }
        var group = streaks.filter { $0.type == type }
        group.move(fromOffsets: offsets, toOffset: destination)
        var reordered = group.makeIterator()
        for i in streaks.indices where streaks[i].type == type {
            if let next = reordered.next() { streaks[i] = next }
        }
        save()
    }

    /// Live reorder while a grid card is being dragged over another card.
    /// Not persisted — call `persistStreakOrder()` when the drag ends.
    /// With card labels on, dragging is confined to the card's own section.
    func liveMoveStreak(id: UUID, over targetID: UUID) {
        guard let from = streaks.firstIndex(where: { $0.id == id }),
              let to = streaks.firstIndex(where: { $0.id == targetID }),
              from != to else { return }
        if showCardLabels && streaks[from].type != streaks[to].type { return }
        streaks.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    /// Persist the order once a grid drag ends.
    func persistStreakOrder() {
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

    /// Records that the user read an unlocked message, which hides the
    /// envelope indicator on the card front.
    func markMilestoneMessageOpened(id: UUID, for streak: Streak) {
        guard let index = streaks.firstIndex(where: { $0.id == streak.id }),
              let msgIndex = streaks[index].milestoneMessages.firstIndex(where: { $0.id == id }),
              streaks[index].milestoneMessages[msgIndex].isUnlocked,
              streaks[index].milestoneMessages[msgIndex].openedAt == nil
        else { return }
        streaks[index].milestoneMessages[msgIndex].openedAt = Date()
        save()
    }

    func clearStreakData(_ streak: Streak) {
        guard let index = streaks.firstIndex(where: { $0.id == streak.id }) else { return }
        streaks[index].completedDates = []
        streaks[index].dayStatuses = [:]
        streaks[index].dayCounts = [:]
        streaks[index].dayNotes = [:]
        streaks[index].autoFilledDates = []
        streaks[index].startDate = Date()
        for i in streaks[index].milestoneMessages.indices {
            streaks[index].milestoneMessages[i].unlockedAt = nil
            streaks[index].milestoneMessages[i].openedAt = nil
        }
        save()
    }

    func clearAllStreakData() {
        for i in streaks.indices {
            streaks[i].completedDates = []
            streaks[i].dayStatuses = [:]
            streaks[i].dayCounts = [:]
            streaks[i].dayNotes = [:]
            streaks[i].autoFilledDates = []
            streaks[i].startDate = Date()
            for j in streaks[i].milestoneMessages.indices {
                streaks[i].milestoneMessages[j].unlockedAt = nil
                streaks[i].milestoneMessages[j].openedAt = nil
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

        // Scheduling rules: off-days of a specific-weekday streak can't be
        // marked at all.
        guard streaks[index].isActive(on: date) else { return }

        // Multiple Times a Day statuses are derived from counts, so route
        // through the count so the two never disagree.
        if streaks[index].type == .multipleDaily {
            switch status {
            case .done:
                let target = streaks[index].dailyTarget
                setCount(max(streaks[index].count(on: date), target), for: date, on: streaks[index])
            case .neutral, .notDone:
                setCount(0, for: date, on: streaks[index])
            }
            return
        }

        let key = Streak.dateKey(date)
        streaks[index].dayStatuses[key] = status
        // A hand-set day is no longer auto-managed.
        streaks[index].autoFilledDates.removeAll { $0 == key }

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

    // MARK: - Multiple Times a Day counts

    /// Set the completion count for a day, clamped to >= 0. The day's
    /// status and completedDates entry are re-derived from the count so
    /// all existing streak math keeps working.
    func setCount(_ count: Int, for date: Date, on streak: Streak) {
        guard let index = streaks.firstIndex(where: { $0.id == streak.id }) else { return }
        let clamped = max(0, count)
        let key = Streak.dateKey(date)
        streaks[index].dayCounts[key] = clamped == 0 ? nil : clamped
        // A hand-set count is no longer auto-managed.
        streaks[index].autoFilledDates.removeAll { $0 == key }
        rederiveMultiStatus(at: index, for: date)
        unlockMilestonesIfNeeded(at: index)
        save()
    }

    /// Mark a Multiple Times a Day day as explicitly "not done" while keeping
    /// whatever partial count the user logged. This closes the day out — it
    /// no longer counts as a missed/unfilled day — without erasing progress.
    func markMultiNotDone(for date: Date, on streak: Streak) {
        guard let index = streaks.firstIndex(where: { $0.id == streak.id }),
              streaks[index].type == .multipleDaily else { return }
        let key = Streak.dateKey(date)
        streaks[index].dayStatuses[key] = .notDone
        streaks[index].autoFilledDates.removeAll { $0 == key }
        streaks[index].completedDates.removeAll {
            Calendar.current.isDate($0, inSameDayAs: date)
        }
        save()
    }

    func incrementCount(for date: Date, on streak: Streak) {
        setCount(streak.count(on: date) + 1, for: date, on: streak)
    }

    func decrementCount(for date: Date, on streak: Streak) {
        setCount(streak.count(on: date) - 1, for: date, on: streak)
    }

    /// count >= target → Done; partial → Neutral; zero → no status.
    private func rederiveMultiStatus(at index: Int, for date: Date) {
        let key = Streak.dateKey(date)
        let count = streaks[index].dayCounts[key] ?? 0
        let target = max(1, streaks[index].dailyTarget)
        if count >= target {
            streaks[index].dayStatuses[key] = .done
            if !streaks[index].completedDates.contains(where: {
                Calendar.current.isDate($0, inSameDayAs: date)
            }) {
                streaks[index].completedDates.append(date)
            }
        } else {
            streaks[index].dayStatuses[key] = count > 0 ? .neutral : nil
            streaks[index].completedDates.removeAll {
                Calendar.current.isDate($0, inSameDayAs: date)
            }
        }
    }

    /// Change the daily target and re-derive every recorded day against it,
    /// so history reflects the new goal (documented behavior).
    func setDailyTarget(_ target: Int, for streak: Streak) {
        guard let index = streaks.firstIndex(where: { $0.id == streak.id }) else { return }
        streaks[index].dailyTarget = max(1, target)
        let keys = Set(streaks[index].dayCounts.keys).union(streaks[index].dayStatuses.keys)
        for key in keys {
            guard let date = Streak.date(fromKey: key) else { continue }
            rederiveMultiStatus(at: index, for: date)
        }
        resolveAutoFill(at: index)
        unlockMilestonesIfNeeded(at: index)
        save()
    }

    // MARK: - Forgotten-day behavior

    /// Set what happens to elapsed days the user never marked, and apply it
    /// immediately to this streak's history.
    func setMissBehavior(_ behavior: MissBehavior, for streak: Streak) {
        guard let index = streaks.firstIndex(where: { $0.id == streak.id }) else { return }
        streaks[index].missBehavior = behavior
        resolveAutoFill(at: index)
        save()
    }

    /// Re-apply auto-fill for every streak. Idempotent — safe to call on
    /// launch and whenever the day rolls over. Persists locally only if a
    /// streak's filled set actually changed. Never pushes to the cloud:
    /// launch/foreground run this against the local cache, which can be
    /// days behind Firestore, and pushing stale data auto-filled as missed
    /// would overwrite the real history (last write wins). The fill is
    /// derived state — every device recomputes the same fill from the
    /// synced data — so the next real edit pushing it along is enough.
    func applyAutoFillForAll(asOf now: Date = Date()) {
        var changed = false
        for i in streaks.indices {
            if resolveAutoFill(at: i, asOf: now) { changed = true }
        }
        if changed {
            persistStreaksLocally()
            refreshNotifications()
        }
    }

    /// Undo the streak's previous auto-fill, then, unless the behavior is
    /// `.default`, mark every elapsed, still-untouched, scheduled day as done
    /// or not done per the setting. Only fully-blank days are ever filled, so
    /// manual progress is never overwritten and the fill fully reverts.
    /// Returns whether the filled set changed. Does not save.
    @discardableResult
    private func resolveAutoFill(at index: Int, asOf now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let previous = streaks[index].autoFilledDates

        // 1. Revert the prior fill so re-runs and behavior changes are clean.
        // Only a day auto-marked Done ever added a completedDates entry, so
        // only that case removes one — an auto-missed day must never take a
        // real (pre-existing) completion down with it.
        for key in previous {
            let wasAutoDone = streaks[index].dayStatuses[key] == .done
            streaks[index].dayStatuses[key] = nil
            streaks[index].dayCounts[key] = nil
            if wasAutoDone, let date = Streak.date(fromKey: key) {
                streaks[index].completedDates.removeAll {
                    calendar.isDate($0, inSameDayAs: date)
                }
            }
        }
        streaks[index].autoFilledDates = []

        // 2. Re-fill for the current behavior (shared with the widget via
        // Streak.applyAutoFill). Applies to every streak type: day-based
        // cards fill each blank active day, and count-per-period cards fill
        // every blank day (which can over-count, by design).
        streaks[index].autoFilledDates = streaks[index].applyAutoFill(asOf: now, calendar: calendar)

        if streaks[index].missBehavior == .autoDone {
            unlockMilestonesIfNeeded(at: index)
        }
        return streaks[index].autoFilledDates != previous
    }

    // MARK: - Weekly/monthly goals

    /// Update a weekly/monthly streak's goal. Past periods are re-evaluated
    /// against the new goal (documented behavior — schedule history isn't kept).
    func setGoal(mode: GoalMode, weekdays: [Int], periodTarget: Int, for streak: Streak) {
        guard let index = streaks.firstIndex(where: { $0.id == streak.id }) else { return }
        streaks[index].goalMode = mode
        streaks[index].scheduledWeekdays = weekdays.filter { (1...7).contains($0) }.sorted()
        streaks[index].periodTarget = max(1, periodTarget)
        // Schedule changes alter which days are "active", so re-evaluate the
        // auto-fill (e.g. a day that's no longer scheduled shouldn't stay
        // auto-filled).
        resolveAutoFill(at: index)
        unlockMilestonesIfNeeded(at: index)
        save()
    }

    // MARK: - Day notes

    /// Set or clear (empty string) the note attached to a specific day.
    func setDayNote(_ note: String, for date: Date, on streak: Streak) {
        guard let index = streaks.firstIndex(where: { $0.id == streak.id }) else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        streaks[index].dayNotes[Streak.dateKey(date)] = trimmed.isEmpty ? nil : trimmed
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
        let counts = NotificationManager.unfilledCounts(for: streaks)
        let total = streaks.count
        let times = reminderTimes
        Task {
            await NotificationManager.refresh(
                times: times,
                unfilledCounts: counts,
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

    /// True if `date` is a past day (since the card was created) the user
    /// failed to complete, respecting the streak's type and schedule:
    /// off-days of a weekday schedule are never missed, and count-per-period
    /// goals have no per-day misses at all (missing is a week/month concept).
    func isMissedDay(_ date: Date, for streak: Streak) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        guard day < today, day >= calendar.startOfDay(for: streak.startDate) else {
            return false
        }
        switch streak.type {
        case .daily:
            // Off-days of a specific-weekday daily schedule are never missed.
            guard streak.isActive(on: day) else { return false }
            let status = streak.dayStatuses[Streak.dateKey(day)]
            return status == nil || status == .neutral
        case .multipleDaily:
            // Off-days of a specific-day schedule are never missed.
            guard streak.isActive(on: day) else { return false }
            // An explicit "not done" closes the day out even below target.
            if streak.dayStatuses[Streak.dateKey(day)] == .notDone { return false }
            return streak.count(on: day) < streak.dailyTarget
        case .weekly, .monthly:
            switch streak.goalMode {
            case .specificWeekdays:
                guard streak.isActive(on: day) else { return false }
                let status = streak.dayStatuses[Streak.dateKey(day)]
                return status == nil || status == .neutral
            case .countPerPeriod:
                return false
            }
        }
    }

    /// Whether the streak has any past days that count as missed.
    func hasMissedDays(for streak: Streak) -> Bool {
        // Count-per-period goals never produce per-day misses; skip the scan.
        if streak.isPeriodBased && streak.goalMode == .countPerPeriod { return false }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var day = calendar.startOfDay(for: streak.startDate)
        while day < today {
            if isMissedDay(day, for: streak) { return true }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return false
    }

    /// Number of past days that count as missed (for statistics).
    func missedDayCount(for streak: Streak) -> Int {
        if streak.isPeriodBased && streak.goalMode == .countPerPeriod { return 0 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var day = calendar.startOfDay(for: streak.startDate)
        var count = 0
        while day < today {
            if isMissedDay(day, for: streak) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }

    func currentStreak(for streak: Streak) -> Int {
        streak.displayStreakValue()
    }

    func longestStreak(for streak: Streak) -> Int {

        // Weekly/monthly streaks count consecutive complete periods.
        if streak.isPeriodBased {
            return streak.longestPeriodStreak()
        }

        // Specific-day schedules count consecutive scheduled days done,
        // skipping off-days (calendar-adjacency doesn't apply).
        if streak.type == .daily || streak.type == .multipleDaily,
           streak.goalMode == .specificWeekdays,
           !streak.scheduledWeekdays.isEmpty {
            return longestScheduledDailyStreak(for: streak)
        }

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

    /// Longest run of consecutive scheduled days marked Done for a
    /// specific-weekday daily streak, over its whole history.
    private func longestScheduledDailyStreak(for streak: Streak) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let done = Set(streak.completedDates.map { calendar.startOfDay(for: $0) })
        var day = calendar.startOfDay(for: streak.startDate)
        var longest = 0
        var current = 0
        while day <= today {
            if streak.isActive(on: day) {
                if done.contains(day) {
                    current += 1
                    longest = max(longest, current)
                } else if day < today {
                    // A past scheduled day that wasn't done breaks the run;
                    // a still-blank today is pending and left alone.
                    current = 0
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return max(longest, streak.currentStreakValue())
    }

    // MARK: - Not-done statistics

    /// A day counts as "not done" if the user pressed Not Done or Neutral, or
    /// if the day passed without being filled out (which defaults to Neutral).
    private func countsAsNotDone(_ date: Date, for streak: Streak) -> Bool {
        // Off-days of a specific-weekday daily schedule don't count either way.
        guard streak.isActive(on: date) else { return false }
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

        // Marking today (a scheduled day) as done breaks the not-done run.
        if streak.isActive(on: today), todayStatus == .done { return 0 }

        // Only a scheduled today explicitly marked not-done starts the run;
        // a blank or Neutral today is still pending (unmarked), so the run
        // starts from earlier days.
        var count = 0
        if streak.isActive(on: today), todayStatus == .notDone {
            count = 1
        }

        var day = today
        while let prev = calendar.date(byAdding: .day, value: -1, to: day) {
            day = prev
            // Off-days are skipped entirely — they don't extend or break it.
            if !streak.isActive(on: day) { continue }
            if countsAsNotDone(day, for: streak) {
                count += 1
            } else {
                break
            }
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
            // Off-days neither extend nor reset the run.
            if streak.isActive(on: day) {
                if countsAsNotDone(day, for: streak) {
                    current += 1
                    longest = max(longest, current)
                } else {
                    current = 0
                }
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

    /// Scheduled (active) days since creation, counting today. Matches
    /// `daysSinceCreation` for everyday streaks, but counts only the scheduled
    /// days for a specific-day daily or multiple-times-a-day streak — so its
    /// completion rate isn't diluted by off-days.
    func activeDaysSinceCreation(for streak: Streak) -> Int {
        guard streak.type == .daily || streak.type == .multipleDaily,
              streak.goalMode == .specificWeekdays,
              !streak.scheduledWeekdays.isEmpty else {
            return daysSinceCreation(for: streak)
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var day = calendar.startOfDay(for: streak.startDate)
        var count = 0
        while day <= today {
            if streak.isActive(on: day) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return max(1, count)
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

            var shiftedCounts: [String: Int] = [:]
            for (key, value) in streaks[i].dayCounts {
                if let date = formatter.date(from: key),
                   let newDate = Calendar.current.date(byAdding: .day, value: -1, to: date) {
                    shiftedCounts[Streak.dateKey(newDate)] = value
                }
            }
            streaks[i].dayCounts = shiftedCounts

            var shiftedNotes: [String: String] = [:]
            for (key, value) in streaks[i].dayNotes {
                if let date = formatter.date(from: key),
                   let newDate = Calendar.current.date(byAdding: .day, value: -1, to: date) {
                    shiftedNotes[Streak.dateKey(newDate)] = value
                }
            }
            streaks[i].dayNotes = shiftedNotes
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
        persistStreaksLocally()
        pushToCloud()
        refreshNotifications()
    }

    /// Write streaks to the local cache and the widget without touching the
    /// cloud — safe to call during `init`, before sync is wired up.
    private func persistStreaksLocally() {
        if let data = try? JSONEncoder().encode(streaks) {
            UserDefaults.standard.set(data, forKey: "streaks")
        }
        SharedStreakData.write(streaks: streaks)
    }

    /// Rewrite legacy streak-type combinations that are no longer offered.
    /// Currently: monthly + specific-weekday cards become Daily specific-
    /// weekday cards, keeping their schedule and history. Returns whether
    /// anything changed.
    @discardableResult
    private static func migrateTypeChanges(_ streaks: inout [Streak]) -> Bool {
        var changed = false
        for i in streaks.indices
        where streaks[i].type == .monthly && streaks[i].goalMode == .specificWeekdays {
            streaks[i].type = .daily
            changed = true
        }
        return changed
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
