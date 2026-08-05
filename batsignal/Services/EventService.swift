import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

class EventService: ObservableObject {
    private let db = Firestore.firestore()

    // MARK: - Fetch

    func listenToVisibleEvents(
        userId: String,
        onActive: @escaping ([Event]) -> Void,
        onUpcoming: @escaping ([Event]) -> Void
    ) -> ListenerRegistration? {
        guard !userId.isEmpty else {
            onActive([]); onUpcoming([])
            return nil
        }
        return db.collection("events")
            .whereField("recipientIds", arrayContains: userId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("listenToVisibleEvents error: \(error.localizedDescription)")
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
        // Batched so the event doc and the user's activeEventId pointer either both
        // land or neither does — a partial failure here used to leave activeEventId
        // stuck (or unset) with no way to recover short of a manual data fix.
        let ref = db.collection("events").document()
        let batch = db.batch()
        try batch.setData(from: event, forDocument: ref)
        if let uid = Auth.auth().currentUser?.uid {
            batch.updateData(["activeEventId": ref.documentID], forDocument: db.collection("users").document(uid))
        }
        try await batch.commit()
    }

    // MARK: - Update

    func cancelEvent(id: String) async throws {
        let batch = db.batch()
        batch.deleteDocument(db.collection("events").document(id))
        if let uid = Auth.auth().currentUser?.uid {
            batch.updateData(["activeEventId": FieldValue.delete()], forDocument: db.collection("users").document(uid))
        }
        try await batch.commit()
    }

    func endEvent(id: String) async throws {
        // Setting endTime = now makes isExpired true, distinguishing a manually ended
        // event from one that is still pending activation by the Cloud Function
        let batch = db.batch()
        batch.updateData([
            "isActive": false,
            "endTime": Timestamp(date: Date())
        ], forDocument: db.collection("events").document(id))
        if let uid = Auth.auth().currentUser?.uid {
            batch.updateData(["activeEventId": FieldValue.delete()], forDocument: db.collection("users").document(uid))
        }
        try await batch.commit()
    }

    // Detaches a stale activeEventId pointer when the event it refers to is already
    // terminal (or failed to decode) so it can't keep blocking new event creation.
    func clearActiveEventId() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("users").document(uid).updateData([
            "activeEventId": FieldValue.delete()
        ])
    }

    func updateEvent(
        id: String,
        activity: String,
        emoji: String?,
        description: String?,
        startTime: Timestamp,
        durationMinutes: Int?,
        durationVagueLabel: String?,
        endTime: Timestamp?,
        locationType: LocationType,
        locationLabel: String?,
        locationCoordinate: GeoPoint?,
        isActive: Bool,
        commentsEnabled: Bool,
        imageURL: String?
    ) async throws {
        var data: [String: Any] = [
            "activity": activity,
            "startTime": startTime,
            "locationType": locationType.rawValue,
            "isActive": isActive,
            "commentsEnabled": commentsEnabled
        ]
        data["emoji"]              = emoji              != nil ? emoji!              : FieldValue.delete()
        data["description"]        = description        != nil ? description!        : FieldValue.delete()
        data["durationMinutes"]    = durationMinutes    != nil ? durationMinutes!    : FieldValue.delete()
        data["durationVagueLabel"] = durationVagueLabel != nil ? durationVagueLabel! : FieldValue.delete()
        data["endTime"]            = endTime            != nil ? endTime!            : FieldValue.delete()
        data["locationLabel"]      = locationLabel      != nil ? locationLabel!      : FieldValue.delete()
        data["locationCoordinate"] = locationCoordinate != nil ? locationCoordinate! : FieldValue.delete()
        data["imageURL"]           = imageURL           != nil ? imageURL!           : FieldValue.delete()
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

    func joinEvent(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("events").document(id).updateData([
            "joinedUserIds": FieldValue.arrayUnion([uid])
        ])
    }

    func leaveEvent(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("events").document(id).updateData([
            "joinedUserIds": FieldValue.arrayRemove([uid])
        ])
    }

    // MARK: - Real-time listener

    func listenToEvent(id: String, onChange: @escaping (Event?) -> Void) -> ListenerRegistration {
        db.collection("events").document(id).addSnapshotListener { snapshot, _ in
            onChange(try? snapshot?.data(as: Event.self))
        }
    }

    // MARK: - Comments

    func postComment(eventId: String, text: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Comment.characterLimit))
        guard !trimmed.isEmpty else { return }

        let comment = Comment(
            authorId: uid,
            authorName: AuthService.shared.currentUser?.displayName ?? "",
            authorPhotoURL: AuthService.shared.currentUser?.profilePhotoURL,
            text: trimmed,
            createdAt: Timestamp(date: Date())
        )
        _ = try db.collection("events").document(eventId).collection("comments").addDocument(from: comment)
    }

    func listenToComments(eventId: String, onChange: @escaping ([Comment]) -> Void) -> ListenerRegistration {
        db.collection("events").document(eventId).collection("comments")
            .order(by: "createdAt")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("listenToComments error: \(error.localizedDescription)")
                    return
                }
                onChange(snapshot?.documents.compactMap { try? $0.data(as: Comment.self) } ?? [])
            }
    }
}
