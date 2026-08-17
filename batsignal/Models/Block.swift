import Foundation
import FirebaseFirestore

struct Block: Identifiable, Codable {
    @DocumentID var id: String?
    var blockerId: String
    var blockedId: String
    var createdAt: Timestamp

    // Blocks are stored at a derived id rather than a random one so security
    // rules can test for one with exists() — rules can look a document up by
    // path but can't search for it, which is the same limitation that pushed
    // friend linking onto the server.
    static func documentId(blocker: String, blocked: String) -> String {
        "\(blocker)_\(blocked)"
    }
}
