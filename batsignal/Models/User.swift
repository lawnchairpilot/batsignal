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
    }

    // Up to two letters, for avatars with no photo to show.
    var initials: String? {
        guard !displayName.isEmpty else { return nil }
        let letters = displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? nil : letters.uppercased()
    }
}
