//
//  StreakWidget.swift
//  StreakWidget
//
//  A small (2x2) home-screen widget showing one streak's name and its
//  current count. The streak is chosen by long-pressing the widget and
//  editing it; tapping the widget opens the app.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Configuration (which streak to show)

struct StreakEntity: AppEntity {
    var id: String
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Streak"
    static var defaultQuery = StreakEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct StreakEntityQuery: EntityQuery {

    func entities(for identifiers: [String]) async throws -> [StreakEntity] {
        allEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [StreakEntity] {
        allEntities()
    }

    func defaultResult() async -> StreakEntity? {
        allEntities().first
    }

    private func allEntities() -> [StreakEntity] {
        SharedStreakData.read().map {
            StreakEntity(id: $0.id.uuidString, name: $0.name)
        }
    }
}

struct SelectStreakIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Streak"
    static var description = IntentDescription("Choose which streak the widget shows.")

    @Parameter(title: "Streak")
    var streak: StreakEntity?
}

// MARK: - Timeline

struct StreakWidgetEntry: TimelineEntry {
    let date: Date
    /// nil when the user has no streaks yet.
    let name: String?
    let count: Int
    /// True when the streak hasn't been filled out yet for the entry's day.
    let unfilledToday: Bool
    let cardColor: CodableColor
    let textColor: CodableColor
}

struct StreakWidgetProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> StreakWidgetEntry {
        StreakWidgetEntry(
            date: Date(),
            name: "Read",
            count: 12,
            unfilledToday: false,
            cardColor: .white,
            textColor: CodableColor(red: 0, green: 0, blue: 0)
        )
    }

    func snapshot(for configuration: SelectStreakIntent, in context: Context) async -> StreakWidgetEntry {
        entry(for: configuration, at: Date())
    }

    func timeline(for configuration: SelectStreakIntent, in context: Context) async -> Timeline<StreakWidgetEntry> {
        let now = Date()
        var entries = [entry(for: configuration, at: now)]

        // Add an entry just past midnight so the count rolls over with the
        // new day even if nothing else triggers a reload.
        let calendar = Calendar.current
        if let midnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 30),
            matchingPolicy: .nextTime
        ) {
            entries.append(entry(for: configuration, at: midnight))
            return Timeline(entries: entries, policy: .after(midnight))
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func entry(for configuration: SelectStreakIntent, at date: Date) -> StreakWidgetEntry {
        let streaks = SharedStreakData.read()
        let chosen = streaks.first { $0.id.uuidString == configuration.streak?.id }
            ?? streaks.first

        guard let chosen else {
            return StreakWidgetEntry(
                date: date,
                name: nil,
                count: 0,
                unfilledToday: false,
                cardColor: .white,
                textColor: CodableColor(red: 0, green: 0, blue: 0)
            )
        }
        return StreakWidgetEntry(
            date: date,
            name: chosen.name,
            count: chosen.currentStreakValue(asOf: date),
            unfilledToday: chosen.isUnfilledToday(asOf: date),
            cardColor: chosen.cardColor,
            textColor: chosen.textColor
        )
    }
}

// MARK: - View

struct StreakWidgetView: View {

    var entry: StreakWidgetEntry

    var body: some View {
        VStack(spacing: 6) {
            if let name = entry.name {
                Text(name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)

                // Bigger once today is filled out; the freed-up line goes
                // to the flame and count.
                Text("🔥 \(entry.count)")
                    .font(.system(
                        size: entry.unfilledToday ? 32 : 44,
                        weight: .heavy,
                        design: .rounded
                    ))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())

                if entry.unfilledToday {
                    Text("Save your streak")
                        .font(.caption)
                        .opacity(0.7)
                }
            } else {
                Text("🔥")
                    .font(.system(size: 28))
                Text("Add a streak in Streakora to get started")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .opacity(0.8)
            }
        }
        .foregroundStyle(entry.textColor.color)
        .containerBackground(for: .widget) {
            entry.cardColor.color
        }
    }
}

// MARK: - Widget

struct StreakWidget: Widget {

    let kind: String = "StreakWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectStreakIntent.self,
            provider: StreakWidgetProvider()
        ) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Streak")
        .description("Shows the current count for a streak you choose.")
        .supportedFamilies([.systemSmall])
    }
}
