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

    static func dateKey(_ date: Date) -> String {
        let day = Calendar.current.startOfDay(for: date)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: day)
    }
}
