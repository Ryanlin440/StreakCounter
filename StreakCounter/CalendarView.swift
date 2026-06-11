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

    private let calendar = Calendar.current

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

            Text(monthYearString)
                .font(.headline)

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
                        isToday: calendar.isDateInToday(date)
                    ) { newStatus in
                        store.setStatus(newStatus, for: date, on: streak)
                    }
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
        .padding(.horizontal)
    }

    private var legend: some View {

        HStack(spacing: 16) {
            ForEach(DayStatus.allCases, id: \.self) { s in
                HStack(spacing: 4) {
                    Circle()
                        .fill(s.color)
                        .frame(width: 12, height: 12)
                    Text(s.displayName)
                        .font(.caption)
                }
            }
        }
        .padding(.top, 8)
    }

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        return formatter.shortWeekdaySymbols ?? []
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

        var cells: [Date?] = Array(repeating: nil, count: firstWeekday - 1)

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
    var onTap: (DayStatus) -> Void

    private let calendar = Calendar.current

    var body: some View {

        Menu {
            ForEach(DayStatus.allCases, id: \.self) { s in
                Button {
                    onTap(s)
                } label: {
                    Label(s.displayName, systemImage: s.symbol)
                }
            }
        } label: {

            ZStack {

                RoundedRectangle(cornerRadius: 6)
                    .fill(fillColor)

                if isToday {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.blue, lineWidth: 2)
                }

                Text("\(calendar.component(.day, from: date))")
                    .font(.callout)
                    .foregroundStyle(textColor)
            }
            .frame(height: 44)
        }
    }

    private var fillColor: Color {
        if let status = status {
            return status.color.opacity(0.85)
        } else {
            return Color.gray.opacity(0.12)
        }
    }

    private var textColor: Color {
        status == nil ? Color.primary : Color.white
    }
}
