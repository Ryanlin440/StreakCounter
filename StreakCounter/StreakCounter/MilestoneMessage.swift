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

    var isUnlocked: Bool { unlockedAt != nil }
}
