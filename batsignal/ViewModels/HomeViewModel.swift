import Foundation
import Combine
import CoreLocation
import FirebaseFirestore

@MainActor
class HomeViewModel: ObservableObject {
    @Published var events: [Event] = []
    @Published var isLoading = false

    private let eventService = EventService()
    private let locationService = LocationService()
    private var listener: ListenerRegistration?

    func startListening(friendIds: [String], maxRadius: Double?) {
        listener?.remove()
        isLoading = true
        listener = eventService.listenToFriendEvents(friendIds: friendIds) { [weak self] fetched in
            guard let self else { return }
            if let maxRadius, self.locationService.currentLocation != nil {
                self.events = fetched.filter { event in
                    guard let coord = event.locationCoordinate else { return true }
                    guard let dist = self.locationService.distance(from: coord) else { return true }
                    return dist <= maxRadius
                }
            } else {
                self.events = fetched
            }
            self.isLoading = false
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }
}
