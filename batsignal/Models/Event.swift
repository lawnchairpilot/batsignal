import Foundation
import FirebaseFirestore
import CoreLocation

enum LocationType: String, Codable {
    case text
    case fixed
    case live
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

    // MARK: - Expiry (client-side for MVP)

    var isExpired: Bool {
        guard let endTime else { return false }
        return endTime.dateValue() < Date()
    }

    var isVisible: Bool {
        isActive && !isExpired
    }
}
