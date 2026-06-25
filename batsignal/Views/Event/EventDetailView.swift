import SwiftUI
import MapKit
import FirebaseFirestore
import FirebaseCore
internal import FirebaseFirestoreInternal

// Allows CLLocationCoordinate2D to be observed with .onChange(of:)
extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

struct EventDetailView: View {
    let event: Event
    var creatorName: String?

    @State private var liveCoordinate: CLLocationCoordinate2D?
    @State private var liveListener: ListenerRegistration?

    private var displayCoordinate: CLLocationCoordinate2D? {
        if let live = liveCoordinate { return live }
        guard let geoPoint = event.locationCoordinate else { return nil }
        return CLLocationCoordinate2D(latitude: geoPoint.latitude, longitude: geoPoint.longitude)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Activity + description
                VStack(alignment: .leading, spacing: 6) {
                    if let name = creatorName {
                        Label(name, systemImage: "person.fill")
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                    }
                    Text(event.activity).font(.title.bold())
                    if let desc = event.description {
                        Text(desc).foregroundColor(.secondary)
                    }
                }

                Divider()

                // Time
                VStack(alignment: .leading, spacing: 4) {
                    Label("Time", systemImage: "clock")
                        .font(.subheadline).foregroundColor(.secondary)
                    Text(startTimeLabel)
                        .font(.body)
                    if !event.durationLabel.isEmpty {
                        Text(event.durationLabel)
                            .font(.body).foregroundColor(.secondary)
                    }
                }

                Divider()

                // Location
                VStack(alignment: .leading, spacing: 8) {
                    Label("Location", systemImage: locationIcon)
                        .font(.subheadline).foregroundColor(.secondary)

                    if let label = event.locationLabel {
                        Text(label).font(.body)
                    }

                    if let coordinate = displayCoordinate {
                        MapThumbnailView(
                            coordinate: coordinate,
                            isLive: event.locationType == .live,
                            eventId: event.id
                        )
                        .frame(height: 180)
                        .cornerRadius(12)
                        .clipped()
                    } else if event.locationType == .live {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Waiting for location…")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if event.locationType == .live {
                        Label("Live location", systemImage: "location.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard event.locationType == .live, let eventId = event.id else { return }
            liveListener = EventService().listenToEvent(id: eventId) { updatedEvent in
                Task { @MainActor in
                    guard let geoPoint = updatedEvent?.locationCoordinate else { return }
                    liveCoordinate = CLLocationCoordinate2D(
                        latitude: geoPoint.latitude,
                        longitude: geoPoint.longitude
                    )
                }
            }
        }
        .onDisappear {
            liveListener?.remove()
            liveListener = nil
        }
    }

    private var startTimeLabel: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let time = formatter.string(from: event.startTime.dateValue())
        if Calendar.current.isDateInTomorrow(event.startTime.dateValue()) {
            return "Tomorrow · \(time)"
        }
        return time
    }

    private var locationIcon: String {
        switch event.locationType {
        case .text:   return "mappin"
        case .fixed:  return "mappin.circle"
        case .live:   return "location.fill"
        }
    }
}

// MARK: - Live badge

struct LiveBadge: View {
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.red)
                .frame(width: 7, height: 7)
                .scaleEffect(pulsing ? 1.35 : 0.85)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
                .onAppear { pulsing = true }
            Text("LIVE")
                .font(.caption2.bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.red)
        .clipShape(Capsule())
    }
}

// MARK: - Map thumbnail (non-interactive, tappable to expand)

struct MapThumbnailView: View {
    let coordinate: CLLocationCoordinate2D
    var isLive: Bool = false
    var eventId: String? = nil

    @State private var markerCoord: CLLocationCoordinate2D
    @State private var showFullMap = false

    init(coordinate: CLLocationCoordinate2D, isLive: Bool = false, eventId: String? = nil) {
        self.coordinate = coordinate
        self.isLive = isLive
        self.eventId = eventId
        self._markerCoord = State(initialValue: coordinate)
    }

    var body: some View {
        ZStack {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))) {
                Marker("", coordinate: markerCoord)
            }
            .disabled(true)

            if isLive {
                VStack {
                    HStack {
                        Spacer()
                        LiveBadge()
                            .padding(8)
                    }
                    Spacer()
                }
            }

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showFullMap = true }
        }
        .onChange(of: coordinate) { _, newCoord in
            markerCoord = newCoord
        }
        .sheet(isPresented: $showFullMap) {
            FullMapView(coordinate: markerCoord, isLive: isLive, eventId: eventId)
        }
    }
}

// MARK: - Full-screen map with live updates and Open in Maps

struct FullMapView: View {
    let coordinate: CLLocationCoordinate2D
    var isLive: Bool = false
    var eventId: String? = nil

    @State private var position: MapCameraPosition
    @State private var markerCoord: CLLocationCoordinate2D
    @State private var liveListener: ListenerRegistration?
    @Environment(\.dismiss) private var dismiss

    init(coordinate: CLLocationCoordinate2D, isLive: Bool = false, eventId: String? = nil) {
        self.coordinate = coordinate
        self.isLive = isLive
        self.eventId = eventId
        self._position = State(initialValue: .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))
        self._markerCoord = State(initialValue: coordinate)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $position) {
                    Marker("", coordinate: markerCoord)
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    if isLive {
                        HStack {
                            Spacer()
                            LiveBadge()
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                    }

                    Button(action: openInMaps) {
                        Label("Open in Maps", systemImage: "map.fill")
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.regularMaterial)
                            .cornerRadius(16)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            guard isLive, let eventId else { return }
            liveListener = EventService().listenToEvent(id: eventId) { updatedEvent in
                Task { @MainActor in
                    guard let geoPoint = updatedEvent?.locationCoordinate else { return }
                    let newCoord = CLLocationCoordinate2D(
                        latitude: geoPoint.latitude,
                        longitude: geoPoint.longitude
                    )
                    markerCoord = newCoord
                    position = .region(MKCoordinateRegion(
                        center: newCoord,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
            }
        }
        .onDisappear {
            liveListener?.remove()
            liveListener = nil
        }
    }

    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: markerCoord)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.openInMaps()
    }
}