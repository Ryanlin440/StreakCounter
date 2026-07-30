//
//  MilestoneMessage.swift
//  StreakCounter
//

import Foundation

struct MilestoneMessage: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var targetDays: Int
    var message: String
    var createdAt: Date = Date()
    var unlockedAt: Date?
    /// When the user first read the message after it unlocked. Clears the
    /// envelope indicator on the card front. Optional so older saved data
    /// still decodes.
    var openedAt: Date?

    var isUnlocked: Bool { unlockedAt != nil }
}
