import Foundation
import FirebaseFirestore
import CoreLocation

enum LocationType: String, Codable {
    case text
    case fixed
    case live
}

// Defaults to [] when the key is missing, so events written before recipientIds
// existed still decode instead of silently vanishing (and leaving activeEventId stuck).
@propertyWrapper
struct DefaultEmptyStringArray: Codable {
    var wrappedValue: [String]

    init(wrappedValue: [String] = []) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        wrappedValue = (try? [String](from: decoder)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}

extension KeyedDecodingContainer {
    func decode(_ type: DefaultEmptyStringArray.Type, forKey key: Key) throws -> DefaultEmptyStringArray {
        try decodeIfPresent(type, forKey: key) ?? DefaultEmptyStringArray()
    }
}

struct Event: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var activity: String
    var emoji: String?
    var description: String?
    var startTime: Timestamp
    var durationMinutes: Int?           // nil if vague (e.g. "til dark")
    var durationVagueLabel: String?     // set only when durationMinutes is nil
    var endTime: Timestamp?             // computed from startTime + durationMinutes, or 9 PM start date if vague
    var locationType: LocationType
    var locationLabel: String?          // text description or place name
    var locationCoordinate: GeoPoint?   // fixed coordinate or live-updated
    var isActive: Bool
    var createdAt: Timestamp
    @DefaultEmptyStringArray var recipientIds: [String]
    var joinedUserIds: [String]?
    var commentsEnabled: Bool?
    var imageURL: String?
    // True when recipientIds was populated from "all my friends" rather than a
    // specific group selection. Drives whether a newly-added friend gets
    // backfilled into recipientIds after the fact (see functions/src/index.ts,
    // backfillEventsOnFriendAccept) — a group-scoped event shouldn't gain
    // recipients the creator deliberately excluded. Missing on older documents
    // defaults to true, since every event predates the group-scoping feature.
    var audienceIsAllFriends: Bool?

    init(
        id: String? = nil,
        creatorId: String,
        activity: String,
        emoji: String?,
        description: String?,
        startTime: Timestamp,
        durationMinutes: Int?,
        durationVagueLabel: String?,
        endTime: Timestamp?,
        locationType: LocationType,
        locationLabel: String?,
        locationCoordinate: GeoPoint?,
        isActive: Bool,
        createdAt: Timestamp,
        recipientIds: [String],
        joinedUserIds: [String]? = nil,
        commentsEnabled: Bool? = nil,
        imageURL: String? = nil,
        audienceIsAllFriends: Bool = true
    ) {
        self.id = id
        self.creatorId = creatorId
        self.activity = activity
        self.emoji = emoji
        self.description = description
        self.startTime = startTime
        self.durationMinutes = durationMinutes
        self.durationVagueLabel = durationVagueLabel
        self.endTime = endTime
        self.locationType = locationType
        self.locationLabel = locationLabel
        self.locationCoordinate = locationCoordinate
        self.isActive = isActive
        self.createdAt = createdAt
        self.recipientIds = recipientIds
        self.joinedUserIds = joinedUserIds
        self.commentsEnabled = commentsEnabled
        self.imageURL = imageURL
        self.audienceIsAllFriends = audienceIsAllFriends
    }

    // MARK: - Duration display

    static let durationOptions: [(minutes: Int, label: String)] = [
        (30,  "30 min"),
        (60,  "1 hour"),
        (90,  "1.5 hours"),
        (120, "2 hours"),
        (180, "3 hours"),
        (240, "4 hours"),
        (360, "6 hours"),
        (480, "8 hours"),
    ]

    static let vagueOptions: [String] = ["til dark", "all day"]

    // Exact durations add minutes to startTime; vague durations always end at 9 PM on the start date.
    static func computeEndTime(startTime: Date, durationMinutes: Int?, vagueLabel: String?) -> Timestamp? {
        if let minutes = durationMinutes {
            return Timestamp(date: startTime.addingTimeInterval(Double(minutes) * 60))
        }
        if vagueLabel != nil {
            let nine = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: startTime) ?? startTime
            return Timestamp(date: nine)
        }
        return nil
    }

    var durationLabel: String {
        if let minutes = durationMinutes {
            return Self.durationOptions.first { $0.minutes == minutes }?.label ?? "\(minutes) min"
        }
        return durationVagueLabel ?? ""
    }

    // MARK: - Progress

    var progress: Double? {
        guard let durationMinutes, let endTime else { return nil }
        let total = Double(durationMinutes) * 60
        let elapsed = Date().timeIntervalSince(startTime.dateValue())
        return min(max(elapsed / total, 0), 1)
    }

    var timeRemainingLabel: String? {
        guard let endTime else { return nil }
        let remaining = endTime.dateValue().timeIntervalSince(Date())
        guard remaining > 0 else { return "Ending..." }
        let minutes = Int(remaining) / 60
        let hours = minutes / 60
        if hours > 0 {
            let mins = minutes % 60
            return mins > 0 ? "\(hours)h \(mins)m left" : "\(hours)h left"
        }
        return "\(minutes)m left"
    }

    // MARK: - Expiry (client-side for MVP)

    var isExpired: Bool {
        guard let endTime else { return false }
        return endTime.dateValue() < Date()
    }

    var isVisible: Bool {
        isActive && !isExpired
    }

    // Missing field on older documents defaults to enabled
    var commentsAllowed: Bool {
        commentsEnabled ?? true
    }
}
