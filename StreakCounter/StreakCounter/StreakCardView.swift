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
    /// Tighter layout for the two-column grid ("Square") card layout.
    var compact: Bool = false
    @EnvironmentObject private var auth: AuthService

    @State private var showCardSettings = false
    @State private var showDayNote = false

    private var textColor: Color {
        streak.textColor.color
    }

    private var scale: CGFloat {
        CGFloat(store.cardSize) * (compact ? 0.85 : 1.0)
    }

    /// The day the card is showing/editing — the app-wide selected date.
    private var displayDate: Date {
        store.selectedDate
    }

    private var statusForDisplay: DayStatus {
        store.status(for: displayDate, on: streak) ?? .neutral
    }

    /// Off-day of a specific-weekday schedule: the card stays visible but
    /// greyed out so the user understands why it can't be interacted with.
    private var isInactiveDay: Bool {
        !streak.isActive(on: displayDate)
    }

    private var hasDayNote: Bool {
        streak.note(on: displayDate)?.isEmpty == false
    }

    /// Week/month progress toward the goal for the period containing the
    /// selected date. nil for day-based streak types.
    private var periodProgress: (done: Int, required: Int)? {
        guard let interval = streak.periodInterval(containing: displayDate) else { return nil }
        return (streak.doneCount(in: interval), streak.requiredCount(in: interval))
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
                        .lineLimit(compact ? 1 : nil)
                    Text(streak.goalDescription)
                        .font(.system(size: 11 * scale, weight: .medium))
                        .foregroundColor(textColor.opacity(0.6))
                    if !streak.notes.isEmpty && !compact {
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
                    title: streak.isPeriodBased ? "Current \(streak.streakUnit)" : "Current",
                    systemImage: "flame.fill"
                )
                statCounter(
                    value: store.longestStreak(for: streak),
                    title: streak.isPeriodBased ? "Best \(streak.streakUnit)" : "Best",
                    systemImage: "trophy.fill"
                )
                Spacer()
                if !compact {
                    Text("Started \(streak.startDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 11 * scale))
                        .foregroundColor(textColor.opacity(0.7))
                }
            }

            if let progress = periodProgress, !isInactiveDay {
                HStack(spacing: 4 * scale) {
                    if progress.done >= progress.required && progress.required > 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12 * scale))
                            .foregroundColor(Color(.systemGreen))
                    }
                    Text("\(progress.done) / \(progress.required) \(streak.periodCaption)")
                        .font(.system(size: 12 * scale, weight: .semibold))
                        .foregroundColor(
                            progress.done >= progress.required && progress.required > 0
                                ? Color(.systemGreen)
                                : textColor.opacity(0.75)
                        )
                }
            }

            HStack(spacing: 8 * scale) {
                controlArea

                Button {
                    showDayNote = true
                } label: {
                    Image(systemName: hasDayNote ? "note.text" : "square.and.pencil")
                        .font(.system(size: 16 * scale))
                        .foregroundColor(hasDayNote ? .orange : textColor)
                        .padding(8 * scale)
                        .background(textColor.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasDayNote ? "Edit this day's note" : "Add a note for this day")

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
        .opacity(isInactiveDay ? 0.5 : 1)
        .saturation(isInactiveDay ? 0.3 : 1)
        .sheet(isPresented: $showCardSettings) {
            StreakCardSettingsSheet(streakID: streak.id, store: store)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showDayNote) {
            DayNotesSheet(streakID: streak.id, date: displayDate, store: store)
        }
    }

    /// The completion control for the selected date, by streak type.
    @ViewBuilder
    private var controlArea: some View {
        if isInactiveDay {
            HStack(spacing: 6 * scale) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 13 * scale))
                Text("Rest day — scheduled \(streak.scheduledWeekdaysDescription)")
                    .font(.system(size: 12 * scale, weight: .medium))
                    .lineLimit(2)
            }
            .foregroundColor(textColor.opacity(0.7))
            .frame(maxWidth: .infinity, minHeight: 36 * scale)
            .background(Color(.systemGray3).opacity(0.2))
            .clipShape(Capsule())
        } else {
            switch streak.type {
            case .multipleDaily:
                CountControl(
                    count: streak.count(on: displayDate),
                    target: streak.dailyTarget,
                    scale: scale,
                    textColor: textColor,
                    onIncrement: { store.incrementCount(for: displayDate, on: streak) },
                    onDecrement: { store.decrementCount(for: displayDate, on: streak) }
                )
            case .daily, .weekly, .monthly:
                StatusSegmentedControl(
                    current: statusForDisplay,
                    scale: scale
                ) { status in
                    store.setStatus(status, for: displayDate, on: streak)
                }
            }
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
