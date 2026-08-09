//
//  DayStatus.swift
//  StreakCounter
//

import SwiftUI

enum DayStatus: String, Codable, CaseIterable {
    case notDone
    case neutral
    case done

    var displayName: String {
        switch self {
        case .notDone: return "Not Done"
        case .neutral: return "Neutral"
        case .done: return "Done"
        }
    }

    var color: Color {
        switch self {
        case .notDone: return .red
        case .neutral: return .gray
        case .done: return .green
        }
    }

    var symbol: String {
        switch self {
        case .notDone: return "xmark"
        // Neutral reads as "unmarked" — the day hasn't been meaningfully
        // filled out yet.
        case .neutral: return "circle.dashed"
        case .done: return "checkmark"
        }
    }
}
