//
//  Streak.swift
//  StreakCounter
//
//  Created by Ryan Lin on 6/8/26.
//

import Foundation

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

    init(
        id: UUID = UUID(),
        name: String,
        startDate: Date = Date(),
        completedDates: [Date] = [],
        dayStatuses: [String: DayStatus] = [:],
        cardColor: CodableColor = .white,
        textColor: CodableColor = CodableColor(red: 0, green: 0, blue: 0),
        notes: String = "",
        milestoneMessages: [MilestoneMessage] = []
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
    }

    enum CodingKeys: String, CodingKey {
        case id, name, startDate, completedDates, dayStatuses, cardColor, textColor, notes, milestoneMessages
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
        if todayStatus == .notDone || todayStatus == .neutral {
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
        let status = dayStatuses[Streak.dateKey(now)]
        return status == nil || status == .neutral
    }
}
