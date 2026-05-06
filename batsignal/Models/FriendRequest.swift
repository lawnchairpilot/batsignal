import Foundation
import FirebaseFirestore

enum FriendRequestStatus: String, Codable {
    case pending
    case accepted
    case declined
}

struct FriendRequest: Identifiable, Codable {
    @DocumentID var id: String?
    var fromUserId: String
    var toUserId: String
    var status: FriendRequestStatus
    var createdAt: Timestamp
}
