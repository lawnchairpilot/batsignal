import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

class FriendService: ObservableObject {
    private let db = Firestore.firestore()

    // MARK: - Friend lookup

    func findUser(byPhoneNumber phoneNumber: String) async throws -> User? {
        let snapshot = try await db.collection("users")
            .whereField("phoneNumber", isEqualTo: phoneNumber)
            .limit(to: 1)
            .getDocuments()
        return try snapshot.documents.first?.data(as: User.self)
    }

    // MARK: - Friend requests

    func sendFriendRequest(toUserId: String) async throws {
        guard let fromUserId = Auth.auth().currentUser?.uid else { return }
        let request = FriendRequest(
            fromUserId: fromUserId,
            toUserId: toUserId,
            status: .pending,
            createdAt: .init()
        )
        _ = try db.collection("friendRequests").addDocument(from: request)
    }

    func respondToRequest(requestId: String, accept: Bool) async throws {
        let status = accept ? FriendRequestStatus.accepted : .declined
        try await db.collection("friendRequests").document(requestId).updateData([
            "status": status.rawValue
        ])

        if accept {
            guard let currentUserId = Auth.auth().currentUser?.uid else { return }
            let snapshot = try await db.collection("friendRequests").document(requestId).getDocument()
            let request = try snapshot.data(as: FriendRequest.self)
            try await addMutualFriendship(userId1: currentUserId, userId2: request.fromUserId)
        }
    }

    func fetchIncomingRequests() async throws -> [FriendRequest] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        let snapshot = try await db.collection("friendRequests")
            .whereField("toUserId", isEqualTo: uid)
            .whereField("status", isEqualTo: FriendRequestStatus.pending.rawValue)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FriendRequest.self) }
    }

    // MARK: - Friends list

    func fetchFriends(ids: [String]) async throws -> [User] {
        guard !ids.isEmpty else { return [] }
        let snapshot = try await db.collection("users")
            .whereField(FieldPath.documentID(), in: ids)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: User.self) }
    }

    // MARK: - Private

    private func addMutualFriendship(userId1: String, userId2: String) async throws {
        let batch = db.batch()
        let user1Ref = db.collection("users").document(userId1)
        let user2Ref = db.collection("users").document(userId2)
        batch.updateData(["friends": FieldValue.arrayUnion([userId2])], forDocument: user1Ref)
        batch.updateData(["friends": FieldValue.arrayUnion([userId1])], forDocument: user2Ref)
        try await batch.commit()
    }
}
