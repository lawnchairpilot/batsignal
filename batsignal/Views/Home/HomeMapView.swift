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

    // Everything the pin actually draws, folded into one value. MapKit hangs on
    // to the annotation view it already built for a given identity and doesn't
    // reliably re-render the SwiftUI content inside it when only the data
    // behind it changes — which is why an emoji added to a live signal kept
    // showing the old pin until the app was relaunched. Keying the ForEach on
    // this rather than on `id` alone makes a changed pin a *new* annotation,
    // and a new annotation does get drawn. Selection (`.tag`) and hero sizing
    // still key off `id`, so neither notices the swap.
    var renderIdentity: String {
        "\(id)|\(label ?? "")|\(creatorPhotoURL ?? "")|\(event.joinedCount)"
    }
}

// MARK: - Camera position helpers

private let defaultMapSpan = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
// Focusing a single event is a chance to show its surroundings properly, so the
// hero framing zooms in past the overview span.
private let heroMapSpan = MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)

// How much room the opening view leaves around the outermost pin, as a multiple
// of the spread it's fitting. Not decoration: a pin is drawn *above* the
// coordinate it marks and stands up to 57pt tall, so a fit measured on the
// coordinates alone clips the topmost one in half.
private let overviewPadding: Double = 1.35

// A ceiling on how far the opening view will pull back. Nothing guarantees an
// event is anywhere near the user — the radius setting is optional, and a bad
// write could leave a pin at (0, 0) — and without a cap a single outlier zooms
// the map out to where nothing local is legible. Past the cap a pin stays off
// the opening frame and is reached through its carousel card instead. Set well
// clear of the widest radius setting (100 miles) so a normal spread always fits.
private let overviewMaxDelta: Double = 4.0

// A ceiling on the carousel clearance below. The clearance grows without bound
// as the uncovered band closes on half the map, and past this the zoom-out
// costs more legibility than the southernmost pin is worth — it drops behind
// the cards instead, still one swipe away on its own card.
private let overviewMaxPadding: Double = 2.5

func cameraPosition(centeredOn coordinate: CLLocationCoordinate2D) -> MapCameraPosition {
    .region(MKCoordinateRegion(center: coordinate, span: defaultMapSpan))
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

// MARK: - The home screen's full-bleed map

struct HomeMapView: View {
    let annotations: [EventAnnotationItem]
    var focusedCoordinate: CLLocationCoordinate2D?
    var focusedEventId: String?
    // The event whose card is open, if any. Its pin becomes the hero of the
    // map: blown up to roughly the size of the creation screen's preview
    // circle, with the camera reframed around it.
    var enlargedEventId: String?
    // Set when the carousel is sitting on your own card with no signal pinned
    // to point at. It's what separates "you swiped back to the create prompt",
    // which re-centres on you the way it always did, from the opening state,
    // where nothing has been picked yet and the map fits what's happening.
    var focusUserLocation: Bool = false
    // How much of the map's bottom edge the carousel covers, so the hero pin
    // can be centred in the strip that's actually visible rather than in the
    // map's own middle — which an expanded card sits right on top of.
    var occludedBottomHeight: CGFloat = 0
    // The height the map is actually laid out at. Not applied as a frame — the
    // map fills whatever it's given — it's the yardstick the hero framing
    // measures its camera shift against.
    var height: CGFloat = 340
    var onSelectEvent: (Event) -> Void = { _ in }

    @StateObject private var locationProvider = OneTimeLocationProvider()
    @State private var position: MapCameraPosition = .automatic
    // Marking the focused pin as the map's selection is the only lever SwiftUI
    // gives over stacking: MapKit raises the selected annotation view above the
    // unselected ones, so a pin sharing the same spot can't bury it.
    @State private var selectedAnnotationId: String?

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom], selection: $selectedAnnotationId) {
            ForEach(annotations, id: \.renderIdentity) { item in
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
                            size: iconSize(for: item),
                            // Read off the event itself rather than carried on
                            // the annotation item, so the count the pin glows
                            // by is the same one the card counts faces from.
                            joinCount: item.event.joinedCount
                        )
                    }
                    .buttonStyle(.plain)
                }
                .tag(item.id)
            }
            UserAnnotation()
        }
        // Fills the system's own "you are here" dot, which takes the map's
        // tint. Swell blue rather than the app's moonlight so the dot reads as
        // part of the water rather than as another piece of chrome — and it
        // keeps the white ring, accuracy circle and heading wedge that come
        // with the built-in dot.
        .tint(Blipper.swellBlue)
        // Over the map, under everything HomeView lays on top of it — the
        // header and the carousel both want to stay out of the fog.
        .overlay(MapFogVignette())
        .onAppear {
            refreshPosition()
            selectedAnnotationId = focusedEventId
        }
        .onChange(of: locationProvider.coordinate) { _, _ in refreshPosition() }
        // Events arrive from Firestore a beat after the map is on screen, so
        // the opening frame has to be redone once they land or it fits nothing
        // but the user's own dot.
        .onChange(of: fittedAnnotationIdentity) { _, _ in refreshPosition() }
        .onChange(of: focusedCoordinate) { _, _ in refreshPosition() }
        .onChange(of: enlargedEventId) { _, _ in refreshPosition() }
        .onChange(of: focusUserLocation) { _, _ in refreshPosition() }
        // The card's height settles a beat after it opens, so the framing has
        // to follow it rather than being computed once on expansion.
        .onChange(of: occludedBottomHeight) { _, _ in
            guard enlargedEventId != nil else { return }
            refreshPosition()
        }
        .onChange(of: focusedEventId) { _, newValue in selectedAnnotationId = newValue }
    }

    private func refreshPosition() {
        if let heroCoordinate {
            position = heroCameraPosition(for: heroCoordinate)
        } else if let focusedCoordinate {
            position = cameraPosition(centeredOn: focusedCoordinate)
        } else if focusUserLocation, let userCoordinate = locationProvider.coordinate {
            position = cameraPosition(centeredOn: userCoordinate)
        } else {
            position = overviewCameraPosition
        }
    }

    // MARK: - Opening framing

    // What the map opens on, and what it returns to whenever no one event is
    // focused: the user's own dot and every signal happening right now, rather
    // than a fixed span around the user, which left anything more than a few
    // blocks away off-screen at launch. Zooming in on one event is what
    // swiping the carousel is for; this is the view that starts broad enough
    // to show there's something to swipe to.
    private var overviewCameraPosition: MapCameraPosition {
        // Upcoming signals keep their pins but stay out of the fit. Pulling the
        // camera back is for showing what's going on now — a signal set for
        // tomorrow across town isn't that, and letting one widen the opening
        // view would shrink everything that is.
        let eventCoordinates = fittedAnnotations.map(\.coordinate)

        // Nothing happening: open exactly the way the map always has, the
        // user's location at the standard span.
        guard !eventCoordinates.isEmpty else {
            guard let userCoordinate = locationProvider.coordinate else { return .automatic }
            return cameraPosition(centeredOn: userCoordinate)
        }

        let latitudes = eventCoordinates.map(\.latitude)
        let longitudes = eventCoordinates.map(\.longitude)

        // The user's dot holds the centre. Framing the bounding box of the dot
        // and the pins instead only guaranteed the dot was somewhere on screen,
        // which with one distant signal meant the far corner, under the
        // wordmark. With no fix yet there's nothing to hold the centre, so the
        // signals' own midpoint stands in.
        let centre = locationProvider.coordinate ?? CLLocationCoordinate2D(
            latitude: ((latitudes.min() ?? 0) + (latitudes.max() ?? 0)) / 2,
            longitude: ((longitudes.min() ?? 0) + (longitudes.max() ?? 0)) / 2
        )

        // A pinned centre means the frame has to reach as far the opposite way
        // as it does towards its farthest signal: the span is twice the reach
        // from the centre, not the spread between the outermost pins.
        let latitudeReach = latitudes.map { abs($0 - centre.latitude) }.max() ?? 0
        let longitudeReach = longitudes.map { abs($0 - centre.longitude) }.max() ?? 0
        let padding = carouselClearingPadding

        // Floored at the span the map used to open on, so one signal across the
        // street doesn't slam the camera all the way in, and capped so one
        // across the county doesn't strand everything else in a dot.
        let latitudeDelta = min(
            max(2 * latitudeReach * padding, defaultMapSpan.latitudeDelta),
            overviewMaxDelta
        )
        let longitudeDelta = min(
            max(2 * longitudeReach * padding, defaultMapSpan.longitudeDelta),
            overviewMaxDelta
        )

        return .region(MKCoordinateRegion(
            center: centre,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        ))
    }

    // How much wider than the bare reach the frame opens. The hero framing can
    // lift its subject into the band the carousel leaves uncovered; a frame
    // locked to the user's dot can't move, so the only way its farthest signal
    // clears the cards is for the whole thing to open wider. Never below the
    // flat margin a pin needs regardless — a pin is drawn *above* the
    // coordinate it marks and stands up to 57pt tall, so a frame measured on
    // coordinates alone clips the top one in half.
    private var carouselClearingPadding: Double {
        let uncoveredBelowCentre = visibleStripHeight - height / 2
        guard uncoveredBelowCentre > 0 else { return overviewPadding }
        return min(max(overviewPadding, Double(height / 2 / uncoveredBelowCentre)), overviewMaxPadding)
    }

    // The pins the opening view has to fit: the active ones, matching what
    // overviewCameraPosition frames.
    private var fittedAnnotations: [EventAnnotationItem] {
        annotations.filter(\.isActive)
    }

    // Reframing keys off this set changing — signals landing after launch, one
    // ending, one crossing from upcoming into active — and not off the
    // annotations array, so a photo finishing its download or a headcount
    // ticking up can't yank a map the user is in the middle of panning.
    private var fittedAnnotationIdentity: String {
        fittedAnnotations.map(\.id).sorted().joined(separator: ",")
    }

    // MARK: - Pin sizing

    // An ordinary pin grows with the people who've joined it. The focused one
    // doesn't stack that on top: its size is a framing decision — as much of
    // the uncovered strip as it can fill — and it's the only pin at that size,
    // so there's nothing beside it for a bigger circle to mean anything
    // against. Its glow still answers to the headcount.
    private func iconSize(for item: EventAnnotationItem) -> CGFloat {
        guard item.id != enlargedEventId else { return heroIconSize }
        return EventAnnotationView.joinedSize(
            base: EventAnnotationView.defaultSize,
            joinCount: item.event.joinedCount
        )
    }

    // MARK: - Hero framing

    private var heroCoordinate: CLLocationCoordinate2D? {
        guard let enlargedEventId else { return nil }
        return annotations.first { $0.id == enlargedEventId }?.coordinate
    }

    // What the focused pin would be drawn at if it weren't focused — the floor
    // its hero size can't fall below. Without it, opening the card on a busy
    // signal could make its pin *smaller* than the one you just tapped, on a
    // map short enough that the strip left uncovered is tighter than the pin's
    // own grown size.
    private var enlargedEventUnfocusedSize: CGFloat {
        guard let enlarged = annotations.first(where: { $0.id == enlargedEventId }) else {
            return EventAnnotationView.defaultSize
        }
        return EventAnnotationView.joinedSize(
            base: EventAnnotationView.defaultSize,
            joinCount: enlarged.event.joinedCount
        )
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
        return min(heroIconMaxSize, max(enlargedEventUnfocusedSize, fits))
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
