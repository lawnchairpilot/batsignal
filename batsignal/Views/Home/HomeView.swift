import SwiftUI
import CoreLocation
internal import FirebaseFirestoreInternal

struct HomeView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject private var viewModel: HomeViewModel
    @EnvironmentObject private var myEventViewModel: MyActiveEventViewModel
    @EnvironmentObject private var friendsViewModel: FriendsViewModel
    @State private var showCreateEvent = false
    @State private var focusedCoordinate: CLLocationCoordinate2D?
    @State private var focusedEventId: String?
    // Which card is showing its details. Held here rather than inside
    // EventCardView so only one can be open at a time, and so it survives the
    // carousel's LazyHStack recycling cards as they scroll off-screen.
    @State private var expandedEventId: String?
    // Your own card's equivalent. It isn't keyed by event id because the card
    // stands for whichever signal you have — active or upcoming.
    @State private var isOwnCardExpanded = false
    @State private var carouselHeight: CGFloat = 0
    @State private var selectedCarouselItem: HomeCarouselSelection? = .own
    // Drives the recurring "there's more over here" tug, below.
    @State private var nudgeOffset: CGFloat = 0

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                // The map runs edge to edge under the status bar and home
                // indicator, so its own idea of its height — what the hero
                // framing does its arithmetic against — is the safe area plus
                // both insets. The header and carousel stay inside the safe
                // area, laid out over the top of it.
                let mapHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom

                ZStack(alignment: .top) {
                    HomeMapView(
                        annotations: allAnnotations,
                        focusedCoordinate: focusedCoordinate,
                        focusedEventId: focusedEventId,
                        enlargedEventId: enlargedAnnotationId,
                        occludedBottomHeight: carouselHeight + proxy.safeAreaInsets.bottom,
                        height: mapHeight,
                        onSelectEvent: { event in revealCard(for: event) }
                    )
                    .ignoresSafeArea()

                    VStack(spacing: 0) {
                        header

                        Spacer(minLength: 0)

                        // No horizontal padding: a scroll view clips to its
                        // bounds, and insetting it chopped the peeking cards
                        // off in mid-air short of the screen edge. The inset
                        // lives inside the scroll view instead.
                        homeCarousel(
                            availableHeight: proxy.size.height,
                            containerWidth: proxy.size.width
                        )
                            .padding(.bottom, 12)
                            // Measured outside the padding, so this is the
                            // full bite the carousel takes out of the map.
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { carouselHeight = $0 }
                    }
                }
            }
            // The title and profile button ride on the map instead.
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCreateEvent) {
                CreateEventView()
            }
        }
    }

    // Sits on the map rather than in a navigation bar. The profile button keeps
    // a material backing to stay legible over whatever is beneath; the wordmark
    // leans on its own color and haze instead.
    private var header: some View {
        HStack(spacing: 8) {
            Text(Strings.Common.appName)
                .font(.blipperDisplay(.title2, weight: 700))
                // The wordmark sits on the map among the signals it names, so
                // it takes their color rather than the chrome's.
                .foregroundStyle(Blipper.amber)
                // The same haze the map pins wear. With the backdrop gone this
                // is also what holds the wordmark off busy map content.
                .blipperGlow(Blipper.amber)
                // Uneven vertically on purpose. The HStack centres the text's
                // *line box*, but "Blipper" has descenders so its inked glyphs
                // sit below that centre, while the LIVE badge beside it is all
                // caps and has none — so the two don't line up by eye even
                // though the stack has centred them both. More padding at the
                // bottom than the top lifts the glyphs back onto the badge's
                // centre line. The 4pt of lift here is set by eye; measuring the
                // ink against the line box says ~2pt, which read a touch low
                // once the backdrop came off and the glow went on. Retune by
                // eye if the wordmark's face or size changes.
                //
                // The horizontal inset is what keeps the wordmark off the
                // header's own margin now that there's no backdrop shaping it.
                .padding(EdgeInsets(top: 2, leading: 12, bottom: 10, trailing: 12))

            Spacer()

            if hasLiveEvent {
                LiveBadge()
            }

            NavigationLink {
                ProfileView()
            } label: {
                EventIconView(
                    photoURL: authService.currentUser?.profilePhotoURL,
                    label: authService.currentUser?.initials,
                    size: 34
                )
                .padding(3)
                .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel(Strings.Profile.title)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var hasLiveEvent: Bool {
        allAnnotations.contains { $0.isLive }
    }

    // What's left for an expanded card once the header row at the top of the
    // map, the carousel's bottom inset and the card's own chrome are taken out.
    // Cards that need more than this scroll internally rather than growing up
    // under the header.
    private func expandedCardMaxContentHeight(for availableHeight: CGFloat) -> CGFloat {
        max(availableHeight - 140, 180)
    }

    private func homeCarousel(availableHeight: CGFloat, containerWidth: CGFloat) -> some View {
        // Sized here rather than with containerRelativeFrame because the inset
        // below depends on the card width, and the card width would in turn
        // depend on the inset if it were measured against the scroll view.
        let cardWidth = containerWidth * 0.82
        // Half the leftover width at each end, so the first and last cards can
        // come to rest dead centre instead of against an edge. What's left over
        // after the gap is how far their neighbours peek in from the screen
        // edges — which is why the gap is tight.
        let sideInset = max((containerWidth - cardWidth) / 2, 0)

        return ScrollView(.horizontal, showsIndicators: false) {
            // Deliberately not a LazyHStack. The carousel is sized by
            // fixedSize(vertical:), which asks the scroll view for its ideal
            // height — and a lazy stack answers that from the cards it has
            // realized, i.e. your own. Every other card then got clipped to
            // your card's height, at the top, because the stack is bottom
            // aligned. A handful of friends' events don't need laziness anyway.
            HStack(alignment: .bottom, spacing: 8) {
                Group {
                    if myEventViewModel.activeEvent != nil || myEventViewModel.upcomingEvent != nil {
                        MyActiveEventCard(viewModel: myEventViewModel, isExpanded: $isOwnCardExpanded)
                    } else {
                        CreateEventPromptCard(action: { showCreateEvent = true })
                    }
                }
                .opacity(0.92)
                .frame(width: cardWidth)
                .carouselFocusEffect()
                .id(HomeCarouselSelection.own)

                ForEach(viewModel.events) { event in
                    let creator = friendsViewModel.friends.first { $0.id == event.creatorId }
                    EventCardView(
                        event: event,
                        isExpanded: expansionBinding(for: event),
                        creatorName: creator?.displayName,
                        expandedMaxContentHeight: expandedCardMaxContentHeight(for: availableHeight)
                    )
                    .opacity(0.92)
                    .frame(width: cardWidth)
                    .carouselFocusEffect()
                    .id(HomeCarouselSelection.event(event.id ?? ""))
                }
            }
            .scrollTargetLayout()
            .offset(x: nudgeOffset)
        }
        .safeAreaPadding(.horizontal, sideInset)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selectedCarouselItem)
        // carouselFocusEffect already recedes the off-centre cards; the system
        // edge effect on top of that just smears them into the map.
        .hidingScrollEdgeEffect()
        .fixedSize(horizontal: false, vertical: true)
        .task { await runCarouselHint() }
        .onChange(of: selectedCarouselItem) { _, newValue in
            focusMapOnCarouselSelection(newValue)
        }
    }

    // Repeats for as long as the hint still applies — parked on your own card
    // with someone else's sitting just off screen. Swipe away and it falls
    // silent, come back and it picks up again, because the conditions are
    // re-read each time round rather than latched at launch.
    private func runCarouselHint() async {
        // Long enough for the map and cards to settle, so the first movement
        // isn't lost in everything else appearing at once.
        try? await Task.sleep(for: .milliseconds(1500))

        while !Task.isCancelled {
            if shouldHintCarousel {
                await nudgeCarousel()
            }
            try? await Task.sleep(for: .seconds(6))
        }
    }

    private var shouldHintCarousel: Bool {
        // An expanded card or an open sheet means the swipe isn't what you're
        // being asked to think about, so the carousel holds still.
        !viewModel.events.isEmpty
            && selectedCarouselItem == .own
            && !isOwnCardExpanded
            && !showCreateEvent
    }

    // Tugs the carousel a little to the left and lets it spring back, the way
    // it would if you started a swipe and lifted your finger — the peeking card
    // alone doesn't say clearly enough that there's something to swipe to.
    private func nudgeCarousel() async {
        withAnimation(.easeOut(duration: 0.3)) { nudgeOffset = -40 }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { nudgeOffset = 0 }
        // Lets the spring land before the gap to the next tug is counted.
        try? await Task.sleep(for: .milliseconds(500))
    }

    private func focusMapOnCarouselSelection(_ selection: HomeCarouselSelection?) {
        // Swiping past an open card closes it, so the carousel only ever has one
        // expanded card and it's the one you're looking at. Written as "collapse
        // anything that isn't the new selection" rather than "collapse, then
        // expand", so revealCard(for:) setting both in one update can't lose.
        collapseCards(unless: selection)

        switch selection {
        case .event(let id):
            guard let event = viewModel.events.first(where: { $0.id == id }) else { return }
            focusMap(on: event)
        case .own, .none:
            // Swiping back to your own card points the map at your signal, the
            // same way swiping to a friend's card points it at theirs. With no
            // signal yet (the create prompt), or one whose location hasn't
            // landed, clearing the focus hands the map back to its default —
            // your current location.
            if let event = myEventViewModel.activeEvent ?? myEventViewModel.upcomingEvent,
               event.locationCoordinate != nil {
                focusMap(on: event)
            } else {
                focusedCoordinate = nil
                focusedEventId = nil
            }
        }
    }

    // Only touches carousel cards: a card expanded down in the upcoming list
    // isn't in the carousel at all, so scrolling the carousel shouldn't shut it.
    private func collapseCards(unless selection: HomeCarouselSelection?) {
        if isOwnCardExpanded, selection != .own {
            withAnimation(.easeInOut(duration: 0.2)) { isOwnCardExpanded = false }
        }
        if let expandedEventId,
           viewModel.events.contains(where: { $0.id == expandedEventId }),
           selection != .event(expandedEventId) {
            withAnimation(.easeInOut(duration: 0.2)) { self.expandedEventId = nil }
        }
    }

    // Whichever card is open owns the map: your own signal's pin gets the same
    // treatment a friend's does.
    private var enlargedAnnotationId: String? {
        if let expandedEventId { return expandedEventId }
        guard isOwnCardExpanded else { return nil }
        return myEventViewModel.activeEvent?.id ?? myEventViewModel.upcomingEvent?.id
    }

    private func isExpanded(_ event: Event) -> Bool {
        expandedEventId != nil && expandedEventId == event.id
    }

    private func expansionBinding(for event: Event) -> Binding<Bool> {
        Binding(
            get: { isExpanded(event) },
            set: { expandedEventId = $0 ? event.id : nil }
        )
    }

    private func focusMap(on event: Event) {
        guard let geoPoint = event.locationCoordinate else { return }
        focusedCoordinate = CLLocationCoordinate2D(latitude: geoPoint.latitude, longitude: geoPoint.longitude)
        focusedEventId = event.id
    }

    // Tapping a pin brings you to that event's card rather than a sheet: scroll
    // the carousel to it and open it. Setting the selection first lets its
    // onChange close whatever else was open before this opens the new one.
    private func revealCard(for event: Event) {
        guard let id = event.id else { return }
        focusMap(on: event)
        if myEventViewModel.activeEvent?.id == id || myEventViewModel.upcomingEvent?.id == id {
            selectedCarouselItem = .own
            withAnimation(.easeInOut(duration: 0.2)) { isOwnCardExpanded = true }
            return
        }
        if viewModel.events.contains(where: { $0.id == id }) {
            selectedCarouselItem = .event(id)
        }
        withAnimation(.easeInOut(duration: 0.2)) { expandedEventId = id }
    }

    private var allAnnotations: [EventAnnotationItem] {
        // recipientIds never contains the creator themself, so listenToVisibleEvents
        // (which viewModel.events/upcomingEvents come from) never surfaces this
        // user's own event — without this it fell back to the plain blue user dot.
        // Declaration order does NOT control stacking here — MapKit re-sorts
        // annotation views itself, so raising the focused pin is done through
        // the map's selection binding instead (see HomeMapView).
        (ownEventAnnotation.map { [$0] } ?? []) +
        makeAnnotationItems(from: viewModel.events, isActive: true) +
        makeAnnotationItems(from: viewModel.upcomingEvents, isActive: false)
    }

    private var ownEventAnnotation: EventAnnotationItem? {
        guard let event = myEventViewModel.activeEvent,
              let id = event.id,
              let geoPoint = event.locationCoordinate else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: geoPoint.latitude, longitude: geoPoint.longitude)
        let name = authService.currentUser?.displayName
        let label = event.emoji ?? authService.currentUser?.initials
        return EventAnnotationItem(
            id: id,
            coordinate: coordinate,
            label: label,
            creatorPhotoURL: annotationPhotoURL(for: event, creatorPhotoURL: authService.currentUser?.profilePhotoURL),
            isLive: event.locationType == .live,
            isActive: true,
            event: event,
            creatorName: name
        )
    }

    // EventIconView draws a photo in preference to a label, so the photo and the
    // label can't pick their fallbacks independently: a creator's profile photo
    // left in place here outranks the event's own emoji and silently swallows
    // it. What the event says about itself comes first — its image, then its
    // emoji — and the creator's photo is only reached when it says neither.
    private func annotationPhotoURL(for event: Event, creatorPhotoURL: String?) -> String? {
        if let imageURL = event.imageURL { return imageURL }
        return event.emoji == nil ? creatorPhotoURL : nil
    }

    private func makeAnnotationItems(from events: [Event], isActive: Bool) -> [EventAnnotationItem] {
        events.compactMap { event in
            guard let id = event.id, let geoPoint = event.locationCoordinate else { return nil }
            let coordinate = CLLocationCoordinate2D(latitude: geoPoint.latitude, longitude: geoPoint.longitude)
            let creator = friendsViewModel.friends.first { $0.id == event.creatorId }
            let label = event.emoji ?? creator?.initials
            return EventAnnotationItem(
                id: id,
                coordinate: coordinate,
                label: label,
                creatorPhotoURL: annotationPhotoURL(for: event, creatorPhotoURL: creator?.profilePhotoURL),
                isLive: event.locationType == .live,
                isActive: isActive,
                event: event,
                creatorName: creator?.displayName
            )
        }
    }
}

private enum HomeCarouselSelection: Hashable {
    case own
    case event(String)
}

// Shrinks and dims a carousel card the further it drifts from center, so
// off-focus cards read as physically receding — the same tactile cue the
// native wheel picker (EventDurationWheel) gives unselected rows for free.
private extension View {
    func carouselFocusEffect() -> some View {
        visualEffect { effect, proxy in
            let frame = proxy.frame(in: .scrollView)
            let scrollWidth = proxy.bounds(of: .scrollView)?.width ?? frame.width
            let distance = abs(frame.midX - scrollWidth / 2)
            let maxDistance = scrollWidth / 2 + frame.width / 2
            let fraction = maxDistance > 0 ? min(distance / maxDistance, 1) : 0
            return effect
                .scaleEffect(1 - fraction * 0.12)
                .opacity(1 - fraction * 0.55)
        }
    }
}

private struct CreateEventPromptCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.headline)
                    // Amber because this card stands in for the signal you
                    // don't have yet — it's the one card in the carousel with
                    // no icon of its own to carry the colour.
                    .foregroundColor(Blipper.amber)
                FadingHeadline(text: Strings.Home.createSignalTitle, background: Blipper.surface)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Blipper.surface)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
