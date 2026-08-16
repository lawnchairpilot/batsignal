import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

class FriendService: ObservableObject {
    private let db = Firestore.firestore()

    // MARK: - Friend lookup

    func findUser(byPhoneNumber phoneNumber: String) async throws -> PublicProfile? {
        guard let normalized = PhoneNumber.normalize(phoneNumber) else { return nil }
        return try await ProfileLookup.profiles(phoneNumbers: [normalized]).first
    }

    // People this user has no direct read access to: the other party to a friend
    // request, before there's a friendship to grant it, or the people on a
    // signal. Naming the event lets the server check this user was actually
    // sent it before saying who else is there.
    func fetchProfiles(ids: [String], eventId: String? = nil) async throws -> [PublicProfile] {
        try await ProfileLookup.profiles(userIds: ids, eventId: eventId)
    }

    // MARK: - Friend requests

    func sendFriendRequest(toUserId: String) async throws {
        guard let fromUserId = Auth.auth().currentUser?.uid else { return }

        // Check for an existing pending request in either direction
        let existing = try await db.collection("friendRequests")
            .whereField("fromUserId", isEqualTo: fromUserId)
            .whereField("toUserId", isEqualTo: toUserId)
            .whereField("status", isEqualTo: FriendRequestStatus.pending.rawValue)
            .getDocuments()
        guard existing.documents.isEmpty else { return }

        let request = FriendRequest(
            fromUserId: fromUserId,
            toUserId: toUserId,
            status: .pending,
            createdAt: .init()
        )
        _ = try db.collection("friendRequests").addDocument(from: request)
    }

    // The whole user document, which only its owner and their friends can read.
    // For anyone else — a pending request, someone on a signal — use
    // fetchProfiles, or this comes back empty.
    func fetchUser(id: String) async throws -> User? {
        let doc = try await db.collection("users").document(id).getDocument()
        return try? doc.data(as: User.self)
    }

    // Flipping the status is the whole job. The friendship itself is written by
    // linkFriendsOnRequestAccept (functions/src/index.ts), which is the only
    // writer either friends list has — a client can't be trusted to edit
    // someone else's. The new friend appears when the user document listener
    // sees it land, a beat after this returns.
    func respondToRequest(requestId: String, accept: Bool) async throws {
        let status = accept ? FriendRequestStatus.accepted : .declined
        try await db.collection("friendRequests").document(requestId).updateData([
            "status": status.rawValue
        ])
    }

    func listenToIncomingRequests(onChange: @escaping ([FriendRequest]) -> Void) -> ListenerRegistration? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return db.collection("friendRequests")
            .whereField("toUserId", isEqualTo: uid)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("listenToIncomingRequests error: \(error.localizedDescription)")
                    return
                }
                let pending = snapshot?.documents
                    .compactMap { try? $0.data(as: FriendRequest.self) }
                    .filter { $0.status == .pending } ?? []
                onChange(pending)
            }
    }

    func listenToOutgoingRequests(onChange: @escaping ([FriendRequest]) -> Void) -> ListenerRegistration? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return db.collection("friendRequests")
            .whereField("fromUserId", isEqualTo: uid)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("listenToOutgoingRequests error: \(error.localizedDescription)")
                    return
                }
                let pending = snapshot?.documents
                    .compactMap { try? $0.data(as: FriendRequest.self) }
                    .filter { $0.status == .pending } ?? []
                onChange(pending)
            }
    }

    // MARK: - Friends list

    func fetchFriends(ids: [String]) async throws -> [User] {
        guard !ids.isEmpty else { return [] }
        let snapshot = try await db.collection("users")
            .whereField(FieldPath.documentID(), in: ids)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: User.self) }
    }

}
