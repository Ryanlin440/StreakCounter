//
//  DayNotesSheet.swift
//  StreakCounter
//

import SwiftUI

/// Editor for the note attached to one specific day of a streak.
/// These are separate from the streak-level notes edited in card settings.
struct DayNotesSheet: View {

    let streakID: UUID
    let date: Date
    @ObservedObject var store: StreakStore
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""

    private var streak: Streak? {
        store.streaks.first { $0.id == streakID }
    }

    private var hasExistingNote: Bool {
        guard let streak else { return false }
        return streak.note(on: date)?.isEmpty == false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened this day?", text: $text, axis: .vertical)
                        .lineLimit(3...10)
                } header: {
                    if let streak {
                        Text(streak.name)
                    }
                } footer: {
                    Text("This note is attached to this specific day, separate from the streak's own notes.")
                }

                if hasExistingNote {
                    Section {
                        Button("Delete Note", role: .destructive) {
                            if let streak {
                                store.setDayNote("", for: date, on: streak)
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let streak {
                            store.setDayNote(text, for: date, on: streak)
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            text = streak?.note(on: date) ?? ""
        }
    }
}
