import Foundation
import FirebaseFirestore

struct Comment: Identifiable, Codable {
    @DocumentID var id: String?
    var authorId: String
    var authorName: String
    var authorPhotoURL: String?
    var text: String
    var createdAt: Timestamp

    static let characterLimit = 140
}
