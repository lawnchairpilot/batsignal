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
// Focusing a single event is a chance to show its surroundings properly, so the
// hero framing zooms in past the overview span.
private let heroMapSpan = MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)

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
    // The event whose card is open, if any. Its pin becomes the hero of the
    // map: blown up to roughly the size of the creation screen's preview
    // circle, with the camera reframed around it.
    var enlargedEventId: String?
    // How much of the map's bottom edge the carousel covers, so the hero pin
    // can be centred in the strip that's actually visible rather than in the
    // map's own middle — which an expanded card sits right on top of.
    var occludedBottomHeight: CGFloat = 0
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
                    // Anchored at the bottom so the tail tip marks the actual
                    // coordinate. With .center the pin only pointed at its
                    // location by accident of its size, which stops being true
                    // the moment one of them is five times bigger than the rest.
                    Annotation("", coordinate: item.coordinate, anchor: .bottom) {
                        Button {
                            onSelectEvent(item.event)
                        } label: {
                            EventAnnotationView(
                                label: item.label,
                                photoURL: item.creatorPhotoURL,
                                size: item.id == enlargedEventId ? heroIconSize : EventAnnotationView.defaultSize
                            )
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
        .onChange(of: enlargedEventId) { _, _ in refreshPosition() }
        // The card's height settles a beat after it opens, so the framing has
        // to follow it rather than being computed once on expansion.
        .onChange(of: occludedBottomHeight) { _, _ in
            guard enlargedEventId != nil else { return }
            refreshPosition()
        }
        .onChange(of: focusedEventId) { _, newValue in selectedAnnotationId = newValue }
        .sheet(isPresented: $showFullMap) {
            HomeFullMapView(annotations: annotations, initialPosition: position)
        }
    }

    private func refreshPosition() {
        if let heroCoordinate {
            position = heroCameraPosition(for: heroCoordinate)
        } else if let focusedCoordinate {
            position = cameraPosition(centeredOn: focusedCoordinate)
        } else {
            position = defaultCameraPosition(userCoordinate: locationProvider.coordinate)
        }
    }

    // MARK: - Hero framing

    private var heroCoordinate: CLLocationCoordinate2D? {
        guard let enlargedEventId else { return nil }
        return annotations.first { $0.id == enlargedEventId }?.coordinate
    }

    // The band of map the expanded card leaves uncovered.
    private var visibleStripHeight: CGFloat {
        max(height - occludedBottomHeight, 0)
    }

    // As close to the creation screen's preview circle as the uncovered band
    // allows. On a short map with a tall card there simply isn't room for the
    // full 220, and a pin that overshoots the strip is worse than a smaller one.
    private var heroIconSize: CGFloat {
        let available = visibleStripHeight - heroTopMargin - heroCardGap
        let fits = available / 1.2  // the tail takes the other 0.2
        return min(heroIconMaxSize, max(EventAnnotationView.defaultSize, fits))
    }

    // Centres the whole pin in the uncovered band. The pin is anchored at its
    // tip, so it hangs upward from the coordinate — which is why the coordinate
    // itself ends up low on the screen, with the enlarged circle filling the
    // space above it.
    private func heroCameraPosition(for coordinate: CLLocationCoordinate2D) -> MapCameraPosition {
        let pinHeight = EventAnnotationView.totalHeight(forIconSize: heroIconSize)
        let bandCentre = (heroTopMargin + visibleStripHeight - heroCardGap) / 2
        let tipY = bandCentre + pinHeight / 2
        // How far down the screen the coordinate has to move from the map's
        // centre, where an un-shifted camera would put it.
        let shift = tipY - height / 2
        // Approximate: MapKit adjusts a requested region to the view's aspect
        // ratio, so this treats the span we ask for as the span we get. Close
        // enough for framing, and it degrades gracefully if MapKit widens it.
        let latitudePerPoint = heroMapSpan.latitudeDelta / Double(height)
        let centre = CLLocationCoordinate2D(
            latitude: coordinate.latitude + Double(shift) * latitudePerPoint,
            longitude: coordinate.longitude
        )
        return .region(MKCoordinateRegion(center: centre, span: heroMapSpan))
    }
}

private let heroIconMaxSize: CGFloat = 220  // EventSymbolHeader's preview circle
private let heroTopMargin: CGFloat = 16
private let heroCardGap: CGFloat = 12

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
                        Annotation("", coordinate: item.coordinate, anchor: .bottom) {
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
