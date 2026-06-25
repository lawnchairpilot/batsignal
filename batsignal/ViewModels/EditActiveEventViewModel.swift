import Foundation
import Combine
import FirebaseFirestore
import CoreLocation

@MainActor
class EditActiveEventViewModel: ObservableObject {
    let eventId: String
    private let originalStartTime: Timestamp

    @Published var activity: String
    @Published var description: String
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
        self.originalStartTime = event.startTime
        self.activity = event.activity
        self.description = event.description ?? ""
        self.locationType = event.locationType
        self.locationLabel = event.locationLabel ?? ""

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

    var durationLabel: String {
        if let minutes = selectedDurationMinutes {
            return Event.durationOptions.first { $0.minutes == minutes }?.label ?? ""
        }
        return selectedVagueLabel ?? ""
    }

    func save() async {
        guard !eventId.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        let endTime: Timestamp? = selectedDurationMinutes.map { minutes in
            Timestamp(date: originalStartTime.dateValue().addingTimeInterval(Double(minutes) * 60))
        }

        var coordinate: GeoPoint? = nil
        if locationType == .fixed, let fixed = fixedCoordinate {
            coordinate = GeoPoint(latitude: fixed.latitude, longitude: fixed.longitude)
        }

        do {
            try await eventService.updateEvent(
                id: eventId,
                activity: activity,
                description: description.isEmpty ? nil : description,
                startTime: originalStartTime,
                durationMinutes: selectedDurationMinutes,
                durationVagueLabel: selectedVagueLabel,
                endTime: endTime,
                locationType: locationType,
                locationLabel: locationLabel.isEmpty ? nil : locationLabel,
                locationCoordinate: coordinate,
                isActive: true
            )
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}