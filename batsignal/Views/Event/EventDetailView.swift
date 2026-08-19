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
    @State private var joinedUsers: [PublicProfile] = []
    @State private var isJoining = false
    @State private var isAttendeeListExpanded = false
    @State private var contentHeight: CGFloat?
    @State private var now = Date()
    @State private var activeReport: ReportTarget?
    @State private var showBlockConfirmation = false
    @State private var moderationError: String?

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
            .background(Blipper.surface)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
            )
            .sheet(item: $activeReport) { target in
                ReportSheet(target: target)
            }
            .alert(
                Strings.Moderation.blockTitle(creatorName ?? Strings.Friends.someone),
                isPresented: $showBlockConfirmation
            ) {
                Button(Strings.Common.cancel, role: .cancel) {}
                Button(Strings.Moderation.blockConfirm, role: .destructive) {
                    Task {
                        do {
                            try await ModerationService.shared.block(userId: displayEvent.creatorId)
                        } catch {
                            moderationError = Strings.Moderation.blockFailed
                        }
                    }
                }
            } message: {
                Text(Strings.Moderation.blockMessage)
            }
            .alert(
                Strings.Moderation.blockFailed,
                isPresented: Binding(
                    get: { moderationError != nil },
                    set: { if !$0 { moderationError = nil } }
                )
            ) {
                Button(Strings.Common.ok, role: .cancel) { moderationError = nil }
            }
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
            .hidingScrollEdgeEffect()
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
                    .font(.blipperUI(.subheadline))
                    .foregroundColor(Blipper.textMuted)
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
                        .font(.blipperUI(.caption1, weight: 600))
                        .foregroundColor(.accentColor)
                }
                Text(displayEvent.activity)
                    .font(.blipperUI(.headline, weight: 600))
            }

            Spacer(minLength: 8)

            if !displayEvent.isActive, let eta = displayEvent.startsInLabel {
                Text(eta)
                    .font(.blipperUI(.caption1, weight: 600))
                    .foregroundColor(.accentColor)
            }

            // A visible control rather than a long press: this is the reporting
            // route for a signal's words and photo, and it has to be findable.
            if !isOwnEvent {
                moderationMenu
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

    private var moderationMenu: some View {
        Menu {
            Button {
                activeReport = ReportTarget.event(displayEvent)
            } label: {
                Label(Strings.Moderation.reportEvent, systemImage: "flag")
            }
            Button {
                activeReport = ReportTarget.user(displayEvent.creatorId)
            } label: {
                Label(Strings.Moderation.reportUser, systemImage: "person.crop.circle.badge.exclamationmark")
            }
            Button(role: .destructive) {
                showBlockConfirmation = true
            } label: {
                Label(Strings.Moderation.block, systemImage: "hand.raised")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
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
                        .tint(Blipper.amber)
                    if let label = displayEvent.timeRemainingLabel {
                        Text(label)
                            .font(.blipperUI(.caption1))
                            .foregroundColor(Blipper.textMuted)
                    }
                }
            } else if let label = displayEvent.durationVagueLabel {
                Label(label, systemImage: "clock")
                    .font(.blipperUI(.caption1))
                    .foregroundColor(Blipper.textMuted)
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text(startTimeLabel)
                if !displayEvent.durationLabel.isEmpty {
                    Text(Strings.Home.durationSuffix(displayEvent.durationLabel))
                }
            }
            .font(.blipperUI(.subheadline))
            .foregroundColor(Blipper.textMuted)
        }
    }

    @ViewBuilder
    private var locationRow: some View {
        if locationText != nil || eventCoordinate != nil {
            HStack(spacing: 8) {
                if let label = locationText {
                    Label(label, systemImage: locationIcon)
                        .font(.blipperUI(.subheadline))
                        .foregroundColor(Blipper.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // Only a pinned or live event has somewhere to send Maps — a
                // location typed as free text is just a name.
                if eventCoordinate != nil {
                    Button(action: openInMaps) {
                        Label(Strings.Event.openInMaps, systemImage: "map.fill")
                            .font(.blipperUI(.caption1, weight: 600))
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
            .font(.blipperUI(.subheadline, weight: 600))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isJoined ? Color.accentColor.opacity(0.15) : Color.accentColor)
            .foregroundColor(isJoined ? Color.accentColor : Blipper.onMoonlight)
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

    // Scoped to the event because the people on someone else's signal aren't
    // necessarily this user's friends, and so aren't readable directly.
    private func loadJoinedUsers() async {
        guard let eventId = event.id,
              let users = try? await FriendService().fetchProfiles(ids: joinedUserIds, eventId: eventId)
        else { return }
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
                joinedUsers.append(me.publicProfile)
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
                            joinedUsers.append(me.publicProfile)
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
                .fill(Blipper.onRoseLight)
                .frame(width: 7, height: 7)
                .opacity(opacity)
            Text(Strings.Event.live)
                .font(.blipperUI(.caption2, weight: 600))
                .foregroundStyle(Blipper.onRoseLight)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        // Rose rather than amber: live is a status, and status is the one thing
        // the rose accent is reserved for.
        .background(Blipper.rose)
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
    // The size to draw at, joins already accounted for — see joinedSize(base:),
    // which is what callers are expected to run their base size through. The
    // growth deliberately isn't applied in here: the map frames the focused pin
    // by measuring totalHeight(forIconSize:) against the strip the carousel
    // leaves uncovered, and a pin that quietly drew itself larger than the size
    // it was handed would put that arithmetic out by however many people had
    // joined.
    var size: CGFloat = EventAnnotationView.defaultSize
    // How many people have joined the event this pin stands for. Drives the
    // glow only — the circle's own growth comes in through `size`.
    var joinCount: Int = 0

    static let defaultSize: CGFloat = 44
    // The pin keeps its proportions when it's blown up for a focused event, so
    // callers can work out how tall the whole thing will be before drawing it.
    static func totalHeight(forIconSize size: CGFloat) -> CGFloat { size * 1.2 }

    // MARK: Joins

    // The headcount at which a pin stops growing. Set for a friend-group app:
    // most signals top out around here, so the scale spends its whole range on
    // the counts that actually happen rather than saving most of it for crowds
    // that never turn up.
    static let joinCap = 5

    /// 0 when nobody has joined, 1 at the cap. Square root rather than linear
    /// so the first person to join produces the biggest single jump — going
    /// from nobody to somebody is the moment worth seeing across a map, and the
    /// difference between the fourth and fifth is not.
    static func joinIntensity(joinCount: Int) -> Double {
        sqrt(min(Double(joinCount) / Double(joinCap), 1))
    }

    /// What to pass as `size`: a base size grown by however many have joined.
    ///
    /// Far gentler than the glow's growth, and on purpose. The haze is
    /// atmosphere — it can nearly double without taking anything from its
    /// neighbours — whereas the circle is a hard shape that starts overlapping
    /// the pins around it the moment it gets greedy. A third is enough to read
    /// as bigger when two pins sit side by side: the 44pt default lands at 57.
    static func joinedSize(base: CGFloat, joinCount: Int) -> CGFloat {
        base * (1 + 0.3 * joinIntensity(joinCount: joinCount))
    }

    private var joinIntensity: Double { Self.joinIntensity(joinCount: joinCount) }

    private var tailSize: CGFloat { size * 0.2 }

    // MARK: Glow

    // Scaled off the pin rather than fixed, so the hero pin — which can be five
    // times the default size — glows like a bigger light instead of wearing the
    // same thin rim a 44pt pin does. Joins then widen that in proportion, on
    // top of the growth they already gave `size`, so a crowded pin gains a
    // halo out of step with its circle rather than just a scaled copy of the
    // whole pin — which would read as nearer, not busier.
    private var hazeRadius: CGFloat {
        max(size * 0.28, 10) * (1 + 0.9 * joinIntensity)
    }

    // Never falls below blipperGlow's own 0.35, so an unjoined pin looks
    // exactly as it always has and joining only ever adds.
    private var hazeOpacity: Double { 0.35 + 0.30 * joinIntensity }

    // A second, wider, fainter halo layered outside the first. Raising the
    // core's opacity alone stops reading as "brighter" past about 0.6 — it just
    // flattens into a colored disc — whereas a bloom around it keeps a lit
    // center and gives the light somewhere to spread to. Invisible at zero
    // joiners, so it costs an unjoined pin nothing.
    private var bloomOpacity: Double { 0.28 * joinIntensity }

    var body: some View {
        VStack(spacing: 0) {
            // The ring is EventIconView's own amber border now — a second ring
            // here would only double it.
            EventIconView(photoURL: photoURL, label: label, size: size, style: .signal)
            // The tail is the pin's body, so it takes whatever the icon is
            // filled with and the two read as one shape.
            //
            // Drawn behind the circle: it overlaps by a third so the two join
            // without a seam, and painted on top that overlap sat as an amber
            // wedge across the bottom of a photo. zIndex rather than reordering
            // or moving it into a background, because the tail has to keep
            // contributing its height to the stack — the map anchors these at
            // .bottom so the tail's tip is what marks the coordinate, and
            // totalHeight(forIconSize:) counts on it too.
            Image(systemName: "triangle.fill")
                .font(.system(size: tailSize))
                .foregroundColor(EventIconStyle.signal.fill)
                .rotationEffect(.degrees(180))
                .offset(y: -tailSize / 3)
                .zIndex(-1)
        }
        // All three cast from the whole pin rather than from the circle alone.
        // A shadow always draws behind the view it's attached to, so hanging
        // them here puts them behind the tail as well — on the circle they were
        // being painted over it, which is what made the tail look like it was
        // sitting behind the outline in a haze. As a bonus the haze now traces
        // the pin's real silhouette, tail included, instead of stopping at the
        // circle. The black shadow is what holds the pin off the map.
        //
        // Order matters: each shadow is cast by everything above it, so the
        // core goes on first and the bloom spreads that already-lit shape
        // outward. The black one stays last, tight enough not to dirty either.
        .blipperGlow(Blipper.amber, radius: hazeRadius, opacity: hazeOpacity)
        .blipperGlow(Blipper.amber, radius: hazeRadius * 1.8, opacity: bloomOpacity)
        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
        // Joins arrive over a live Firestore listener while the map is open, so
        // this is usually someone else answering the signal in front of you.
        // Blooming up to the new size beats snapping to it. Keyed on the count
        // rather than on the size, which also catches the circle's own growth:
        // `size` is handed in already grown, so it changes in the same pass the
        // count does and swells under this animation too. The focused pin's
        // resize is deliberately not covered — its size moves with the card,
        // not the headcount, and it has the camera animating alongside it.
        .animation(.easeInOut(duration: 0.45), value: joinCount)
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
                            .font(.blipperUI(.body, weight: 600))
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