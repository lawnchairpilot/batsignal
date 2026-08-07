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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // Friends' event map, with my event (or a prompt to create one) overlaid on top
                    ZStack(alignment: .bottom) {
                        HomeMapView(
                            annotations: allAnnotations,
                            focusedCoordinate: focusedCoordinate,
                            onSelectEvent: { event in openEventDetail(for: event) }
                        )

                        Group {
                            if myEventViewModel.activeEvent != nil || myEventViewModel.upcomingEvent != nil {
                                MyActiveEventCard(viewModel: myEventViewModel)
                            } else {
                                CreateEventPromptCard(action: { showCreateEvent = true })
                            }
                        }
                        .padding(12)
                        .opacity(0.92)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Friends' active events
                    if viewModel.isLoading {
                        ProgressView().padding(.top, 40)
                    } else if viewModel.events.isEmpty && viewModel.upcomingEvents.isEmpty {
                        ContentUnavailableView(
                            Strings.Home.emptyStateTitle,
                            systemImage: "antenna.radiowaves.left.and.right",
                            description: Text(Strings.Home.emptyStateDescription)
                        )
                        .padding(.top, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            if !viewModel.events.isEmpty {
                                Text(Strings.Home.whatsHappening)
                                    .font(.title3).bold()
                                    .padding(.horizontal)
                                    .padding(.top, 4)
                                ForEach(viewModel.events) { event in
                                    let creator = friendsViewModel.friends.first { $0.id == event.creatorId }
                                    EventCardView(event: event, creatorName: creator?.displayName, isSelected: event.id != nil && event.id == focusedEventId)
                                        .padding(.horizontal)
                                        .contentShape(Rectangle())
                                        .onTapGesture(count: 2) { openEventDetail(for: event) }
                                        .onTapGesture(count: 1) { handleSingleTap(on: event) }
                                }
                            }

                            if !viewModel.upcomingEvents.isEmpty {
                                Text(Strings.Home.comingUp)
                                    .font(.title3).bold()
                                    .padding(.horizontal)
                                    .padding(.top, viewModel.events.isEmpty ? 4 : 8)
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
                        }
                        .padding(.bottom, 16)
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
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.Home.createSignalTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(Strings.Home.createSignalSubtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
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
