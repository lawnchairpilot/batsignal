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
    var createdAt: Timestamp

    enum CodingKeys: String, CodingKey {
        case id
        case phoneNumber
        case displayName
        case profilePhotoURL
        case friends
        case maxEventRadius
        case activeEventId
        case createdAt
    }
}
