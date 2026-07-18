//
//  FirestoreSync.swift
//  StreakCounter
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Snapshot of the user-facing state we sync across devices.
/// We keep it as a single per-user document so writes are atomic and
/// the snapshot listener fires for any change.
struct StreakStoreSnapshot: Codable {
    var streaks: [Streak]
    var cardSize: Double
    var backgroundColor: CodableColor
    /// Optional so documents written before reminder syncing still decode.
    var reminderTimes: [ReminderTime]?
}

@MainActor
final class FirestoreSync {

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private weak var store: StreakStore?

    /// Set to true while we're applying a remote snapshot so the
    /// store's own setters don't echo the same data back to Firestore.
    fileprivate(set) var isApplyingRemote = false

    init(store: StreakStore) {
        self.store = store
    }

    deinit {
        listener?.remove()
    }

    func start(for uid: String) {
        stop()
        let ref = db.collection("users").document(uid)
        listener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error = error {
                print("FirestoreSync listen error: \(error.localizedDescription)")
                return
            }
            guard let snapshot, snapshot.exists,
                  let data = snapshot.data(),
                  let payload = data["payload"] as? String,
                  let payloadData = payload.data(using: .utf8) else {
                // No remote document yet — push current local state so
                // the other device has something to pull.
                Task { @MainActor in self.pushCurrentState() }
                return
            }
            Task { @MainActor in
                self.applyRemote(payloadData: payloadData)
            }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    func push(snapshot: StreakStoreSnapshot) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard !isApplyingRemote else { return }
        do {
            let json = try JSONEncoder().encode(snapshot)
            guard let payload = String(data: json, encoding: .utf8) else { return }
            db.collection("users").document(uid).setData([
                "payload": payload,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            print("FirestoreSync encode error: \(error.localizedDescription)")
        }
    }

    private func pushCurrentState() {
        guard let store else { return }
        push(snapshot: store.snapshotForSync())
    }

    private func applyRemote(payloadData: Data) {
        guard let store else { return }
        do {
            let snapshot = try JSONDecoder().decode(StreakStoreSnapshot.self, from: payloadData)
            isApplyingRemote = true
            store.applyRemoteSnapshot(snapshot)
            isApplyingRemote = false
        } catch {
            print("FirestoreSync decode error: \(error.localizedDescription)")
        }
    }
}
