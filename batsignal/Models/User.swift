import Foundation
import FirebaseFirestore

struct User: Identifiable, Codable {
    @DocumentID var id: String?
    var phoneNumber: String
    var displayName: String
    var profilePhotoURL: String?
    var friends: [String]
    var maxEventRadius: Double?  // miles, nil = no filter
    var activeEventId: String?   // set when user has an active event
    var fcmToken: String?
    var createdAt: Timestamp
    // Nil for accounts made before the community rules existed, which is what
    // sends them through the agreement gate on next launch.
    var acceptedTermsAt: Timestamp?

    enum CodingKeys: String, CodingKey {
        case id
        case phoneNumber
        case displayName
        case profilePhotoURL
        case friends
        case maxEventRadius
        case activeEventId
        case fcmToken
        case createdAt
        case acceptedTermsAt
    }

    // Up to two letters, for avatars with no photo to show.
    var initials: String? { PublicProfile.initials(from: displayName) }
}
