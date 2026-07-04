//
//  MilestoneMessageSheets.swift
//  StreakCounter
//

import SwiftUI
import MessageUI

struct AddMilestoneMessageSheet: View {

    let streak: Streak
    @ObservedObject var store: StreakStore
    @Environment(\.dismiss) private var dismiss

    @State private var targetDays: Int = 100
    @State private var message: String = ""

    private let presets = [7, 14, 30, 50, 100, 200, 365, 500, 1000]

    var body: some View {
        NavigationStack {
            Form {
                Section("Milestone") {
                    Stepper(value: $targetDays, in: 1...10000) {
                        Text("\(targetDays) day\(targetDays == 1 ? "" : "s")")
                            .font(.body.weight(.medium))
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets, id: \.self) { p in
                                Button("\(p)") {
                                    targetDays = p
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(targetDays == p ? .accentColor : .gray)
                            }
                        }
                    }
                }

                Section {
                    TextField(
                        "What do you want your future self to read?",
                        text: $message,
                        axis: .vertical
                    )
                    .lineLimit(4...12)
                } header: {
                    Text("Message")
                } footer: {
                    Text("The message stays locked until you reach \(targetDays) days. Once unlocked, you can email it to yourself.")
                }
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        store.addMilestoneMessage(
                            targetDays: targetDays,
                            message: message,
                            for: streak
                        )
                        dismiss()
                    }
                    .bold()
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct MilestoneMessageDetailSheet: View {

    let message: MilestoneMessage
    let streakName: String
    @EnvironmentObject private var auth: AuthService

    @Environment(\.dismiss) private var dismiss

    @State private var showMailComposer = false
    @State private var showMailUnavailableAlert = false
    @State private var showGuestEmailPrompt = false
    @State private var guestEmailDraft = ""

    private var recipientEmail: String? {
        auth.effectiveEmail
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: message.isUnlocked ? "envelope.open.fill" : "lock.fill")
                            .font(.title2)
                            .foregroundColor(message.isUnlocked ? .orange : .gray)
                        VStack(alignment: .leading) {
                            Text("Day \(message.targetDays)")
                                .font(.title2.weight(.bold))
                            Text(headerSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    if message.isUnlocked {
                        Text(message.message)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let email = recipientEmail, !email.isEmpty {
                            Button {
                                presentMailComposer()
                            } label: {
                                Label("Send to \(email)", systemImage: "paperplane.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .padding(.top, 8)
                        } else if auth.isGuest {
                            Button {
                                guestEmailDraft = auth.guestEmail
                                showGuestEmailPrompt = true
                            } label: {
                                Label("Email this message", systemImage: "paperplane.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .padding(.top, 8)
                        } else {
                            Text("Sign in or continue as guest to email this message to your future self.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                    } else {
                        Text("Keep going — this message unlocks when you reach \(message.targetDays) days.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle(message.isUnlocked ? "🎉 Unlocked" : "Locked")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .bold()
                }
            }
            .sheet(isPresented: $showMailComposer) {
                if let email = recipientEmail {
                    MailComposeView(
                        recipient: email,
                        subject: emailSubject,
                        body: emailBody
                    )
                }
            }
            .alert("Mail not available", isPresented: $showMailUnavailableAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Set up the Mail app on this device to send your milestone message.")
            }
            .alert("Where should we send it?", isPresented: $showGuestEmailPrompt) {
                TextField("you@example.com", text: $guestEmailDraft)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Cancel", role: .cancel) { }
                Button("Send") {
                    let trimmed = guestEmailDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    auth.setGuestEmail(trimmed)
                    presentMailComposer()
                }
            } message: {
                Text("Enter the email address to send this milestone message to.")
            }
        }
    }

    private func presentMailComposer() {
        if MFMailComposeViewController.canSendMail() {
            showMailComposer = true
        } else {
            showMailUnavailableAlert = true
        }
    }

    private var headerSubtitle: String {
        if let unlocked = message.unlockedAt {
            return "Unlocked \(unlocked.formatted(date: .abbreviated, time: .omitted))"
        } else {
            return "Written \(message.createdAt.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    private var emailSubject: String {
        let label = streakName.isEmpty ? "your streak" : streakName
        return "🎉 Day \(message.targetDays) of \(label) — a note from your past self"
    }

    private var emailBody: String {
        let written = message.createdAt.formatted(date: .long, time: .omitted)
        let label = streakName.isEmpty ? "your streak" : streakName
        return """
        You did it — \(message.targetDays) days of \(label)!

        Here's the note you left for your future self on \(written):

        \(message.message)

        — Sent from StreakCounter
        """
    }
}

// MARK: - Mail compose wrapper

struct MailComposeView: UIViewControllerRepresentable {

    let recipient: String
    let subject: String
    let body: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) { }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
        }
    }
}
