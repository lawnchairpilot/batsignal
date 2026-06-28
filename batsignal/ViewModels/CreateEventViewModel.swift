import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth
import CoreLocation

enum DayOption: String, CaseIterable {
    case today = "Today"
    case tomorrow = "Tomorrow"
}

@MainActor
class CreateEventViewModel: ObservableObject {
    @Published var activity = ""
    @Published var emoji: String? = nil
    @Published var description = ""
    @Published var selectedDay: DayOption = .today
    @Published var selectedTime: Date = Date()
    @Published var selectedDurationMinutes: Int? = 60
    @Published var selectedVagueLabel: String? = nil
    @Published var locationType: LocationType = .text
    @Published var locationLabel = ""
    @Published var fixedCoordinate: CLLocationCoordinate2D? = nil  // set by map picker
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var didCreate = false

    private let eventService = EventService()
    private let locationService = LocationService()

    var startTime: Date {
        let calendar = Calendar.current
        let base = selectedDay == .today ? Date() : calendar.date(byAdding: .day, value: 1, to: Date())!
        let components = calendar.dateComponents([.hour, .minute], from: selectedTime)
        return calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: 0,
            of: base
        ) ?? base
    }

    var durationLabel: String {
        if let minutes = selectedDurationMinutes {
            return Event.durationOptions.first { $0.minutes == minutes }?.label ?? ""
        }
        return selectedVagueLabel ?? ""
    }

    func submit() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Allow up to 5 min in the past to account for time spent filling the form
        guard startTime > Date().addingTimeInterval(-5 * 60) else {
            errorMessage = "Start time cannot be in the past."
            return
        }
        isLoading = true
        errorMessage = nil

        let endTime: Timestamp? = selectedDurationMinutes.map { minutes in
            Timestamp(date: startTime.addingTimeInterval(Double(minutes) * 60))
        }

        var coordinate: GeoPoint? = nil
        if locationType == .fixed, let fixed = fixedCoordinate {
            coordinate = GeoPoint(latitude: fixed.latitude, longitude: fixed.longitude)
        }
        // For .live events, coordinate is nil at creation time — LocationService writes
        // the first coordinate to Firestore shortly after the event becomes active.

        // Active immediately if starting now (within 1 min), otherwise Cloud Function activates it
        let isActive = startTime <= Date().addingTimeInterval(60)

        let event = Event(
            creatorId: uid,
            activity: activity,
            emoji: emoji,
            description: description.isEmpty ? nil : description,
            startTime: Timestamp(date: startTime),
            durationMinutes: selectedDurationMinutes,
            durationVagueLabel: selectedVagueLabel,
            endTime: endTime,
            locationType: locationType,
            locationLabel: locationLabel.isEmpty ? nil : locationLabel,
            locationCoordinate: coordinate,
            isActive: isActive,
            createdAt: .init()
        )

        do {
            try await eventService.createEvent(event)
            didCreate = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
