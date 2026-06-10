//
//  StreakStore.swift
//  StreakCounter
//
//  Created by Ryan Lin on 6/8/26.
//

import Foundation
import Combine
import SwiftUI

class StreakStore: ObservableObject {

    @Published var streaks: [Streak] = []
    @Published var backgroundImageData: Data?
    @Published var backgroundColor: CodableColor = .appBackground
    @Published var cardSize: Double = 1.0

    static let defaultCardSize: Double = 1.0

    private let backgroundColorKey = "backgroundColor"
    private let cardSizeKey = "cardSize"

    init() {
        load()
        loadBackgroundImage()
        loadBackgroundColor()
        loadCardSize()
    }

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

    func currentStreak(for streak: Streak) -> Int {

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayStatus = streak.dayStatuses[Streak.dateKey(today)]

        // Today explicitly marked as not done or neutral breaks the streak.
        if todayStatus == .notDone || todayStatus == .neutral {
            return 0
        }

        let doneDays = Set(streak.completedDates.map { calendar.startOfDay(for: $0) })

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

    // MARK: - Background color

    func setBackgroundColor(_ color: Color) {
        let codable = CodableColor(color)
        backgroundColor = codable
        if let data = try? JSONEncoder().encode(codable) {
            UserDefaults.standard.set(data, forKey: backgroundColorKey)
        }
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
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "streaks") else { return }
        if let decoded = try? JSONDecoder().decode([Streak].self, from: data) {
            streaks = decoded
        }
    }
}
