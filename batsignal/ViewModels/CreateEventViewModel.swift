import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth
import CoreLocation

@MainActor
class CreateEventViewModel: ObservableObject {
    @Published var activity = ""
    @Published var description = ""
    @Published var startTime = Date()
    @Published var selectedDurationMinutes: Int? = 60
    @Published var selectedVagueLabel: String? = nil
    @Published var locationType: LocationType = .text
    @Published var locationLabel = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var didCreate = false

    private let eventService = EventService()
    private let locationService = LocationService()

    var durationLabel: String {
        if let minutes = selectedDurationMinutes {
            return Event.durationOptions.first { $0.minutes == minutes }?.label ?? ""
        }
        return selectedVagueLabel ?? ""
    }

    func submit() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        errorMessage = nil

        let endTime: Timestamp? = selectedDurationMinutes.map { minutes in
            Timestamp(date: startTime.addingTimeInterval(Double(minutes) * 60))
        }

        var coordinate: GeoPoint? = nil
        if locationType == .live || locationType == .fixed {
            locationService.requestCurrentLocation()
            if let loc = locationService.currentLocation {
                coordinate = GeoPoint(latitude: loc.coordinate.latitude,
                                      longitude: loc.coordinate.longitude)
            }
        }

        let event = Event(
            creatorId: uid,
            activity: activity,
            description: description.isEmpty ? nil : description,
            startTime: Timestamp(date: startTime),
            durationMinutes: selectedDurationMinutes,
            durationVagueLabel: selectedVagueLabel,
            endTime: endTime,
            locationType: locationType,
            locationLabel: locationLabel.isEmpty ? nil : locationLabel,
            locationCoordinate: coordinate,
            isActive: true,
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
