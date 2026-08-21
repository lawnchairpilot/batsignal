import Foundation
import FirebaseFirestore

// What was reported. A comment needs its parent event recorded too, since a
// comment id alone doesn't locate the document.
enum ReportedContentType: String, Codable {
    case comment
    case event
    case user
}

enum ReportReason: String, Codable, CaseIterable, Identifiable {
    case harassment
    case sexualContent
    case violence
    case spam
    case impersonation
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .harassment:     return Strings.Moderation.reasonHarassment
        case .sexualContent:  return Strings.Moderation.reasonSexualContent
        case .violence:       return Strings.Moderation.reasonViolence
        case .spam:           return Strings.Moderation.reasonSpam
        case .impersonation:  return Strings.Moderation.reasonImpersonation
        case .other:          return Strings.Moderation.reasonOther
        }
    }
}

enum ReportStatus: String, Codable {
    case open
    case actioned
    case dismissed
}

struct Report: Identifiable, Codable {
    @DocumentID var id: String?
    var reporterId: String
    var targetType: ReportedContentType
    // The comment, event, or user being reported.
    var targetId: String
    // Set only for comments, which live under an event.
    var eventId: String?
    // Who wrote the reported thing, so a review can act on the account behind it
    // rather than just the one item.
    var authorId: String?
    var reason: ReportReason
    var note: String?
    var status: ReportStatus
    var createdAt: Timestamp

    static let noteCharacterLimit = 300
}
