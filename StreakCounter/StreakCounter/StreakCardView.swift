//
//  StreakCardView.swift
//  StreakCounter
//

import SwiftUI

struct StreakCardView: View {

    let streak: Streak
    @ObservedObject var store: StreakStore
    /// Called when the user taps the calendar button. Navigation is owned by
    /// the list (via `navigationDestination(item:)`) so the card doesn't need
    /// a NavigationLink, which would make the whole List row tappable and
    /// draw a disclosure chevron.
    var onOpenCalendar: () -> Void = {}
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
        streak.milestoneMessages.contains { $0.isUnlocked && $0.openedAt == nil }
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
                StatusSegmentedControl(
                    current: todayStatusForDisplay,
                    scale: scale
                ) { status in
                    store.setStatus(status, for: Date(), on: streak)
                }

                Button(action: onOpenCalendar) {
                    Image(systemName: "calendar")
                        .font(.system(size: 18 * scale))
                        .foregroundColor(textColor)
                        .padding(8 * scale)
                        .background(textColor.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .topTrailing) {
                    if store.hasMissedDays(for: streak) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13 * scale))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                            .offset(x: 3 * scale, y: -3 * scale)
                            .accessibilityLabel("Some past days were never filled out")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14 * scale)
        .background(cardBackground)
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
    private var cardBackground: some View {
        ZStack {
            streak.cardColor.color
            if let data = store.cardImageData(for: streak),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            }
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

/// A fused three-state segmented control for today's status: Wrong / Clear /
/// Right. The active segment gets its color theme and a soft matching glow;
/// the other two drop to a dim secondary look with a transparent background.
struct StatusSegmentedControl: View {

    /// The store-backed status this control mirrors (defaults to Neutral
    /// upstream when no status has been set for today).
    let current: DayStatus
    var scale: CGFloat = 1.0
    var onSelect: (DayStatus) -> Void

    // Middle "Clear" is the default until the store's value arrives.
    @State private var selection: DayStatus = .neutral

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 4 * scale) {
                ForEach(DayStatus.allCases, id: \.self) { status in
                    segment(for: status)
                }
            }
            // No inset at all: the segment capsules run edge-to-edge, so the
            // x hugs the container's left curve, the checkmark its right
            // curve, and every segment spans the full height.
            // Container look: tweak the grey shade (.systemGray2–6) and the
            // opacity (0 = invisible, 1 = solid) here.
            .background(Color(.systemGray3).opacity(0.3))
            .clipShape(Capsule())
            .contentShape(Capsule())
            // A single tap selects the segment under the finger. Handled
            // here on the container rather than by the segment Buttons,
            // whose taps the List row swallows in favor of the drag below.
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        select(status(atX: value.location.x, width: proxy.size.width))
                    }
            )
            // Slide across the control to change the selection live; the
            // store is only updated once, when the finger lifts. High
            // priority so drags that start on a segment button aren't
            // claimed by the button — the highlight then follows the
            // finger into each segment it crosses.
            .highPriorityGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        let status = status(atX: value.location.x, width: proxy.size.width)
                        if status != selection {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selection = status
                            }
                        }
                    }
                    .onEnded { value in
                        select(status(atX: value.location.x, width: proxy.size.width))
                    }
            )
        }
        // The control's overall height: every segment stretches to fill it
        // exactly, regardless of each symbol's own glyph height.
        .frame(height: 36 * scale)
        .onAppear { selection = current }
        // Keep in sync with changes made elsewhere (calendar, other devices).
        .onChange(of: current) { _, newValue in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selection = newValue
            }
        }
    }

    /// Animate the selection to `status` and commit it to the store.
    private func select(_ status: DayStatus) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selection = status
        }
        onSelect(status)
    }

    /// The segment under a horizontal position, for slide-to-select.
    private func status(atX x: CGFloat, width: CGFloat) -> DayStatus {
        let all = DayStatus.allCases
        guard width > 0 else { return selection }
        let index = Int(x / (width / CGFloat(all.count)))
        return all[min(all.count - 1, max(0, index))]
    }

    @ViewBuilder
    private func segment(for status: DayStatus) -> some View {
        let isSelected = selection == status
        Button {
            select(status)
        } label: {
            Image(systemName: status.segmentSymbol)
                .font(.system(size: 14 * scale, weight: .bold))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(status.segmentColor)
                            .shadow(
                                color: status.segmentColor.opacity(0.5),
                                radius: 5 * scale,
                                x: 0,
                                y: 2 * scale
                            )
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status.segmentTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension DayStatus {

    var segmentTitle: String {
        switch self {
        case .notDone: return "Wrong"
        case .neutral: return "Clear"
        case .done: return "Right"
        }
    }

    var segmentSymbol: String {
        switch self {
        case .notDone: return "xmark"
        case .neutral: return "circle"
        case .done: return "checkmark"
        }
    }

    var segmentColor: Color {
        switch self {
        case .notDone: return Color(.systemRed)
        case .neutral: return Color(.systemGray2)
        case .done: return Color(.systemGreen)
        }
    }
}
