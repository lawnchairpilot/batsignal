import Foundation
import Combine
import CoreLocation
import FirebaseFirestore

@MainActor
class HomeViewModel: ObservableObject {
    @Published var events: [Event] = []
    @Published var upcomingEvents: [Event] = []
    @Published var isLoading = false

    private let eventService = EventService()
    private let locationService = LocationService()
    private var listener: ListenerRegistration?
    // Everything the query returned, expired events and all. What's published
    // is derived from this, so the derivation can be redone as time passes
    // without waiting on the server to say anything new.
    private var allEvents: [Event] = []
    private var maxRadius: Double?
    private var expiryTicker: Task<Void, Never>?

    func startListening(userId: String, maxRadius: Double?) {
        listener?.remove()
        self.maxRadius = maxRadius
        isLoading = true
        listener = eventService.listenToVisibleEvents(userId: userId) { [weak self] fetched in
            Task { @MainActor in
                guard let self else { return }
                self.allEvents = fetched
                self.isLoading = false
                self.refreshVisibleEvents()
            }
        }
        startExpiryTicker()
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        expiryTicker?.cancel()
        expiryTicker = nil
    }

    // For the app coming back to the foreground: the ticker is throttled while
    // backgrounded, and returning to a map still showing events that finished
    // an hour ago is exactly the case this is all for.
    func refreshNow() {
        refreshVisibleEvents()
    }

    // An event ending writes nothing to Firestore — the creator's device does
    // it if their app happens to be running, and otherwise no one does — so
    // there's no snapshot to react to. Re-running the derivation on a timer is
    // what makes a finished event leave the map.
    private func startExpiryTicker() {
        expiryTicker?.cancel()
        expiryTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                await self?.refreshVisibleEvents()
            }
        }
    }

    private func refreshVisibleEvents() {
        let live = allEvents.filter { !$0.isExpired }
        let byStart = { (lhs: Event, rhs: Event) in
            lhs.startTime.dateValue() < rhs.startTime.dateValue()
        }

        let active = live.filter(\.isActive).sorted(by: byStart)
        let upcoming = live.filter { !$0.isActive }.sorted(by: byStart)

        // Assigning only on a real change keeps the timer from republishing an
        // identical list every 20 seconds and redrawing the map for nothing.
        let filtered = withinRadius(active)
        if filtered.map(\.id) != events.map(\.id) {
            events = filtered
        }
        if upcoming.map(\.id) != upcomingEvents.map(\.id) {
            upcomingEvents = upcoming
        }
    }

    private func withinRadius(_ events: [Event]) -> [Event] {
        guard let maxRadius, locationService.currentLocation != nil else { return events }
        return events.filter { event in
            guard let coord = event.locationCoordinate else { return true }
            guard let distance = locationService.distance(from: coord) else { return true }
            return distance <= maxRadius
        }
    }

    deinit {
        expiryTicker?.cancel()
    }
}
