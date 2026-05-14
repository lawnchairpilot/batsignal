import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

class EventService: ObservableObject {
    private let db = Firestore.firestore()

    // MARK: - Fetch

    func fetchFriendEvents(friendIds: [String]) async throws -> [Event] {
        guard !friendIds.isEmpty else { return [] }
        let snapshot = try await db.collection("events")
            .whereField("creatorId", in: friendIds)
            .whereField("isActive", isEqualTo: true)
            .order(by: "startTime", descending: false)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Event.self) }
    }

    func fetchMyEvents() async throws -> [Event] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        let snapshot = try await db.collection("events")
            .whereField("creatorId", isEqualTo: uid)
            .order(by: "startTime", descending: true)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Event.self) }
    }

    func listenToMyActiveEvent(onChange: @escaping (Event?) -> Void) -> ListenerRegistration? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return db.collection("events")
            .whereField("creatorId", isEqualTo: uid)
            .whereField("isActive", isEqualTo: true)
            .limit(to: 1)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("listenToMyActiveEvent error: \(error.localizedDescription)")
                    return
                }
                let event = snapshot?.documents.compactMap { try? $0.data(as: Event.self) }.first
                onChange(event?.isExpired == false ? event : nil)
            }
    }

    // MARK: - Create

    func createEvent(_ event: Event) async throws {
        _ = try db.collection("events").addDocument(from: event)
    }

    // MARK: - Update

    func endEvent(id: String) async throws {
        try await db.collection("events").document(id).updateData(["isActive": false])
    }

    func extendEvent(id: String, currentEndTime: Date, currentDurationMinutes: Int) async throws {
        let newDuration = currentDurationMinutes + 30
        let newEndTime = currentEndTime.addingTimeInterval(30 * 60)
        try await db.collection("events").document(id).updateData([
            "durationMinutes": newDuration,
            "endTime": Timestamp(date: newEndTime)
        ])
    }

    func updateLiveLocation(eventId: String, coordinate: GeoPoint) async throws {
        try await db.collection("events").document(eventId).updateData([
            "locationCoordinate": coordinate
        ])
    }

    // MARK: - Real-time listener

    func listenToEvent(id: String, onChange: @escaping (Event?) -> Void) -> ListenerRegistration {
        db.collection("events").document(id).addSnapshotListener { snapshot, _ in
            onChange(try? snapshot?.data(as: Event.self))
        }
    }
}
