//
//  StreakWidget.swift
//  StreakWidget
//
//  Home-screen widgets showing streak progress. Small shows one streak
//  (chosen by long-pressing the widget and editing it), medium adds a couple
//  more, and large lists several. Tapping a widget opens the app.
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

/// Everything the widget needs to render one streak, precomputed for the
/// entry's date so the views stay dumb.
struct WidgetStreakInfo: Identifiable {
    let id: UUID
    let name: String
    let type: StreakType
    let goalDescription: String
    let streakValue: Int
    let progressDone: Int
    let progressTarget: Int
    /// "today", "this week", or "this month".
    let progressCaption: String
    let unfilled: Bool
    let cardColor: CodableColor
    let textColor: CodableColor

    static func from(_ streak: Streak, at date: Date) -> WidgetStreakInfo {
        let done: Int
        let target: Int
        switch streak.type {
        case .multipleDaily:
            done = streak.count(on: date)
            target = streak.dailyTarget
        case .daily:
            done = streak.dayStatuses[Streak.dateKey(date)] == .done ? 1 : 0
            target = 1
        case .weekly, .monthly:
            if let interval = streak.periodInterval(containing: date) {
                done = streak.doneCount(in: interval)
                // Full schedule, matching the app's card and calendar totals.
                target = streak.scheduleCount(in: interval)
            } else {
                done = 0
                target = 1
            }
        }
        return WidgetStreakInfo(
            id: streak.id,
            name: streak.name,
            type: streak.type,
            goalDescription: streak.goalDescription,
            streakValue: streak.displayStreakValue(asOf: date),
            progressDone: done,
            progressTarget: target,
            progressCaption: streak.periodCaption,
            unfilled: streak.isUnfilled(on: date),
            cardColor: streak.cardColor,
            textColor: streak.textColor
        )
    }

    var isComplete: Bool {
        progressTarget > 0 && progressDone >= progressTarget
    }
}

struct StreakWidgetEntry: TimelineEntry {
    let date: Date
    /// The intent-chosen streak. nil when the user has no streaks yet.
    let primary: WidgetStreakInfo?
    /// The remaining streaks in main-page type order, for medium/large.
    let others: [WidgetStreakInfo]
}

struct StreakWidgetProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> StreakWidgetEntry {
        StreakWidgetEntry(
            date: Date(),
            primary: WidgetStreakInfo(
                id: UUID(),
                name: "Read",
                type: .daily,
                goalDescription: "Daily",
                streakValue: 12,
                progressDone: 1,
                progressTarget: 1,
                progressCaption: "today",
                unfilled: false,
                cardColor: .white,
                textColor: CodableColor(red: 0, green: 0, blue: 0)
            ),
            others: []
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
        // Same category order as the app's main page.
        let ordered = StreakType.displayOrder.flatMap { type in
            streaks.filter { $0.type == type }
        }
        let chosen = ordered.first { $0.id.uuidString == configuration.streak?.id }
            ?? ordered.first

        guard let chosen else {
            return StreakWidgetEntry(date: date, primary: nil, others: [])
        }
        let others = ordered
            .filter { $0.id != chosen.id }
            .map { WidgetStreakInfo.from($0, at: date) }
        return StreakWidgetEntry(
            date: date,
            primary: WidgetStreakInfo.from(chosen, at: date),
            others: others
        )
    }
}

// MARK: - Views

struct StreakWidgetView: View {

    var entry: StreakWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var backgroundColor: Color {
        entry.primary?.cardColor.color ?? CodableColor.white.color
    }

    private var textColor: Color {
        entry.primary?.textColor.color ?? .black
    }

    var body: some View {
        Group {
            if let primary = entry.primary {
                switch family {
                case .systemMedium:
                    mediumView(primary)
                case .systemLarge:
                    largeView(primary)
                default:
                    smallView(primary)
                }
            } else {
                emptyView
            }
        }
        .foregroundStyle(textColor)
        .containerBackground(for: .widget) {
            backgroundColor
        }
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Text("🔥")
                .font(.system(size: 28))
            Text("Add a streak in Streakora to get started")
                .font(.caption)
                .multilineTextAlignment(.center)
                .opacity(0.8)
        }
    }

    // MARK: Small

    private func smallView(_ info: WidgetStreakInfo) -> some View {
        VStack(spacing: 4) {
            Text(info.name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)

            // Bigger once the day/period is handled; the freed-up line goes
            // to the flame and count.
            Text("🔥 \(info.streakValue)")
                .font(.system(
                    size: info.unfilled ? 30 : 40,
                    weight: .heavy,
                    design: .rounded
                ))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())

            // Daily's 0/1–1/1 line carries no extra information; the other
            // types show their progress toward the goal.
            if info.type != .daily {
                progressLine(info, fontSize: 12)
            }

            if info.unfilled {
                Text("Save your streak")
                    .font(.caption)
                    .opacity(0.7)
            }
        }
    }

    // MARK: Medium

    private func mediumView(_ primary: WidgetStreakInfo) -> some View {
        HStack(spacing: 12) {
            smallView(primary)
                .frame(maxWidth: .infinity)

            if !entry.others.isEmpty {
                Rectangle()
                    .fill(textColor.opacity(0.15))
                    .frame(width: 1)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entry.others.prefix(2)) { info in
                        compactRow(info)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func compactRow(_ info: WidgetStreakInfo) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(info.name)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 4) {
                Text("🔥 \(info.streakValue)")
                    .font(.caption.weight(.bold))
                if info.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                } else if info.type != .daily {
                    Text("\(info.progressDone)/\(info.progressTarget)")
                        .font(.caption2)
                        .opacity(0.7)
                }
            }
        }
    }

    // MARK: Large

    private func largeView(_ primary: WidgetStreakInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([primary] + entry.others.prefix(5)) { info in
                largeRow(info)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func largeRow(_ info: WidgetStreakInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(info.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(info.goalDescription)
                    .font(.caption2)
                    .opacity(0.6)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text("🔥 \(info.streakValue)")
                    .font(.caption.weight(.bold))
                ProgressView(
                    value: Double(min(info.progressDone, info.progressTarget)),
                    total: Double(max(1, info.progressTarget))
                )
                .tint(info.isComplete ? .green : .orange)
                if info.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                } else {
                    Text("\(info.progressDone)/\(info.progressTarget)")
                        .font(.caption2)
                        .opacity(0.7)
                }
            }
        }
    }

    // MARK: Shared bits

    private func progressLine(_ info: WidgetStreakInfo, fontSize: CGFloat) -> some View {
        HStack(spacing: 3) {
            if info.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: fontSize - 1))
                    .foregroundStyle(.green)
            }
            Text("\(info.progressDone)/\(info.progressTarget) \(info.progressCaption)")
                .font(.system(size: fontSize, weight: .semibold))
                .opacity(info.isComplete ? 1 : 0.75)
                .foregroundStyle(info.isComplete ? .green : textColor)
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
        .description("Shows progress for streaks you choose.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
