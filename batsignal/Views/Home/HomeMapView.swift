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

// MARK: - Camera position helper

func bestCameraPosition(
    for annotations: [EventAnnotationItem],
    userCoordinate: CLLocationCoordinate2D?
) -> MapCameraPosition {
    let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)

    guard !annotations.isEmpty else {
        if let loc = userCoordinate {
            return .region(MKCoordinateRegion(center: loc, span: span))
        }
        return .automatic
    }

    let pool: [EventAnnotationItem] = {
        let active = annotations.filter { $0.isActive }
        return active.isEmpty ? annotations : active
    }()

    let center: CLLocationCoordinate2D
    if let userLoc = userCoordinate {
        let userCL = CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude)
        let nearest = pool.min {
            CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude).distance(from: userCL) <
            CLLocation(latitude: $1.coordinate.latitude, longitude: $1.coordinate.longitude).distance(from: userCL)
        }!
        center = nearest.coordinate
    } else {
        center = pool[0].coordinate
    }

    return .region(MKCoordinateRegion(center: center, span: span))
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

    @StateObject private var locationProvider = OneTimeLocationProvider()
    @State private var position: MapCameraPosition = .automatic
    @State private var showFullMap = false

    private var hasLiveEvent: Bool { annotations.contains { $0.isLive } }

    var body: some View {
        ZStack {
            Map(position: $position) {
                ForEach(annotations) { item in
                    Annotation("", coordinate: item.coordinate) {
                        EventAnnotationView(label: item.label, photoURL: item.creatorPhotoURL)
                    }
                }
                UserAnnotation()
            }
            .disabled(true)

            if hasLiveEvent {
                VStack {
                    HStack {
                        Spacer()
                        LiveBadge().padding(8)
                    }
                    Spacer()
                }
            }

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showFullMap = true }
        }
        .frame(height: 200)
        .cornerRadius(12)
        .clipped()
        .onAppear { refreshPosition() }
        .onChange(of: locationProvider.coordinate) { _, _ in refreshPosition() }
        .onChange(of: annotations.count) { _, _ in refreshPosition() }
        .sheet(isPresented: $showFullMap) {
            HomeFullMapView(
                annotations: annotations,
                initialPosition: bestCameraPosition(for: annotations, userCoordinate: locationProvider.coordinate)
            )
        }
    }

    private func refreshPosition() {
        position = bestCameraPosition(for: annotations, userCoordinate: locationProvider.coordinate)
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
                    Button("Done") { dismiss() }
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
                            Button("Done") { selectedItem = nil }
                        }
                    }
                }
            }
        }
    }
}
