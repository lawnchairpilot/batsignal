import Foundation
import Combine
import CoreLocation
import FirebaseFirestore

class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var liveEventId: String?
    private let eventService = EventService()

    // A live event chases the host with a geofence rather than by tracking them
    // continuously: publish a fix, draw a circle around it, and go quiet until
    // they leave it. Standing still costs nothing — no GPS runs at all — and
    // moving costs one short fix per circle. Continuous background tracking
    // would hold the GPS radio open for the entire event, which for a signal
    // that only means "roughly where I am" is a battery bill nobody would want
    // to pay for hosting.
    // Plain letters only: the name becomes a filename on disk (the conditions
    // outlive the process in ~/Library/CoreLocation/<bundle id>/<name>.monitor),
    // and punctuation in it is rejected as invalid.
    private static let monitorName = "BatsignalLiveEvent"
    private static let conditionIdentifier = "LiveEventArea"
    // Region monitoring gets unreliable well below this; a tighter circle would
    // buy precision the system can't actually promise.
    private static let regionRadius: CLLocationDistance = 200
    // Significant-change monitoring runs alongside the geofence and can report
    // the same position twice, so a fix has to be a real move to be worth a write.
    private static let minPublishDistance: CLLocationDistance = 75

    private var monitor: CLMonitor?
    private var monitorTask: Task<Void, Never>?
    private var lastPublishedLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        // Not kCLLocationAccuracyBest: the extra precision costs seconds of
        // extra GPS time per fix, and nothing here is drawn tightly enough to
        // show the difference.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    // MARK: - Permissions

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    // MARK: - One-shot location (for feed filtering)

    func requestCurrentLocation() {
        manager.requestLocation()
    }

    // MARK: - Live sharing (for live events)

    func startLiveSharing(for eventId: String) {
        liveEventId = eventId
        switch manager.authorizationStatus {
        case .authorizedAlways:
            beginLiveUpdates()
        case .authorizedWhenInUse:
            // Without Always, everything below still works while the app is
            // open and simply stops when it isn't — the host's pin holds at
            // their last position rather than going stale silently.
            manager.requestAlwaysAuthorization()
            beginLiveUpdates()
        case .notDetermined:
            manager.requestAlwaysAuthorization()
            // Picked back up in the delegate once the host answers.
        default:
            break
        }
    }

    func stopLiveSharing() {
        liveEventId = nil
        lastPublishedLocation = nil
        manager.stopMonitoringSignificantLocationChanges()

        monitorTask?.cancel()
        monitorTask = nil

        // Conditions outlive the process that added them, so a circle left
        // behind here would go on waking the app for an event that's over.
        let monitor = self.monitor
        self.monitor = nil
        Task { await monitor?.remove(Self.conditionIdentifier) }
    }

    // MARK: - Private

    private func beginLiveUpdates() {
        // The safety net under the geofence: a host who leaves fast enough can
        // outrun a region exit, and this catches those and re-draws the circle.
        manager.startMonitoringSignificantLocationChanges()
        // One fix now, so the event has a position the moment it starts rather
        // than whenever the host next moves.
        manager.requestLocation()
        startMonitoring()
    }

    private func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            // Only one monitor may be open under a given name, which is why
            // this is held rather than opened per circle.
            let monitor = await CLMonitor(Self.monitorName)
            guard let self, !Task.isCancelled else { return }
            self.monitor = monitor

            // A circle from a previous event points wherever the host was then.
            await monitor.remove(Self.conditionIdentifier)

            do {
                for try await event in await monitor.events {
                    guard event.identifier == Self.conditionIdentifier else { continue }
                    // Left the circle: take a single fix, which publishes the
                    // new position and draws the next circle around it.
                    if event.state == .unsatisfied {
                        self.manager.requestLocation()
                    }
                }
            } catch {
                print("LocationService monitoring ended: \(error.localizedDescription)")
            }
        }
    }

    private func armRegion(around coordinate: CLLocationCoordinate2D) async {
        guard let monitor else { return }
        let condition = CLMonitor.CircularGeographicCondition(
            center: coordinate,
            radius: Self.regionRadius
        )
        await monitor.remove(Self.conditionIdentifier)
        // Assumed satisfied because the host is standing in the middle of it —
        // the only event worth hearing about is them leaving.
        await monitor.add(condition, identifier: Self.conditionIdentifier, assuming: .satisfied)
    }

    private func publish(_ location: CLLocation, for eventId: String) {
        if let last = lastPublishedLocation,
           location.distance(from: last) < Self.minPublishDistance {
            return
        }
        lastPublishedLocation = location

        let geoPoint = GeoPoint(latitude: location.coordinate.latitude,
                                longitude: location.coordinate.longitude)
        Task {
            try? await eventService.updateLiveLocation(eventId: eventId, coordinate: geoPoint)
        }
        Task { await armRegion(around: location.coordinate) }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // A negative accuracy means the fix is invalid, and publishing one would
        // move the host's pin somewhere they've never been.
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        currentLocation = location

        guard let eventId = liveEventId else { return }
        publish(location, for: eventId)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationService error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        guard liveEventId != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginLiveUpdates()
        default:
            break
        }
    }

    // MARK: - Distance filtering

    func distance(from coordinate: GeoPoint) -> CLLocationDistance? {
        guard let current = currentLocation else { return nil }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return current.distance(from: target) / 1609.34  // meters → miles
    }
}
