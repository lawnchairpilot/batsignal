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
    @State private var selectedEventForDetail: EventDetailSelection?
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
                                height: mapHeight(for: proxy.size.height),
                                onSelectEvent: { event in openEventDetail(for: event) }
                            )

                            homeCarousel
                                .padding(.horizontal, 12)
                                .padding(.bottom, 12)
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
                                    EventCardView(event: event, creatorName: creator?.displayName, isSelected: event.id != nil && event.id == focusedEventId)
                                        .padding(.horizontal)
                                        .opacity(0.6)
                                        .contentShape(Rectangle())
                                        .onTapGesture(count: 2) { openEventDetail(for: event) }
                                        .onTapGesture(count: 1) { handleSingleTap(on: event) }
                                }
                            }
                            .padding(.bottom, 16)
                        }
                    }
                }
            }
            .navigationTitle(Strings.Common.appName)
            .sheet(isPresented: $showCreateEvent) {
                CreateEventView()
            }
            .sheet(item: $selectedEventForDetail) { selection in
                NavigationStack {
                    EventDetailView(
                        event: selection.event,
                        creatorName: selection.creatorName,
                        creatorPhotoURL: selection.creatorPhotoURL
                    )
                    .navigationTitle(selection.event.activity)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(Strings.Common.done) { selectedEventForDetail = nil }
                        }
                    }
                }
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

    private var homeCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .bottom, spacing: 12) {
                Group {
                    if myEventViewModel.activeEvent != nil || myEventViewModel.upcomingEvent != nil {
                        MyActiveEventCard(viewModel: myEventViewModel)
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
                    EventCardView(event: event, creatorName: creator?.displayName)
                        .opacity(0.92)
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.82 }
                        .carouselFocusEffect()
                        .contentShape(Rectangle())
                        .onTapGesture { openEventDetail(for: event) }
                        .id(HomeCarouselSelection.event(event.id ?? ""))
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selectedCarouselItem)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: selectedCarouselItem) { _, newValue in
            focusMapOnCarouselSelection(newValue)
        }
    }

    private func focusMapOnCarouselSelection(_ selection: HomeCarouselSelection?) {
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

    private func handleSingleTap(on event: Event) {
        if event.id != nil && event.id == focusedEventId {
            openEventDetail(for: event)
        } else {
            focusMap(on: event)
        }
    }

    private func focusMap(on event: Event) {
        guard let geoPoint = event.locationCoordinate else { return }
        focusedCoordinate = CLLocationCoordinate2D(latitude: geoPoint.latitude, longitude: geoPoint.longitude)
        focusedEventId = event.id
    }

    private func openEventDetail(for event: Event) {
        guard let id = event.id else { return }
        let creator = friendsViewModel.friends.first { $0.id == event.creatorId }
        selectedEventForDetail = EventDetailSelection(
            id: id,
            event: event,
            creatorName: creator?.displayName,
            creatorPhotoURL: creator?.profilePhotoURL
        )
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
        let label: String? = {
            if let emoji = event.emoji { return emoji }
            guard let name, !name.isEmpty else { return nil }
            let parts = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
            return parts.isEmpty ? nil : parts.uppercased()
        }()
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
            let label: String? = {
                if let emoji = event.emoji { return emoji }
                guard let name = creator?.displayName, !name.isEmpty else { return nil }
                let parts = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
                return parts.isEmpty ? nil : parts.uppercased()
            }()
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

private struct EventDetailSelection: Identifiable {
    let id: String
    let event: Event
    let creatorName: String?
    let creatorPhotoURL: String?
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
