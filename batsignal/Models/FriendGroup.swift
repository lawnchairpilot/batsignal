import Foundation
import FirebaseFirestore

struct FriendGroup: Identifiable, Codable {
    @DocumentID var id: String?
    var ownerId: String
    var name: String
    var emoji: String?
    var memberIds: [String]
    var createdAt: Timestamp
}
