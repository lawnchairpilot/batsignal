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
    // Both names are stamped on at send time, the way a Comment carries its
    // author's. Neither party can read the other's profile document before
    // they're friends, and looking them up means a round trip to a Cloud
    // Function — which is a lot of machinery for a label the sender already had
    // on screen when they tapped Add. Missing on requests sent before these
    // existed, which fall back to the lookup.
    var fromUserName: String?
    var toUserName: String?
    var status: FriendRequestStatus
    var createdAt: Timestamp
}
