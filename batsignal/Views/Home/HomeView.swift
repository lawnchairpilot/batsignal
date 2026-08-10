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

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {

                        // Friends' event map, with my event and friends' current events as cards overlaid on top
                        ZStack(alignment: .bottom) {
                            HomeMapView(
                                annotations: allAnnotations,
                                focusedCoordinate: focusedCoordinate,
                                focusedEventId: focusedEventId,
                                enlargedEventId: enlargedAnnotationId,
                                occludedBottomHeight: carouselHeight,
                                height: mapHeight(for: proxy.size.height),
                                onSelectEvent: { event in revealCard(for: event) }
                            )

                            homeCarousel(availableHeight: proxy.size.height)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 12)
                                // Measured outside the padding, so this is the
                                // full bite the carousel takes out of the map.
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { carouselHeight = $0 }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

                        // Friends' upcoming events
                        if viewModel.isLoading {
                            ProgressView().padding(.top, 40)
                        } else if viewModel.events.isEmpty && viewModel.upcomingEvents.isEmpty {
                            ContentUnavailableView(
                                Strings.Home.emptyStateTitle,
                                systemImage: "antenna.radiowaves.left.and.right",
                                description: Text(Strings.Home.emptyStateDescription)
                            )
                            .padding(.top, 40)
                        } else if !viewModel.upcomingEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(Strings.Home.comingUp)
                                    .font(.title3).bold()
                                    .padding(.horizontal)
                                    .padding(.top, 4)
                                ForEach(viewModel.upcomingEvents) { event in
                                    let creator = friendsViewModel.friends.first { $0.id == event.creatorId }
                                    EventCardView(
                                        event: event,
                                        isExpanded: expansionBinding(for: event),
                                        creatorName: creator?.displayName,
                                        isSelected: event.id != nil && event.id == focusedEventId,
                                        onCompactTap: { handleSingleTap(on: event) }
                                    )
                                    .padding(.horizontal)
                                    .opacity(isExpanded(event) ? 1 : 0.6)
                                }
                            }
                            .padding(.bottom, 16)
                        }
                    }
                }
                // The map sits flush against the navigation bar, so everything
                // in the top band of the page — including an expanded card that
                // has grown up off the map's bottom edge — gets iOS's scroll
                // edge effect painted over it and fades out. The map is opaque
                // enough to carry the title on its own, so turn it off.
                .scrollEdgeEffectHidden(true, for: .top)
            }
            .navigationTitle(Strings.Common.appName)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        EventIconView(
                            photoURL: authService.currentUser?.profilePhotoURL,
                            label: authService.currentUser?.initials,
                            size: 30
                        )
                    }
                    .accessibilityLabel(Strings.Profile.title)
                }
            }
            .sheet(isPresented: $showCreateEvent) {
                CreateEventView()
            }
        }
    }

    // Lets the map claim the full screen whenever there's no upcoming-events
    // list that needs room below it, instead of leaving dead space under the
    // carousel — including the "no signals" empty state, which is small
    // enough to just sit in whatever space is left. Only the upcoming list
    // (which can be long) keeps the map pinned to its standard height.
    private func mapHeight(for availableHeight: CGFloat) -> CGFloat {
        let standardHeight: CGFloat = 340
        guard !viewModel.isLoading, viewModel.upcomingEvents.isEmpty else { return standardHeight }
        return max(standardHeight, availableHeight - 24)
    }

    // What's left of the map for an expanded card, once its own 16pt padding,
    // the carousel's bottom inset and a little clearance from the map's top
    // edge are taken out. Cards that need more than this scroll internally
    // rather than growing up under the navigation bar.
    private func expandedCardMaxContentHeight(for availableHeight: CGFloat) -> CGFloat {
        max(mapHeight(for: availableHeight) - 76, 180)
    }

    private func homeCarousel(availableHeight: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // Deliberately not a LazyHStack. The carousel is sized by
            // fixedSize(vertical:), which asks the scroll view for its ideal
            // height — and a lazy stack answers that from the cards it has
            // realized, i.e. your own. Every other card then got clipped to
            // your card's height, at the top, because the stack is bottom
            // aligned. A handful of friends' events don't need laziness anyway.
            HStack(alignment: .bottom, spacing: 12) {
                Group {
                    if myEventViewModel.activeEvent != nil || myEventViewModel.upcomingEvent != nil {
                        MyActiveEventCard(viewModel: myEventViewModel, isExpanded: $isOwnCardExpanded)
                    } else {
                        CreateEventPromptCard(action: { showCreateEvent = true })
                    }
                }
                .opacity(0.92)
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.82 }
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
                    .containerRelativeFrame(.horizontal) { width, _ in width * 0.82 }
                    .carouselFocusEffect()
                    .id(HomeCarouselSelection.event(event.id ?? ""))
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selectedCarouselItem)
        // carouselFocusEffect already recedes the off-centre cards; the system
        // edge effect on top of that just smears them into the map.
        .scrollEdgeEffectHidden()
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: selectedCarouselItem) { _, newValue in
            focusMapOnCarouselSelection(newValue)
        }
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

    // A card down in the upcoming list is far enough from the map that tapping
    // it once is more likely to mean "where is that?" than "tell me more", so
    // the first tap only points the map at it and the second one opens it.
    private func handleSingleTap(on event: Event) -> Bool {
        if event.id != nil && event.id == focusedEventId { return true }
        focusMap(on: event)
        return false
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
            creatorPhotoURL: event.imageURL ?? authService.currentUser?.profilePhotoURL,
            isLive: event.locationType == .live,
            isActive: true,
            event: event,
            creatorName: name
        )
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
                creatorPhotoURL: event.imageURL ?? creator?.profilePhotoURL,
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
                    .foregroundColor(.accentColor)
                FadingHeadline(text: Strings.Home.createSignalTitle, background: Color(.secondarySystemBackground))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
