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
        requestLocationIfPossible()
    }

    private func requestLocationIfPossible() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        coordinate = locations.last?.coordinate
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        requestLocationIfPossible()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

// MARK: - Thumbnail (pan/zoom in place, with a button to expand full-screen)

struct HomeMapView: View {
    let annotations: [EventAnnotationItem]
    var focusedCoordinate: CLLocationCoordinate2D?
    var focusedEventId: String?
    var height: CGFloat = 340
    var onSelectEvent: (Event) -> Void = { _ in }

    @StateObject private var locationProvider = OneTimeLocationProvider()
    @State private var position: MapCameraPosition = .automatic
    @State private var showFullMap = false
    // Marking the focused pin as the map's selection is the only lever SwiftUI
    // gives over stacking: MapKit raises the selected annotation view above the
    // unselected ones, so a pin sharing the same spot can't bury it.
    @State private var selectedAnnotationId: String?

    private var hasLiveEvent: Bool { annotations.contains { $0.isLive } }

    var body: some View {
        ZStack {
            Map(position: $position, interactionModes: [.pan, .zoom], selection: $selectedAnnotationId) {
                ForEach(annotations) { item in
                    Annotation("", coordinate: item.coordinate) {
                        Button {
                            onSelectEvent(item.event)
                        } label: {
                            EventAnnotationView(label: item.label, photoURL: item.creatorPhotoURL)
                        }
                        .buttonStyle(.plain)
                    }
                    .tag(item.id)
                }
                UserAnnotation()
            }

            VStack {
                HStack {
                    if hasLiveEvent {
                        LiveBadge().padding(8)
                    }
                    Spacer()
                    Button(action: { showFullMap = true }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                            .padding(8)
                            .background(.thinMaterial, in: Circle())
                    }
                    .padding(8)
                }
                Spacer()
            }
        }
        .frame(height: height)
        .cornerRadius(12)
        .clipped()
        .onAppear {
            refreshPosition()
            selectedAnnotationId = focusedEventId
        }
        .onChange(of: locationProvider.coordinate) { _, _ in refreshPosition() }
        .onChange(of: focusedCoordinate) { _, _ in refreshPosition() }
        .onChange(of: focusedEventId) { _, newValue in selectedAnnotationId = newValue }
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
                // Pins here are just markers: details live on the cards back on
                // the home map, which this view has none of.
                Map(position: $position) {
                    ForEach(annotations) { item in
                        Annotation("", coordinate: item.coordinate) {
                            EventAnnotationView(label: item.label, photoURL: item.creatorPhotoURL)
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
        }
    }
}
