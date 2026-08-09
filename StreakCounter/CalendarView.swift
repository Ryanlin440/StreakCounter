//
//  CalendarView.swift
//  StreakCounter
//
//  Created by Ryan Lin on 6/8/26.
//

import SwiftUI

struct StreakCalendarView: View {

    let streakID: UUID
    @ObservedObject var store: StreakStore

    @State private var displayedMonth: Date = Date()
    @State private var noteDay: NoteDay?

    private let calendar = Calendar.current

    /// Identifiable wrapper so a tapped day can drive `.sheet(item:)`.
    private struct NoteDay: Identifiable {
        let date: Date
        var id: Date { date }
    }

    private var streak: Streak? {
        store.streaks.first(where: { $0.id == streakID })
    }

    var body: some View {

        VStack(spacing: 16) {

            monthHeader

            weekdayHeader

            calendarGrid

            legend

            Spacer()
        }
        .padding(.vertical)
        .frame(maxWidth: ContentView.phoneContentMaxWidth)
        .frame(maxWidth: .infinity)
        .navigationTitle(streak?.name ?? "Streak")
        .sheet(item: $noteDay) { day in
            DayNotesSheet(streakID: streakID, date: day.date, store: store)
        }
    }

    private var monthHeader: some View {

        HStack {

            Button {
                if let prev = calendar.date(
                    byAdding: .month,
                    value: -1,
                    to: displayedMonth
                ) {
                    displayedMonth = prev
                }
            } label: {
                Image(systemName: "chevron.left")
                    .padding(.horizontal)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(monthYearString)
                    .font(.headline)
                if let summary = monthSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                if let next = calendar.date(
                    byAdding: .month,
                    value: 1,
                    to: displayedMonth
                ) {
                    displayedMonth = next
                }
            } label: {
                Image(systemName: "chevron.right")
                    .padding(.horizontal)
            }
        }
        .padding(.horizontal)
    }

    /// Goal context for the displayed month: progress for monthly streaks,
    /// the goal description for the other types.
    private var monthSummary: String? {
        guard let streak else { return nil }
        if streak.type == .monthly,
           let interval = calendar.dateInterval(of: .month, for: displayedMonth) {
            // The full month's schedule, unlike requiredCount, which clamps
            // to the streak's start date and would understate the total for
            // the month the streak was created in.
            let required = streak.scheduleCount(in: interval)
            guard required > 0, interval.end > streak.startDate else {
                return streak.goalDescription
            }
            return "\(streak.doneCount(in: interval)) / \(required) this month"
        }
        return streak.goalDescription
    }

    private var weekdayHeader: some View {

        HStack {
            ForEach(weekdaySymbols, id: \.self) { sym in
                Text(sym)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }

    private var calendarGrid: some View {

        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 4),
            count: 7
        )

        return LazyVGrid(columns: columns, spacing: 4) {

            ForEach(Array(days.enumerated()), id: \.offset) { _, item in

                if let date = item, let streak = streak {
                    DayCell(
                        date: date,
                        status: store.status(for: date, on: streak),
                        isToday: calendar.isDateInToday(date),
                        isMissed: store.isMissedDay(date, for: streak),
                        isInactive: !streak.isActive(on: date),
                        isAutoFilled: streak.autoFilledDates.contains(Streak.dateKey(date)),
                        isMultiCount: streak.type == .multipleDaily,
                        count: streak.count(on: date),
                        target: streak.dailyTarget,
                        hasNote: streak.note(on: date)?.isEmpty == false,
                        onTap: { newStatus in
                            store.setStatus(newStatus, for: date, on: streak)
                        },
                        onIncrement: {
                            store.incrementCount(for: date, on: streak)
                        },
                        onDecrement: {
                            store.decrementCount(for: date, on: streak)
                        },
                        onMarkNotDone: {
                            store.markMultiNotDone(for: date, on: streak)
                        },
                        onMarkDone: {
                            store.setCount(streak.dailyTarget, for: date, on: streak)
                        },
                        onEditNote: {
                            noteDay = NoteDay(date: date)
                        }
                    )
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
        .padding(.horizontal)
    }

    private var legend: some View {

        LegendFlow(spacing: 16, rowSpacing: 8) {
            ForEach(DayStatus.allCases, id: \.self) { s in
                HStack(spacing: 4) {
                    Circle()
                        .fill(s.color)
                        .frame(width: 12, height: 12)
                    Text(s.displayName)
                        .font(.caption)
                }
            }
            if let streak, streak.goalMode == .specificWeekdays, !streak.scheduledWeekdays.isEmpty {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 12, height: 12)
                    Text("Off day")
                        .font(.caption)
                }
            }
            if let streak, streak.missBehavior != .default {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("Auto-filled")
                        .font(.caption)
                }
            }
        }
        .padding(.top, 8)
        .padding(.horizontal)
    }

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    /// Weekday column titles, Monday first.
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols // always Sunday-first
        return Array(symbols[1...]) + [symbols[0]]
    }

    private var days: [Date?] {

        guard let monthInterval = calendar.dateInterval(
            of: .month,
            for: displayedMonth
        ) else {
            return []
        }

        let firstDay = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let daysInMonth = calendar.range(
            of: .day,
            in: .month,
            for: displayedMonth
        )?.count ?? 0

        // Leading blanks in a Monday-first grid: weekday is 1 = Sunday …
        // 7 = Saturday, so Monday (2) maps to column 0.
        var cells: [Date?] = Array(repeating: nil, count: (firstWeekday + 5) % 7)

        for day in 0..<daysInMonth {
            if let date = calendar.date(
                byAdding: .day,
                value: day,
                to: firstDay
            ) {
                cells.append(date)
            }
        }

        while cells.count % 7 != 0 {
            cells.append(nil)
        }

        return cells
    }
}

struct DayCell: View {

    let date: Date
    let status: DayStatus?
    let isToday: Bool
    /// A past day that counts as missed for this streak's type/schedule.
    var isMissed: Bool = false
    /// Off-day of a specific-weekday schedule: greyed out and not markable.
    var isInactive: Bool = false
    /// The status was written by auto-fill (a forgotten day), not by hand.
    var isAutoFilled: Bool = false
    /// Multiple Times a Day streaks show a count and use +1/−1 instead of
    /// the status menu.
    var isMultiCount: Bool = false
    var count: Int = 0
    var target: Int = 1
    var hasNote: Bool = false
    var onTap: (DayStatus) -> Void
    var onIncrement: () -> Void = {}
    var onDecrement: () -> Void = {}
    /// Marks the day not done, keeping whatever partial count was logged.
    var onMarkNotDone: () -> Void = {}
    /// Sets a Multiple Times a Day count straight to the target (n/n).
    var onMarkDone: () -> Void = {}
    var onEditNote: () -> Void = {}

    private let calendar = Calendar.current

    var body: some View {

        Menu {
            if isInactive {
                // Off days can't be marked, but a note is still allowed.
            } else if isMultiCount {
                Button(action: onMarkDone) {
                    Label("Done (\(target)/\(target))", systemImage: "checkmark.circle")
                }
                .disabled(count >= target)
                Button(action: onMarkNotDone) {
                    Label("Not done", systemImage: "xmark.circle")
                }
                Divider()
                Button(action: onIncrement) {
                    Label("+1", systemImage: "plus")
                }
                Button(action: onDecrement) {
                    Label("−1", systemImage: "minus")
                }
                .disabled(count <= 0)
            } else {
                // Ordered Done → Neutral → Not Done so the positive action sits on top.
                ForEach(DayStatus.allCases.reversed(), id: \.self) { s in
                    Button {
                        onTap(s)
                    } label: {
                        Label(s.displayName, systemImage: s.symbol)
                    }
                }
            }

            Divider()

            Button(action: onEditNote) {
                Label(hasNote ? "Edit note…" : "Note…",
                      systemImage: hasNote ? "note.text" : "square.and.pencil")
            }
        } label: {

            ZStack {

                RoundedRectangle(cornerRadius: 6)
                    .fill(fillColor)

                if isToday {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.blue, lineWidth: 2)
                }

                VStack(spacing: 0) {
                    Text("\(calendar.component(.day, from: date))")
                        .font(isMultiCount && count > 0 ? .caption : .callout)
                        .foregroundStyle(textColor)
                    if isMultiCount && count > 0 {
                        Text("\(count)/\(target)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(textColor.opacity(0.9))
                    }
                }

                if isAutoFilled {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(textColor.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(2)
                        .accessibilityLabel("Filled in automatically")
                }

                if isMissed {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(2)
                        .accessibilityLabel("Never filled out")
                }

                if hasNote {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(3)
                        .accessibilityLabel("Has a note")
                }
            }
            .frame(height: 44)
            .opacity(isInactive ? 0.45 : 1)
        }
    }

    private var fillColor: Color {
        if isInactive {
            return Color.gray.opacity(0.06)
        }
        if let status = status {
            return status.color.opacity(0.85)
        }
        return Color.gray.opacity(0.12)
    }

    private var textColor: Color {
        if isInactive {
            return Color.secondary
        }
        return status == nil ? Color.primary : Color.white
    }
}

/// A simple left-aligned flow layout: lays items out in a row and wraps to
/// the next row when the current one runs out of width. Used for the calendar
/// legend so extra chips (Off day, Auto-filled) drop to a second line instead
/// of overflowing.
private struct LegendFlow: Layout {

    var spacing: CGFloat = 16
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalWidth = max(totalWidth, rowWidth)
                totalHeight += rowHeight + rowSpacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalWidth = max(totalWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + spacing + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            } else if x > bounds.minX {
                x += spacing
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}
