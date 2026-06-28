import Foundation
import Combine
import FirebaseFirestore
import CoreLocation

@MainActor
class EditUpcomingEventViewModel: ObservableObject {
    let eventId: String

    @Published var activity: String
    @Published var emoji: String?
    @Published var description: String
    @Published var selectedDay: DayOption
    @Published var selectedTime: Date
    @Published var selectedDurationMinutes: Int?
    @Published var selectedVagueLabel: String?
    @Published var locationType: LocationType
    @Published var locationLabel: String
    @Published var fixedCoordinate: CLLocationCoordinate2D?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var didSave = false

    private let eventService = EventService()

    init(event: Event) {
        self.eventId = event.id ?? ""
        self.activity = event.activity
        self.emoji = event.emoji
        self.description = event.description ?? ""
        self.locationType = event.locationType
        self.locationLabel = event.locationLabel ?? ""

        let startDate = event.startTime.dateValue()
        self.selectedDay = Calendar.current.isDateInTomorrow(startDate) ? .tomorrow : .today
        self.selectedTime = startDate

        if let minutes = event.durationMinutes {
            self.selectedDurationMinutes = minutes
            self.selectedVagueLabel = nil
        } else {
            self.selectedDurationMinutes = nil
            self.selectedVagueLabel = event.durationVagueLabel
        }

        if let coord = event.locationCoordinate {
            self.fixedCoordinate = CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
        }
    }

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

    func save() async {
        guard !eventId.isEmpty else { return }
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

        let isActive = startTime <= Date().addingTimeInterval(60)

        do {
            try await eventService.updateEvent(
                id: eventId,
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
                isActive: isActive
            )
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}