//
//  Streak.swift
//  StreakCounter
//
//  Created by Ryan Lin on 6/8/26.
//

import Foundation

/// How often a streak is meant to be completed. Determines the card's
/// control, its statistics, and how the flame streak value is computed.
enum StreakType: String, Codable, CaseIterable, Identifiable {
    case multipleDaily
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .multipleDaily: return "Multiple Times a Day"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    /// Section order on the main page and in Statistics.
    static let displayOrder: [StreakType] = [.multipleDaily, .daily, .weekly, .monthly]
}

/// How a weekly/monthly goal is defined: complete every scheduled weekday,
/// or complete any N days within the week/month.
enum GoalMode: String, Codable {
    case specificWeekdays
    case countPerPeriod
}

struct Streak: Identifiable, Codable {
    let id: UUID
    var name: String
    var startDate: Date
    var completedDates: [Date]
    var dayStatuses: [String: DayStatus]
    var cardColor: CodableColor
    var textColor: CodableColor
    var notes: String
    var milestoneMessages: [MilestoneMessage]
    var type: StreakType
    /// Completions per day needed for a Multiple Times a Day streak (>= 1).
    var dailyTarget: Int
    /// Goal definition for weekly/monthly streaks.
    var goalMode: GoalMode
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday) the streak is
    /// active on, when goalMode == .specificWeekdays.
    var scheduledWeekdays: [Int]
    /// Days required per week/month, when goalMode == .countPerPeriod (>= 1).
    var periodTarget: Int
    /// Per-day completion counts for Multiple Times a Day streaks,
    /// keyed by Streak.dateKey.
    var dayCounts: [String: Int]
    /// Per-day notes, keyed by Streak.dateKey. Separate from the
    /// streak-level `notes`.
    var dayNotes: [String: String]

    init(
        id: UUID = UUID(),
        name: String,
        startDate: Date = Date(),
        completedDates: [Date] = [],
        dayStatuses: [String: DayStatus] = [:],
        cardColor: CodableColor = .white,
        textColor: CodableColor = CodableColor(red: 0, green: 0, blue: 0),
        notes: String = "",
        milestoneMessages: [MilestoneMessage] = [],
        type: StreakType = .daily,
        dailyTarget: Int = 1,
        goalMode: GoalMode = .countPerPeriod,
        scheduledWeekdays: [Int] = [],
        periodTarget: Int = 1,
        dayCounts: [String: Int] = [:],
        dayNotes: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.completedDates = completedDates
        self.dayStatuses = dayStatuses
        self.cardColor = cardColor
        self.textColor = textColor
        self.notes = notes
        self.milestoneMessages = milestoneMessages
        self.type = type
        self.dailyTarget = max(1, dailyTarget)
        self.goalMode = goalMode
        self.scheduledWeekdays = scheduledWeekdays
        self.periodTarget = max(1, periodTarget)
        self.dayCounts = dayCounts
        self.dayNotes = dayNotes
    }

    enum CodingKeys: String, CodingKey {
        case id, name, startDate, completedDates, dayStatuses, cardColor, textColor, notes, milestoneMessages
        case type, dailyTarget, goalMode, scheduledWeekdays, periodTarget, dayCounts, dayNotes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.startDate = try c.decode(Date.self, forKey: .startDate)
        self.completedDates = try c.decodeIfPresent([Date].self, forKey: .completedDates) ?? []
        self.dayStatuses = try c.decodeIfPresent([String: DayStatus].self, forKey: .dayStatuses) ?? [:]
        let card = try c.decodeIfPresent(CodableColor.self, forKey: .cardColor) ?? .white
        self.cardColor = card
        self.textColor = try c.decodeIfPresent(CodableColor.self, forKey: .textColor)
            ?? CodableColor(red: 0, green: 0, blue: 0)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.milestoneMessages = try c.decodeIfPresent([MilestoneMessage].self, forKey: .milestoneMessages) ?? []
        // Streaks saved before types existed decode as plain Daily streaks,
        // so old local caches and Firestore snapshots migrate lazily.
        self.type = try c.decodeIfPresent(StreakType.self, forKey: .type) ?? .daily
        self.dailyTarget = max(1, try c.decodeIfPresent(Int.self, forKey: .dailyTarget) ?? 1)
        self.goalMode = try c.decodeIfPresent(GoalMode.self, forKey: .goalMode) ?? .countPerPeriod
        self.scheduledWeekdays = try c.decodeIfPresent([Int].self, forKey: .scheduledWeekdays) ?? []
        self.periodTarget = max(1, try c.decodeIfPresent(Int.self, forKey: .periodTarget) ?? 1)
        self.dayCounts = try c.decodeIfPresent([String: Int].self, forKey: .dayCounts) ?? [:]
        self.dayNotes = try c.decodeIfPresent([String: String].self, forKey: .dayNotes) ?? [:]
    }

    // Cached: creating a DateFormatter per call is expensive, and dateKey is
    // called once per day when scanning a streak's history.
    private static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dateKey(_ date: Date) -> String {
        let day = Calendar.current.startOfDay(for: date)
        return keyFormatter.string(from: day)
    }

    static func date(fromKey key: String) -> Date? {
        keyFormatter.date(from: key)
    }
}

// Pure streak math, kept on the model (instead of StreakStore) so the
// widget extension can compute counts without the store or Firestore.
extension Streak {

    /// Consecutive days marked Done, ending today or yesterday.
    func currentStreakValue(asOf now: Date = Date()) -> Int {

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let todayStatus = dayStatuses[Streak.dateKey(today)]

        // Today explicitly marked as not done or neutral breaks the streak.
        // For Multiple Times a Day, Neutral means partial progress (derived
        // from the count), so the day is still pending rather than broken.
        if todayStatus == .notDone {
            return 0
        }
        if todayStatus == .neutral && type != .multipleDaily {
            return 0
        }

        let doneDays = Set(completedDates.map { calendar.startOfDay(for: $0) })

        var anchor: Date
        if doneDays.contains(today) {
            anchor = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  doneDays.contains(yesterday) {
            anchor = yesterday
        } else {
            return 0
        }

        var count = 1
        while let prev = calendar.date(byAdding: .day, value: -1, to: anchor),
              doneDays.contains(prev) {
            count += 1
            anchor = prev
        }
        return count
    }

    /// True while the streak hasn't been meaningfully filled out today:
    /// no status yet, or still on the default Neutral.
    func isUnfilledToday(asOf now: Date = Date()) -> Bool {
        isUnfilled(on: now)
    }

    /// Type-aware "still needs attention on this day" check. Drives the
    /// app-icon badge and reminder copy, so scheduling rules matter here:
    /// a weekly streak on an off-day, or one whose week is already complete,
    /// must not nag.
    func isUnfilled(on date: Date) -> Bool {
        switch type {
        case .daily:
            let status = dayStatuses[Streak.dateKey(date)]
            return status == nil || status == .neutral
        case .multipleDaily:
            return count(on: date) < dailyTarget
        case .weekly, .monthly:
            switch goalMode {
            case .specificWeekdays:
                guard isActive(on: date) else { return false }
                let status = dayStatuses[Streak.dateKey(date)]
                return status == nil || status == .neutral
            case .countPerPeriod:
                guard !isPeriodComplete(containing: date) else { return false }
                let status = dayStatuses[Streak.dateKey(date)]
                return status == nil || status == .neutral
            }
        }
    }
}

// MARK: - Scheduling & period math
// Kept on the model (like the streak math above) so the widget extension
// can compute progress for every streak type without the store.
extension Streak {

    var isPeriodBased: Bool { type == .weekly || type == .monthly }

    /// Times completed on the given day (Multiple Times a Day streaks).
    func count(on date: Date) -> Int {
        dayCounts[Streak.dateKey(date)] ?? 0
    }

    /// The user's note for the given day, if any.
    func note(on date: Date) -> String? {
        dayNotes[Streak.dateKey(date)]
    }

    /// Whether the streak can be interacted with on this date. Only weekly/
    /// monthly streaks with specific scheduled weekdays have off-days.
    func isActive(on date: Date, calendar: Calendar = .current) -> Bool {
        guard isPeriodBased, goalMode == .specificWeekdays, !scheduledWeekdays.isEmpty else {
            return true
        }
        return scheduledWeekdays.contains(calendar.component(.weekday, from: date))
    }

    /// The week or month containing `date`. Weeks follow the user's locale
    /// (Calendar.current.firstWeekday); months handle 28–31 days and leap
    /// years via Calendar. nil for day-based streak types.
    func periodInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        switch type {
        case .weekly: return calendar.dateInterval(of: .weekOfYear, for: date)
        case .monthly: return calendar.dateInterval(of: .month, for: date)
        case .daily, .multipleDaily: return nil
        }
    }

    /// Distinct days marked Done inside the interval, counting only days the
    /// streak is active on (so off-days can never contribute).
    func doneCount(in interval: DateInterval, calendar: Calendar = .current) -> Int {
        var count = 0
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            if isActive(on: day, calendar: calendar),
               dayStatuses[Streak.dateKey(day)] == .done {
                count += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }

    /// Days that must be Done for the period to count as complete.
    /// The period containing `startDate` only requires days on or after it,
    /// so a streak created mid-week isn't penalized for days that never
    /// applied to it.
    func requiredCount(in interval: DateInterval, calendar: Calendar = .current) -> Int {
        guard isPeriodBased else { return 0 }
        let firstDay = calendar.startOfDay(for: startDate)
        let clampedStart = max(calendar.startOfDay(for: interval.start), firstDay)
        guard clampedStart < interval.end else { return 0 }

        switch goalMode {
        case .specificWeekdays:
            var count = 0
            var day = clampedStart
            while day < interval.end {
                if scheduledWeekdays.contains(calendar.component(.weekday, from: day)) {
                    count += 1
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            return count
        case .countPerPeriod:
            var available = 0
            var day = clampedStart
            while day < interval.end, available < periodTarget {
                available += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            return min(periodTarget, available)
        }
    }

    /// Whether the week/month containing `date` has met its goal.
    func isPeriodComplete(containing date: Date, calendar: Calendar = .current) -> Bool {
        guard let interval = periodInterval(containing: date, calendar: calendar) else { return false }
        let required = requiredCount(in: interval, calendar: calendar)
        guard required > 0 else { return false }
        return doneCount(in: interval, calendar: calendar) >= required
    }

    /// Whether the period can still be completed as of `now`: no scheduled
    /// day before today has been missed (specific weekdays), or enough days
    /// remain to reach the target (count per period).
    func isPeriodStillAchievable(containing date: Date, asOf now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let interval = periodInterval(containing: date, calendar: calendar) else { return false }
        let today = calendar.startOfDay(for: now)
        let firstDay = calendar.startOfDay(for: startDate)
        let clampedStart = max(calendar.startOfDay(for: interval.start), firstDay)

        switch goalMode {
        case .specificWeekdays:
            var day = clampedStart
            while day < interval.end, day < today {
                if scheduledWeekdays.contains(calendar.component(.weekday, from: day)),
                   dayStatuses[Streak.dateKey(day)] != .done {
                    return false
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            return true
        case .countPerPeriod:
            let done = doneCount(in: interval, calendar: calendar)
            let required = requiredCount(in: interval, calendar: calendar)
            var remaining = 0
            var day = max(today, clampedStart)
            while day < interval.end {
                if dayStatuses[Streak.dateKey(day)] != .done { remaining += 1 }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            return done + remaining >= required
        }
    }

    /// Consecutive complete weeks/months ending at the current period.
    /// The in-progress period counts once complete, is skipped while still
    /// achievable, and breaks the streak only once it can no longer be met.
    func currentPeriodStreak(asOf now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard isPeriodBased,
              let current = periodInterval(containing: now, calendar: calendar) else { return 0 }
        let firstPeriodStart = periodInterval(containing: startDate, calendar: calendar)?.start
            ?? calendar.startOfDay(for: startDate)

        var count = 0
        var interval = current
        if isPeriodComplete(containing: now, calendar: calendar) {
            count = 1
        } else if !isPeriodStillAchievable(containing: now, asOf: now, calendar: calendar) {
            return 0
        }

        while interval.start > firstPeriodStart {
            guard let prevDay = calendar.date(byAdding: .day, value: -1, to: interval.start),
                  let prev = periodInterval(containing: prevDay, calendar: calendar) else { break }
            let required = requiredCount(in: prev, calendar: calendar)
            // A period with nothing required (created on a day after all of
            // its scheduled days) can't extend or break the run.
            if required == 0 { break }
            guard doneCount(in: prev, calendar: calendar) >= required else { break }
            count += 1
            interval = prev
        }
        return count
    }

    /// Longest run of consecutive complete weeks/months over the streak's
    /// whole history, including the current run.
    func longestPeriodStreak(asOf now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard isPeriodBased,
              let current = periodInterval(containing: now, calendar: calendar),
              var interval = periodInterval(containing: startDate, calendar: calendar) else { return 0 }

        var longest = 0
        var run = 0
        while interval.start < current.start {
            let required = requiredCount(in: interval, calendar: calendar)
            if required > 0 {
                if doneCount(in: interval, calendar: calendar) >= required {
                    run += 1
                    longest = max(longest, run)
                } else {
                    run = 0
                }
            }
            guard let next = periodInterval(containing: interval.end, calendar: calendar) else { break }
            interval = next
        }
        return max(longest, currentPeriodStreak(asOf: now, calendar: calendar))
    }

    /// The flame value shown on cards and in the widget: consecutive days
    /// for day-based types, consecutive complete periods for weekly/monthly.
    func displayStreakValue(asOf now: Date = Date()) -> Int {
        switch type {
        case .daily, .multipleDaily:
            return currentStreakValue(asOf: now)
        case .weekly, .monthly:
            return currentPeriodStreak(asOf: now)
        }
    }

    /// Short unit for the flame/trophy values ("days", "wks", "mos").
    var streakUnit: String {
        switch type {
        case .daily, .multipleDaily: return "days"
        case .weekly: return "wks"
        case .monthly: return "mos"
        }
    }

    /// Scheduled weekdays as "Mon · Wed · Fri", ordered from the locale's
    /// first weekday.
    var scheduledWeekdaysDescription: String {
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday
        let ordered = scheduledWeekdays
            .filter { (1...7).contains($0) }
            .sorted { (($0 - first + 7) % 7) < (($1 - first + 7) % 7) }
        return ordered.map { symbols[$0 - 1] }.joined(separator: " · ")
    }

    /// One-line summary of the streak's goal, shown under the card title
    /// and in the widget.
    var goalDescription: String {
        switch type {
        case .daily:
            return "Daily"
        case .multipleDaily:
            return "\(dailyTarget)× a day"
        case .weekly:
            switch goalMode {
            case .specificWeekdays:
                return scheduledWeekdays.isEmpty ? "Weekly" : "\(scheduledWeekdaysDescription) · Weekly"
            case .countPerPeriod:
                return "\(periodTarget) \(periodTarget == 1 ? "day" : "days") / week"
            }
        case .monthly:
            switch goalMode {
            case .specificWeekdays:
                return scheduledWeekdays.isEmpty ? "Monthly" : "\(scheduledWeekdaysDescription) · Monthly"
            case .countPerPeriod:
                return "\(periodTarget) \(periodTarget == 1 ? "day" : "days") / month"
            }
        }
    }

    /// Caption for period progress lines: "this week" / "this month".
    var periodCaption: String {
        switch type {
        case .weekly: return "this week"
        case .monthly: return "this month"
        case .daily, .multipleDaily: return "today"
        }
    }
}
