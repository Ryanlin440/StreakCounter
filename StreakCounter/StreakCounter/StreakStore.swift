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

    private let backgroundColorKey = "backgroundColor"

    init() {
        load()
        loadBackgroundImage()
        loadBackgroundColor()
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

        save()
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
        let doneDays = Set(streak.completedDates.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: Date())
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }

        var anchor: Date
        if doneDays.contains(today) {
            anchor = today
        } else if doneDays.contains(yesterday) {
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
