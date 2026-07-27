import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

class GroupService: ObservableObject {
    private let db = Firestore.firestore()

    func fetchGroups(ownerId: String) async throws -> [FriendGroup] {
        let snapshot = try await db.collection("groups")
            .whereField("ownerId", isEqualTo: ownerId)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FriendGroup.self) }
    }

    func listenToGroups(ownerId: String, onChange: @escaping ([FriendGroup]) -> Void) -> ListenerRegistration? {
        db.collection("groups")
            .whereField("ownerId", isEqualTo: ownerId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("listenToGroups error: \(error.localizedDescription)")
                    return
                }
                let groups = (snapshot?.documents.compactMap { try? $0.data(as: FriendGroup.self) } ?? [])
                    .sorted { $0.createdAt.dateValue() < $1.createdAt.dateValue() }
                onChange(groups)
            }
    }

    func createGroup(name: String, emoji: String?, memberIds: [String]) async throws {
        guard let ownerId = Auth.auth().currentUser?.uid else { return }
        let group = FriendGroup(ownerId: ownerId, name: name, emoji: emoji, memberIds: memberIds, createdAt: .init())
        _ = try db.collection("groups").addDocument(from: group)
    }

    func updateGroup(id: String, name: String, emoji: String?, memberIds: [String]) async throws {
        var data: [String: Any] = [
            "name": name,
            "memberIds": memberIds
        ]
        data["emoji"] = emoji != nil ? emoji! : FieldValue.delete()
        try await db.collection("groups").document(id).updateData(data)
    }

    func deleteGroup(id: String) async throws {
        try await db.collection("groups").document(id).delete()
    }
}
