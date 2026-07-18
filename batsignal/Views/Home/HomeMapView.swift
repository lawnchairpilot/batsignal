import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - Annotation data

struct EventAnnotationItem: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let label: String?           // emoji or initials
    let creatorPhotoURL: String?
    let isLive: Bool
    let isActive: Bool
    let event: Event
    let creatorName: String?
}

// MARK: - Camera position helpers

private let defaultMapSpan = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)

func cameraPosition(centeredOn coordinate: CLLocationCoordinate2D) -> MapCameraPosition {
    .region(MKCoordinateRegion(center: coordinate, span: defaultMapSpan))
}

private func defaultCameraPosition(userCoordinate: CLLocationCoordinate2D?) -> MapCameraPosition {
    guard let userCoordinate else { return .automatic }
    return cameraPosition(centeredOn: userCoordinate)
}

// MARK: - One-shot location (only fires if permission already granted)

private final class OneTimeLocationProvider: NSObject, CLLocationManagerDelegate, ObservableObject {
    @Published var coordinate: CLLocationCoordinate2D?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        coordinate = locations.last?.coordinate
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

// MARK: - Thumbnail (non-interactive, tappable to expand)

struct HomeMapView: View {
    let annotations: [EventAnnotationItem]
    var focusedCoordinate: CLLocationCoordinate2D?
    var onSelectEvent: (Event) -> Void = { _ in }

    @StateObject private var locationProvider = OneTimeLocationProvider()
    @State private var position: MapCameraPosition = .automatic
    @State private var showFullMap = false

    private var hasLiveEvent: Bool { annotations.contains { $0.isLive } }

    var body: some View {
        ZStack {
            Map(position: $position, interactionModes: []) {
                ForEach(annotations) { item in
                    Annotation("", coordinate: item.coordinate) {
                        Button {
                            onSelectEvent(item.event)
                        } label: {
                            EventAnnotationView(label: item.label, photoURL: item.creatorPhotoURL)
                        }
                        .buttonStyle(.plain)
                    }
                }
                UserAnnotation()
            }
            .onTapGesture { showFullMap = true }

            if hasLiveEvent {
                VStack {
                    HStack {
                        Spacer()
                        LiveBadge().padding(8)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .frame(height: 200)
        .cornerRadius(12)
        .clipped()
        .onAppear { refreshPosition() }
        .onChange(of: locationProvider.coordinate) { _, _ in refreshPosition() }
        .onChange(of: focusedCoordinate) { _, _ in refreshPosition() }
        .sheet(isPresented: $showFullMap) {
            HomeFullMapView(annotations: annotations, initialPosition: position)
        }
    }

    private func refreshPosition() {
        if let focusedCoordinate {
            position = cameraPosition(centeredOn: focusedCoordinate)
        } else {
            position = defaultCameraPosition(userCoordinate: locationProvider.coordinate)
        }
    }
}

// MARK: - Full-screen interactive map

struct HomeFullMapView: View {
    let annotations: [EventAnnotationItem]
    let initialPosition: MapCameraPosition

    @State private var position: MapCameraPosition
    @State private var selectedItem: EventAnnotationItem?
    @Environment(\.dismiss) private var dismiss

    private var hasLiveEvent: Bool { annotations.contains { $0.isLive } }

    init(annotations: [EventAnnotationItem], initialPosition: MapCameraPosition) {
        self.annotations = annotations
        self.initialPosition = initialPosition
        self._position = State(initialValue: initialPosition)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $position) {
                    ForEach(annotations) { item in
                        Annotation("", coordinate: item.coordinate) {
                            Button { selectedItem = item } label: {
                                EventAnnotationView(label: item.label, photoURL: item.creatorPhotoURL)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    UserAnnotation()
                }
                .ignoresSafeArea()

                if hasLiveEvent {
                    VStack {
                        HStack {
                            Spacer()
                            LiveBadge()
                                .padding(.trailing, 16)
                                .padding(.top, 8)
                        }
                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Common.done) { dismiss() }
                }
            }
            .sheet(item: $selectedItem) { item in
                NavigationStack {
                    EventDetailView(
                        event: item.event,
                        creatorName: item.creatorName,
                        creatorPhotoURL: item.creatorPhotoURL
                    )
                    .navigationTitle(item.event.activity)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(Strings.Common.done) { selectedItem = nil }
                        }
                    }
                }
            }
        }
    }
}
