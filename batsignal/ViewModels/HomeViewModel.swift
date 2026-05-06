import Foundation
import Combine
import CoreLocation

@MainActor
class HomeViewModel: ObservableObject {
    @Published var events: [Event] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let eventService = EventService()
    private let locationService = LocationService()

    func loadEvents(friendIds: [String], maxRadius: Double?) async {
        isLoading = true
        errorMessage = nil
        do {
            var fetched = try await eventService.fetchFriendEvents(friendIds: friendIds)
            fetched = fetched.filter { $0.isVisible }

            if let maxRadius, locationService.currentLocation != nil {
                fetched = fetched.filter { event in
                    guard let coord = event.locationCoordinate else { return true }
                    guard let dist = locationService.distance(from: coord) else { return true }
                    return dist <= maxRadius
                }
            }

            events = fetched
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
