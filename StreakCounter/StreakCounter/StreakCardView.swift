//
//  StreakCardView.swift
//  StreakCounter
//

import SwiftUI

struct StreakCardView: View {

    let streak: Streak
    @ObservedObject var store: StreakStore
    @EnvironmentObject private var auth: AuthService

    @State private var showCardSettings = false

    private var textColor: Color {
        streak.textColor.color
    }

    private var scale: CGFloat {
        CGFloat(store.cardSize)
    }

    private var todayStatusForDisplay: DayStatus {
        store.status(for: Date(), on: streak) ?? .neutral
    }

    private var hasUnlockedUnseenMessage: Bool {
        streak.milestoneMessages.contains { $0.isUnlocked }
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 10 * scale) {

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2 * scale) {
                    Text(streak.name)
                        .font(.system(size: 17 * scale, weight: .semibold))
                        .foregroundColor(textColor)
                    if !streak.notes.isEmpty {
                        Text(streak.notes)
                            .font(.system(size: 12 * scale))
                            .italic()
                            .foregroundColor(textColor.opacity(0.7))
                            .lineLimit(2)
                    }
                }

                Spacer()

                if hasUnlockedUnseenMessage {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 14 * scale))
                        .foregroundColor(.orange)
                }

                Button {
                    showCardSettings = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20 * scale))
                        .foregroundColor(textColor.opacity(0.8))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 16 * scale) {
                statCounter(
                    value: store.currentStreak(for: streak),
                    title: "Current",
                    systemImage: "flame.fill"
                )
                statCounter(
                    value: store.longestStreak(for: streak),
                    title: "Best",
                    systemImage: "trophy.fill"
                )
                Spacer()
                Text("Started \(streak.startDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 11 * scale))
                    .foregroundColor(textColor.opacity(0.7))
            }

            HStack(spacing: 8 * scale) {
                ForEach(DayStatus.allCases, id: \.self) { status in
                    StatusButton(
                        status: status,
                        isSelected: todayStatusForDisplay == status,
                        scale: scale
                    ) {
                        store.setStatus(status, for: Date(), on: streak)
                    }
                }

                NavigationLink {
                    StreakCalendarView(streakID: streak.id, store: store)
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 18 * scale))
                        .foregroundColor(textColor)
                        .padding(8 * scale)
                        .background(textColor.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14 * scale)
        .background(streak.cardColor.color)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
        .sheet(isPresented: $showCardSettings) {
            StreakCardSettingsSheet(streakID: streak.id, store: store)
                .environmentObject(auth)
        }
    }

    @ViewBuilder
    private func statCounter(value: Int, title: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4 * scale) {
                Image(systemName: systemImage)
                    .font(.system(size: 11 * scale))
                Text("\(value)")
                    .font(.system(size: 19 * scale, weight: .bold))
            }
            .foregroundColor(textColor)
            Text(title)
                .font(.system(size: 10 * scale))
                .foregroundColor(textColor.opacity(0.7))
        }
    }
}

struct StatusButton: View {

    let status: DayStatus
    let isSelected: Bool
    var scale: CGFloat = 1.0
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: status.symbol)
                .font(.system(size: 17 * scale, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8 * scale)
                .background(isSelected ? Color.gray.opacity(0.5) : status.color)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status.displayName)
    }
}
