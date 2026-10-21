//
//  Streak+Statistics.swift
//  StreakCounter
//
//  App-only statistics aggregates. Kept out of Streak.swift so the widget
//  target (which compiles Streak.swift) stays lean.
//

import Foundation

extension Streak {

    // MARK: - Multiple Times a Day

    /// Every completion ever recorded, summed across all days.
    var totalCompletionCount: Int {
        dayCounts.values.reduce(0, +)
    }

    /// Days where the count reached the daily target.
    var targetMetDayCount: Int {
        dayCounts.filter { $0.value >= dailyTarget }.count
    }

    // MARK: - Weekly/Monthly

    /// Weeks/months whose goal was met, from the start of the streak's
    /// history (including backfilled pre-creation days) through the period
    /// containing `now`.
    func completedPeriodCount(asOf now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard isPeriodBased,
              let current = periodInterval(containing: now, calendar: calendar),
              var interval = periodInterval(containing: historyStartDay(calendar: calendar),
                                            calendar: calendar) else { return 0 }
        var count = 0
        while interval.start <= current.start {
            let required = requiredCount(in: interval, calendar: calendar)
            if required > 0, doneCount(in: interval, calendar: calendar) >= required {
                count += 1
            }
            guard let next = periodInterval(containing: interval.end, calendar: calendar) else { break }
            interval = next
        }
        return count
    }

    /// Number of weeks/months since the start of the streak's history
    /// (including backfilled pre-creation days), counting the current one.
    func elapsedPeriodCount(asOf now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard isPeriodBased,
              let current = periodInterval(containing: now, calendar: calendar),
              let first = periodInterval(containing: historyStartDay(calendar: calendar),
                                         calendar: calendar) else { return 0 }
        let component: Calendar.Component = type == .weekly ? .weekOfYear : .month
        let diff = calendar.dateComponents([component], from: first.start, to: current.start)
        let periods = (type == .weekly ? diff.weekOfYear : diff.month) ?? 0
        return max(1, periods + 1)
    }
}
