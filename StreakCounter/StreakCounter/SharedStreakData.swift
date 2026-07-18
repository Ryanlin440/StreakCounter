//
//  SharedStreakData.swift
//  StreakCounter
//

import Foundation
import WidgetKit

/// The streak list shared with the widget extension through the app group.
/// The app writes on every change; the widget only reads.
enum SharedStreakData {

    static let appGroupID = "group.com.ryanlin.StreakCounter2"

    private static let streaksKey = "sharedStreaks"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func write(streaks: [Streak]) {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(streaks) {
            defaults.set(data, forKey: streaksKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func read() -> [Streak] {
        guard let data = defaults?.data(forKey: streaksKey),
              let decoded = try? JSONDecoder().decode([Streak].self, from: data) else {
            return []
        }
        return decoded
    }

    static func clear() {
        defaults?.removeObject(forKey: streaksKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
