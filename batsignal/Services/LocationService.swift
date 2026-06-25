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

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
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
            manager.startMonitoringSignificantLocationChanges()
            manager.requestLocation() // one-shot GPS fix for immediate initial coordinate
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
            manager.startMonitoringSignificantLocationChanges()
            manager.requestLocation()
        case .notDetermined:
            manager.requestAlwaysAuthorization()
            // both called in delegate once granted
        default:
            break
        }
    }

    func stopLiveSharing() {
        liveEventId = nil
        manager.stopMonitoringSignificantLocationChanges()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location

        if let eventId = liveEventId {
            let geoPoint = GeoPoint(latitude: location.coordinate.latitude,
                                    longitude: location.coordinate.longitude)
            Task {
                try? await eventService.updateLiveLocation(eventId: eventId, coordinate: geoPoint)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationService error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        guard liveEventId != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startMonitoringSignificantLocationChanges()
            manager.requestLocation()
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
