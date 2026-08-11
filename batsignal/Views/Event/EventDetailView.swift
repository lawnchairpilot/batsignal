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

// The detail view for someone else's event, rendered as the expanded state of
// an EventCardView rather than as a sheet — so a friend's card and your own
// (MyActiveEventCard) both grow in place when tapped. Time/progress and the
// activity line are drawn the same way MyActiveEventCard's expanded card draws
// them, so the two read as one component in the carousel.
struct ExpandedEventCardView: View {
    let event: Event
    var creatorName: String?
    // Ceiling on the content's height, for hosts that can't grow to fit it —
    // see cardContent. nil means "take whatever room you need".
    var maxContentHeight: CGFloat?
    var onCollapse: (() -> Void)?

    // The listener's copy of the event, which supersedes the one passed in so
    // the progress bar keeps up with the creator extending or ending it.
    @State private var liveEvent: Event?
    @State private var liveListener: ListenerRegistration?
    @State private var joinedUserIds: [String]
    @State private var joinedUsers: [User] = []
    @State private var isJoining = false
    @State private var isAttendeeListExpanded = false
    @State private var contentHeight: CGFloat?
    @State private var now = Date()

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init(
        event: Event,
        creatorName: String? = nil,
        maxContentHeight: CGFloat? = nil,
        onCollapse: (() -> Void)? = nil
    ) {
        self.event = event
        self.creatorName = creatorName
        self.maxContentHeight = maxContentHeight
        self.onCollapse = onCollapse
        self._joinedUserIds = State(initialValue: event.joinedUserIds ?? [])
    }

    private var displayEvent: Event { liveEvent ?? event }

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

    var body: some View {
        cardContent
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
            )
            .onReceive(timer) { now = $0 }
            .onAppear {
                Task { await loadJoinedUsers() }
                guard let eventId = event.id, liveListener == nil else { return }
                liveListener = EventService().listenToEvent(id: eventId) { updatedEvent in
                    Task { @MainActor in
                        guard let updatedEvent else { return }
                        liveEvent = updatedEvent
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

    // MARK: - Sections

    // In the carousel this card is bottom-anchored over a fixed-height map, so
    // content taller than the map grows *upward* off the top of it and into the
    // navigation bar. Where the host gives a ceiling, the content scrolls inside
    // the card rather than escaping it.
    // Measured rather than clamped up front: seeding the height with the
    // ceiling and correcting it once measured opens the card at full height and
    // then shrinks it, which — bottom-anchored — reads as the card dropping
    // downward as it appears. Sizing naturally until it's known to overflow
    // means the common case is right on the first pass and never animates.
    @ViewBuilder
    private var cardContent: some View {
        if let maxContentHeight, contentHeight ?? 0 > maxContentHeight {
            ScrollView {
                measuredSections
            }
            .scrollBounceBehavior(.basedOnSize)
            // Nothing overlaps this scroll view, so its edge effect would only
            // fade the card's own header against the card's own background.
            .scrollEdgeEffectHidden()
            .frame(height: maxContentHeight)
        } else {
            measuredSections
        }
    }

    // The height is the same in both branches — a scroll view proposes its
    // content the same unbounded height the card does — so this can't oscillate
    // between them.
    private var measuredSections: some View {
        sections
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let desc = displayEvent.description, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            timeBlock
            locationRow
            joinRow
            boolersSection

            // Comments are deliberately left off the expanded card for now.
            // CommentsSectionView, Event.commentsAllowed and the Firestore side
            // are all still in place, so this is the one line to restore:
            //
            //   if displayEvent.commentsAllowed, let eventId = displayEvent.id {
            //       Divider()
            //       CommentsSectionView(eventId: eventId)
            //   }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let creatorName {
                    Text(creatorName)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .bold()
                }
                Text(displayEvent.activity)
                    .font(.headline)
            }

            Spacer(minLength: 8)

            if !displayEvent.isActive, let eta = displayEvent.startsInLabel {
                Text(eta)
                    .font(.caption.bold())
                    .foregroundColor(.accentColor)
            }

            if let onCollapse {
                Button(action: onCollapse) {
                    Image(systemName: "chevron.down.circle")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Mirrors MyActiveEventCard's expanded card: a draining progress bar while
    // the event is running, the vague label when there's nothing to drain, and
    // a plain start time before it begins.
    @ViewBuilder
    private var timeBlock: some View {
        if displayEvent.isActive {
            if let remaining = displayEvent.remainingFraction {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: remaining)
                        .tint(remainingColor(remaining))
                    if let label = displayEvent.timeRemainingLabel {
                        Text(label)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if let label = displayEvent.durationVagueLabel {
                Label(label, systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text(startTimeLabel)
                if !displayEvent.durationLabel.isEmpty {
                    Text(Strings.Home.durationSuffix(displayEvent.durationLabel))
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var locationRow: some View {
        if locationText != nil || eventCoordinate != nil {
            HStack(spacing: 8) {
                if let label = locationText {
                    Label(label, systemImage: locationIcon)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // Only a pinned or live event has somewhere to send Maps — a
                // location typed as free text is just a name.
                if eventCoordinate != nil {
                    Button(action: openInMaps) {
                        Label(Strings.Event.openInMaps, systemImage: "map.fill")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    // Holds the pill at its natural width so a long location
                    // label truncates instead of squeezing the button.
                    .fixedSize()
                }
            }
        }
    }

    // One row for both, the way the active card pairs "End Signal" with "+30" —
    // the card is a third of the screen, so a full-width button would eat it.
    private var joinRow: some View {
        HStack(spacing: 8) {
            if isOwnEvent {
                avatarStack
                Spacer(minLength: 0)
            } else {
                joinButton
                Spacer(minLength: 0)
                avatarStack
            }
        }
    }

    // Same pill as MyActiveEventCard's extend/end buttons.
    private var joinButton: some View {
        Button(action: toggleJoin) {
            HStack(spacing: 4) {
                Image(systemName: isJoined ? "checkmark.circle.fill" : "person.badge.plus")
                Text(isJoined ? Strings.Event.joined : Strings.Event.join)
            }
            .font(.subheadline.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isJoined ? Color.accentColor.opacity(0.15) : Color.accentColor)
            .foregroundColor(isJoined ? .accentColor : .white)
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
        .disabled(isJoining)
    }

    @ViewBuilder
    private var avatarStack: some View {
        if !joinedUsers.isEmpty, !isAttendeeListExpanded {
            JoinedAvatarStack(users: joinedUsers)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) { isAttendeeListExpanded = true }
                }
        }
    }

    // The stacked avatars in joinRow open this; tapping a face closes it again.
    @ViewBuilder
    private var boolersSection: some View {
        if !joinedUsers.isEmpty, isAttendeeListExpanded {
            JoinedBoolersRow(users: joinedUsers) {
                withAnimation(.easeInOut(duration: 0.25)) { isAttendeeListExpanded = false }
            }
        }
    }

    // MARK: - Joining

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

    // MARK: - Labels

    // Takes time remaining, so the thresholds run the opposite way from a
    // fill-up bar: the less that's left, the more urgent the color.
    private func remainingColor(_ remaining: Double) -> Color {
        if remaining < 0.25 { return .red }
        if remaining < 0.5 { return .orange }
        return .accentColor
    }

    private var startTimeLabel: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let time = formatter.string(from: displayEvent.startTime.dateValue())
        if Calendar.current.isDateInTomorrow(displayEvent.startTime.dateValue()) {
            return Strings.Event.tomorrowAt(time)
        }
        return time
    }

    // With the map thumbnail gone, a live event with no label of its own still
    // needs to say that it's moving rather than show nothing at all.
    private var locationText: String? {
        if let label = displayEvent.locationLabel, !label.isEmpty { return label }
        return displayEvent.locationType == .live ? Strings.Event.liveLocationLabel : nil
    }

    // Reads off displayEvent rather than the event passed in, so a live event
    // hands Maps where the creator is now instead of where they started.
    private var eventCoordinate: CLLocationCoordinate2D? {
        guard let geoPoint = displayEvent.locationCoordinate else { return nil }
        return CLLocationCoordinate2D(latitude: geoPoint.latitude, longitude: geoPoint.longitude)
    }

    private func openInMaps() {
        guard let coordinate = eventCoordinate else { return }
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = locationText ?? displayEvent.activity
        mapItem.openInMaps()
    }

    private var locationIcon: String {
        switch displayEvent.locationType {
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
    var size: CGFloat = EventAnnotationView.defaultSize

    static let defaultSize: CGFloat = 44
    // The pin keeps its proportions when it's blown up for a focused event, so
    // callers can work out how tall the whole thing will be before drawing it.
    static func totalHeight(forIconSize size: CGFloat) -> CGFloat { size * 1.2 }

    private var tailSize: CGFloat { size * 0.2 }

    var body: some View {
        VStack(spacing: 0) {
            EventIconView(photoURL: photoURL, label: label, size: size)
                .overlay(Circle().stroke(Color.white, lineWidth: max(2, size * 0.02)))
                .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
            Image(systemName: "triangle.fill")
                .font(.system(size: tailSize))
                .foregroundColor(.accentColor)
                .rotationEffect(.degrees(180))
                .offset(y: -tailSize / 3)
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