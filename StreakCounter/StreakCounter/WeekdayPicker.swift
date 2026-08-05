//
//  WeekdayPicker.swift
//  StreakCounter
//

import SwiftUI

/// A row of tappable weekday chips for choosing a specific-weekday schedule.
/// Works in Calendar weekday numbers (1 = Sunday … 7 = Saturday) and shows
/// days ordered from the locale's first weekday.
struct WeekdayPicker: View {

    @Binding var selection: [Int]

    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(orderedWeekdays, id: \.self) { weekday in
                let isSelected = selection.contains(weekday)
                Button {
                    if isSelected {
                        selection.removeAll { $0 == weekday }
                    } else {
                        selection.append(weekday)
                        selection.sort()
                    }
                } label: {
                    Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(isSelected ? Color.accentColor : Color(.systemGray5))
                        .foregroundColor(isSelected ? .white : .primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}
