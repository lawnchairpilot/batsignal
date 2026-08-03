import SwiftUI
import Combine
import MapKit
import FirebaseFirestore
import FirebaseCore
import FirebaseAuth
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
    var creatorPhotoURL: String?

    @State private var liveCoordinate: CLLocationCoordinate2D?
    @State private var liveListener: ListenerRegistration?
    @State private var joinedUserIds: [String]
    @State private var joinedUsers: [User] = []
    @State private var isJoining = false
    @State private var isAttendeeListExpanded = false
    @State private var now = Date()

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init(event: Event, creatorName: String? = nil, creatorPhotoURL: String? = nil) {
        self.event = event
        self.creatorName = creatorName
        self.creatorPhotoURL = creatorPhotoURL
        self._joinedUserIds = State(initialValue: event.joinedUserIds ?? [])
    }

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    private var isJoined: Bool {
        guard let uid = currentUserId else { return false }
        return joinedUserIds.contains(uid)
    }

    private var isOwnEvent: Bool {
        currentUserId != nil && event.creatorId == currentUserId
    }

    private var displayCoordinate: CLLocationCoordinate2D? {
        if let live = liveCoordinate { return live }
        guard let geoPoint = event.locationCoordinate else { return nil }
        return CLLocationCoordinate2D(latitude: geoPoint.latitude, longitude: geoPoint.longitude)
    }

    private var annotationLabel: String? {
        if let emoji = event.emoji { return emoji }
        guard let name = creatorName, !name.isEmpty else { return nil }
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return initials.isEmpty ? nil : initials.uppercased()
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

                // Time + Location, side by side
                HStack(alignment: .top, spacing: 12) {
                    timeBlock
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                    Group {
                        if let coordinate = displayCoordinate {
                            MapThumbnailView(
                                coordinate: coordinate,
                                annotationLabel: annotationLabel,
                                annotationPhotoURL: event.imageURL ?? creatorPhotoURL,
                                isLive: event.locationType == .live,
                                eventId: event.id
                            )
                        } else if event.locationType == .live {
                            VStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(Strings.Event.waitingForLocation)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.secondarySystemBackground))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .cornerRadius(12)
                    .clipped()
                }
                .frame(height: 180)

                if let imageURL = event.imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            Color(.secondarySystemBackground)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .cornerRadius(12)
                    .clipped()
                }

                if !isOwnEvent {

                    Button(action: toggleJoin) {
                        HStack {
                            Image(systemName: isJoined ? "checkmark.circle.fill" : "person.badge.plus")
                            Text(isJoined ? Strings.Event.joined : Strings.Event.join)
                        }
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isJoined ? Color.accentColor.opacity(0.15) : Color.accentColor)
                        .foregroundColor(isJoined ? .accentColor : .white)
                        .cornerRadius(14)
                    }
                    .disabled(isJoining)
                }

                if !joinedUsers.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if isAttendeeListExpanded {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 16) {
                                    ForEach(joinedUsers) { user in
                                        VStack(spacing: 6) {
                                            EventIconView(photoURL: user.profilePhotoURL, label: initials(for: user.displayName), size: 64)
                                            Text(user.displayName)
                                                .font(.caption)
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                                .frame(width: 72)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        } else {
                            HStack(spacing: -8) {
                                ForEach(joinedUsers.prefix(6)) { user in
                                    EventIconView(photoURL: user.profilePhotoURL, label: initials(for: user.displayName), size: 28)
                                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                                }
                                if joinedUsers.count > 6 {
                                    Text("+\(joinedUsers.count - 6)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(Color(.systemGray3))
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                                }
                            }
                        }
                        Text(Strings.Event.goingCount(joinedUsers.count))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isAttendeeListExpanded.toggle()
                        }
                    }
                }

                if event.commentsAllowed, let eventId = event.id {
                    Divider()
                    CommentsSectionView(eventId: eventId)
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(timer) { now = $0 }
        .onAppear {
            Task { await loadJoinedUsers() }
            guard let eventId = event.id else { return }
            liveListener = EventService().listenToEvent(id: eventId) { updatedEvent in
                Task { @MainActor in
                    guard let updatedEvent else { return }
                    if event.locationType == .live, let geoPoint = updatedEvent.locationCoordinate {
                        liveCoordinate = CLLocationCoordinate2D(
                            latitude: geoPoint.latitude,
                            longitude: geoPoint.longitude
                        )
                    }
                    let newJoinedIds = updatedEvent.joinedUserIds ?? []
                    if Set(newJoinedIds) != Set(joinedUserIds) {
                        joinedUserIds = newJoinedIds
                        await loadJoinedUsers()
                    }
                }
            }
        }
        .onDisappear {
            liveListener?.remove()
            liveListener = nil
        }
    }

    private func initials(for name: String) -> String? {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return initials.isEmpty ? nil : initials.uppercased()
    }

    private func loadJoinedUsers() async {
        guard let users = try? await FriendService().fetchFriends(ids: joinedUserIds) else { return }
        await MainActor.run { joinedUsers = users }
    }

    private func toggleJoin() {
        guard let eventId = event.id, let uid = currentUserId else { return }
        let wasJoined = isJoined
        isJoining = true
        if wasJoined {
            joinedUserIds.removeAll { $0 == uid }
            joinedUsers.removeAll { $0.id == uid }
        } else {
            joinedUserIds.append(uid)
            if let me = AuthService.shared.currentUser {
                joinedUsers.append(me)
            }
        }
        Task {
            do {
                if wasJoined {
                    try await EventService().leaveEvent(id: eventId)
                } else {
                    try await EventService().joinEvent(id: eventId)
                }
            } catch {
                await MainActor.run {
                    if wasJoined {
                        joinedUserIds.append(uid)
                        if let me = AuthService.shared.currentUser {
                            joinedUsers.append(me)
                        }
                    } else {
                        joinedUserIds.removeAll { $0 == uid }
                        joinedUsers.removeAll { $0.id == uid }
                    }
                }
            }
            await MainActor.run { isJoining = false }
        }
    }

    private var remainingSeconds: TimeInterval? {
        guard let endTime = event.endTime?.dateValue() else { return nil }
        let remaining = endTime.timeIntervalSince(now)
        return remaining > 0 ? remaining : nil
    }

    private var remainingHours: Int {
        Int((remainingSeconds ?? 0) / 3600)
    }

    private var remainingMinutes: Int {
        Int((remainingSeconds ?? 0) / 60) % 60
    }

    @ViewBuilder
    private var timeBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if event.endTime == nil {
                Text(Strings.Event.timeLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(startTimeLabel)
                    .font(.title2.bold())
            } else if remainingSeconds == nil {
                Text(Strings.Event.eventEnded)
                    .font(.title2.bold())
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if remainingHours > 0 {
                        Text("\(remainingHours)h")
                    }
                    Text("\(remainingMinutes)m")
                }
                .font(.system(size: 52, weight: .bold, design: .rounded))
                Text(Strings.Event.timeLeftCaption)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var startTimeLabel: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let time = formatter.string(from: event.startTime.dateValue())
        if Calendar.current.isDateInTomorrow(event.startTime.dateValue()) {
            return Strings.Event.tomorrowAt(time)
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
    @State private var opacity: Double = 1.0

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.white)
                .frame(width: 7, height: 7)
                .opacity(opacity)
            Text(Strings.Event.live)
                .font(.caption2.bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.red)
        .clipShape(Capsule())
        .task {
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.75)) { opacity = 0.2 }
                try? await Task.sleep(for: .milliseconds(750))
                withAnimation(.easeInOut(duration: 0.75)) { opacity = 1.0 }
                try? await Task.sleep(for: .milliseconds(750))
            }
        }
    }
}

// MARK: - Custom map annotation (EventIconView circle + pin tail)

struct EventAnnotationView: View {
    var label: String? = nil
    var photoURL: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            EventIconView(photoURL: photoURL, label: label)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
            Image(systemName: "triangle.fill")
                .font(.system(size: 9))
                .foregroundColor(.accentColor)
                .rotationEffect(.degrees(180))
                .offset(y: -3)
        }
    }
}

// MARK: - Map thumbnail (non-interactive, tappable to expand)

struct MapThumbnailView: View {
    let coordinate: CLLocationCoordinate2D
    var annotationLabel: String? = nil
    var annotationPhotoURL: String? = nil
    var isLive: Bool = false
    var eventId: String? = nil

    @State private var markerCoord: CLLocationCoordinate2D
    @State private var showFullMap = false

    init(coordinate: CLLocationCoordinate2D, annotationLabel: String? = nil, annotationPhotoURL: String? = nil, isLive: Bool = false, eventId: String? = nil) {
        self.coordinate = coordinate
        self.annotationLabel = annotationLabel
        self.annotationPhotoURL = annotationPhotoURL
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
                if annotationLabel != nil || annotationPhotoURL != nil {
                    Annotation("", coordinate: markerCoord) {
                        EventAnnotationView(label: annotationLabel, photoURL: annotationPhotoURL)
                    }
                } else {
                    Marker("", coordinate: markerCoord)
                }
                UserAnnotation()
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
            FullMapView(coordinate: markerCoord, annotationLabel: annotationLabel, annotationPhotoURL: annotationPhotoURL, isLive: isLive, eventId: eventId)
        }
    }
}

// MARK: - Full-screen map with live updates and Open in Maps

struct FullMapView: View {
    let coordinate: CLLocationCoordinate2D
    var annotationLabel: String? = nil
    var annotationPhotoURL: String? = nil
    var isLive: Bool = false
    var eventId: String? = nil

    @State private var position: MapCameraPosition
    @State private var markerCoord: CLLocationCoordinate2D
    @State private var liveListener: ListenerRegistration?
    @Environment(\.dismiss) private var dismiss

    init(coordinate: CLLocationCoordinate2D, annotationLabel: String? = nil, annotationPhotoURL: String? = nil, isLive: Bool = false, eventId: String? = nil) {
        self.coordinate = coordinate
        self.annotationLabel = annotationLabel
        self.annotationPhotoURL = annotationPhotoURL
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
            ZStack {
                Map(position: $position) {
                    if annotationLabel != nil || annotationPhotoURL != nil {
                        Annotation("", coordinate: markerCoord) {
                            EventAnnotationView(label: annotationLabel, photoURL: annotationPhotoURL)
                        }
                    } else {
                        Marker("", coordinate: markerCoord)
                    }
                    UserAnnotation()
                }
                .ignoresSafeArea()

                VStack {
                    HStack {
                        Spacer()
                        if isLive {
                            LiveBadge()
                                .padding(.trailing, 16)
                                .padding(.top, 8)
                        }
                    }
                    Spacer()
                    Button(action: openInMaps) {
                        Label(Strings.Event.openInMaps, systemImage: "map.fill")
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
                    Button(Strings.Common.done) { dismiss() }
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