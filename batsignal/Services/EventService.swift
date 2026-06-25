import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

class EventService: ObservableObject {
    private let db = Firestore.firestore()

    // MARK: - Fetch

    func listenToFriendEvents(
        friendIds: [String],
        onActive: @escaping ([Event]) -> Void,
        onUpcoming: @escaping ([Event]) -> Void
    ) -> ListenerRegistration? {
        guard !friendIds.isEmpty else {
            onActive([]); onUpcoming([])
            return nil
        }
        return db.collection("events")
            .whereField("creatorId", in: friendIds)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("listenToFriendEvents error: \(error.localizedDescription)")
                    return
                }
                let all = snapshot?.documents.compactMap { try? $0.data(as: Event.self) } ?? []
                let now = Date()
                let active = all
                    .filter { $0.isActive && !$0.isExpired }
                    .sorted { $0.startTime.dateValue() < $1.startTime.dateValue() }
                let upcoming = all
                    .filter { !$0.isActive && !$0.isExpired }
                    .sorted { $0.startTime.dateValue() < $1.startTime.dateValue() }
                onActive(active)
                onUpcoming(upcoming)
            }
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
        let ref = try db.collection("events").addDocument(from: event)
        if let uid = Auth.auth().currentUser?.uid {
            try await db.collection("users").document(uid).updateData([
                "activeEventId": ref.documentID
            ])
        }
    }

    // MARK: - Update

    func cancelEvent(id: String) async throws {
        try await db.collection("events").document(id).delete()
        if let uid = Auth.auth().currentUser?.uid {
            try await db.collection("users").document(uid).updateData([
                "activeEventId": FieldValue.delete()
            ])
        }
    }

    func endEvent(id: String) async throws {
        // Setting endTime = now makes isExpired true, distinguishing a manually ended
        // event from one that is still pending activation by the Cloud Function
        try await db.collection("events").document(id).updateData([
            "isActive": false,
            "endTime": Timestamp(date: Date())
        ])
        if let uid = Auth.auth().currentUser?.uid {
            try await db.collection("users").document(uid).updateData([
                "activeEventId": FieldValue.delete()
            ])
        }
    }

    func updateEvent(
        id: String,
        activity: String,
        description: String?,
        startTime: Timestamp,
        durationMinutes: Int?,
        durationVagueLabel: String?,
        endTime: Timestamp?,
        locationType: LocationType,
        locationLabel: String?,
        locationCoordinate: GeoPoint?,
        isActive: Bool
    ) async throws {
        var data: [String: Any] = [
            "activity": activity,
            "startTime": startTime,
            "locationType": locationType.rawValue,
            "isActive": isActive
        ]
        data["description"]        = description        != nil ? description!        : FieldValue.delete()
        data["durationMinutes"]    = durationMinutes    != nil ? durationMinutes!    : FieldValue.delete()
        data["durationVagueLabel"] = durationVagueLabel != nil ? durationVagueLabel! : FieldValue.delete()
        data["endTime"]            = endTime            != nil ? endTime!            : FieldValue.delete()
        data["locationLabel"]      = locationLabel      != nil ? locationLabel!      : FieldValue.delete()
        data["locationCoordinate"] = locationCoordinate != nil ? locationCoordinate! : FieldValue.delete()
        try await db.collection("events").document(id).updateData(data)
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
