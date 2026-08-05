//
//  CountControl.swift
//  StreakCounter
//

import SwiftUI

/// The completion control for Multiple Times a Day streaks: a minus button,
/// the day's count against its target with a thin progress bar, and a plus
/// button. Turns green with a checkmark once the target is reached.
struct CountControl: View {

    let count: Int
    let target: Int
    var scale: CGFloat = 1.0
    var textColor: Color = .primary
    var onIncrement: () -> Void
    var onDecrement: () -> Void

    private var isComplete: Bool { count >= target }

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(1, Double(count) / Double(target))
    }

    var body: some View {
        HStack(spacing: 10 * scale) {
            stepButton(systemName: "minus", action: onDecrement)
                .disabled(count <= 0)
                .opacity(count <= 0 ? 0.35 : 1)

            VStack(spacing: 4 * scale) {
                HStack(spacing: 5 * scale) {
                    Text("\(count)")
                        .font(.system(size: 17 * scale, weight: .bold))
                        .foregroundColor(isComplete ? Color(.systemGreen) : textColor)
                        .contentTransition(.numericText())
                    Text("/ \(target)")
                        .font(.system(size: 13 * scale, weight: .semibold))
                        .foregroundColor(textColor.opacity(0.6))
                    if isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14 * scale))
                            .foregroundColor(Color(.systemGreen))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Capsule()
                    .fill(textColor.opacity(0.15))
                    .frame(height: 4 * scale)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(isComplete ? Color(.systemGreen) : Color(.systemOrange))
                                .frame(width: proxy.size.width * progress)
                        }
                    }
            }
            .frame(maxWidth: .infinity)

            stepButton(systemName: "plus", action: onIncrement)
        }
        .padding(.horizontal, 6 * scale)
        .frame(height: 44 * scale)
        .background(Color(.systemGray3).opacity(0.3))
        .clipShape(Capsule())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Completed \(count) of \(target) today")
    }

    @ViewBuilder
    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15 * scale, weight: .bold))
                .foregroundColor(textColor)
                .frame(width: 34 * scale, height: 34 * scale)
                .background(textColor.opacity(0.1))
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
