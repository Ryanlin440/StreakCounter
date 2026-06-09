//
//  Streak.swift
//  StreakCounter
//
//  Created by Ryan Lin on 6/8/26.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
        case .neutral: return "minus"
        case .done: return "checkmark"
        }
    }
}

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: Color) {
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = Double(r)
        self.green = Double(g)
        self.blue = Double(b)
        self.alpha = Double(a)
        #else
        self.red = 1
        self.green = 1
        self.blue = 1
        self.alpha = 1
        #endif
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    // Pick black or white text so labels stay readable on any card color.
    var contrastingTextColor: Color {
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        return luminance > 0.6 ? .black : .white
    }

    static let white = CodableColor(red: 1, green: 1, blue: 1)
    static let appBackground = CodableColor(red: 250/255, green: 236/255, blue: 220/255)
}

struct Streak: Identifiable, Codable {
    let id: UUID
    var name: String
    var startDate: Date
    var completedDates: [Date]
    var dayStatuses: [String: DayStatus]
    var cardColor: CodableColor
    var textColor: CodableColor

    init(
        id: UUID = UUID(),
        name: String,
        startDate: Date = Date(),
        completedDates: [Date] = [],
        dayStatuses: [String: DayStatus] = [:],
        cardColor: CodableColor = .white,
        textColor: CodableColor = CodableColor(red: 0, green: 0, blue: 0)
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.completedDates = completedDates
        self.dayStatuses = dayStatuses
        self.cardColor = cardColor
        self.textColor = textColor
    }

    enum CodingKeys: String, CodingKey {
        case id, name, startDate, completedDates, dayStatuses, cardColor, textColor
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
    }

    static func dateKey(_ date: Date) -> String {
        let day = Calendar.current.startOfDay(for: date)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: day)
    }
}
