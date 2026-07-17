import SwiftUI
import CoreLocation
internal import FirebaseFirestoreInternal

struct HomeView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject private var viewModel: HomeViewModel
    @EnvironmentObject private var myEventViewModel: MyActiveEventViewModel
    @EnvironmentObject private var friendsViewModel: FriendsViewModel
    @State private var showCreateEvent = false
    @State private var showActiveEventAlert = false
    @State private var focusedCoordinate: CLLocationCoordinate2D?
    @State private var focusedEventId: String?
    @State private var selectedEventForDetail: EventDetailSelection?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // My event (active or upcoming)
                    if myEventViewModel.activeEvent != nil || myEventViewModel.upcomingEvent != nil {
                        MyActiveEventCard(viewModel: myEventViewModel)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    // Friends' event map
                    HomeMapView(
                        annotations: allAnnotations,
                        focusedCoordinate: focusedCoordinate,
                        onSelectEvent: { event in openEventDetail(for: event) }
                    )
                        .padding(.horizontal)
                        .padding(.top, 8)

                    // Friends' active events
                    if viewModel.isLoading {
                        ProgressView().padding(.top, 40)
                    } else if viewModel.events.isEmpty && viewModel.upcomingEvents.isEmpty {
                        ContentUnavailableView(
                            "No signals yet",
                            systemImage: "antenna.radiowaves.left.and.right",
                            description: Text("When your friends post an event, it'll show up here.")
                        )
                        .padding(.top, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            if !viewModel.events.isEmpty {
                                Text("What's happening")
                                    .font(.title3).bold()
                                    .padding(.horizontal)
                                    .padding(.top, 4)
                                ForEach(viewModel.events) { event in
                                    let creator = friendsViewModel.friends.first { $0.id == event.creatorId }
                                    EventCardView(event: event, creatorName: creator?.displayName, creatorPhotoURL: creator?.profilePhotoURL, isSelected: event.id != nil && event.id == focusedEventId)
                                        .padding(.horizontal)
                                        .contentShape(Rectangle())
                                        .onTapGesture(count: 2) { openEventDetail(for: event) }
                                        .onTapGesture(count: 1) { focusMap(on: event) }
                                }
                            }

                            if !viewModel.upcomingEvents.isEmpty {
                                Text("Coming up")
                                    .font(.title3).bold()
                                    .padding(.horizontal)
                                    .padding(.top, viewModel.events.isEmpty ? 4 : 8)
                                ForEach(viewModel.upcomingEvents) { event in
                                    let creator = friendsViewModel.friends.first { $0.id == event.creatorId }
                                    EventCardView(event: event, creatorName: creator?.displayName, creatorPhotoURL: creator?.profilePhotoURL, isSelected: event.id != nil && event.id == focusedEventId)
                                        .padding(.horizontal)
                                        .opacity(0.6)
                                        .contentShape(Rectangle())
                                        .onTapGesture(count: 2) { openEventDetail(for: event) }
                                        .onTapGesture(count: 1) { focusMap(on: event) }
                                }
                            }
                        }
                        .padding(.bottom, 16)
                    }
                }
            }
            .navigationTitle("Bool Signal")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        if authService.currentUser?.activeEventId != nil || myEventViewModel.upcomingEvent != nil {
                            showActiveEventAlert = true
                        } else {
                            showCreateEvent = true
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
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
                            Button("Done") { selectedEventForDetail = nil }
                        }
                    }
                }
            }
            .alert("Signal already active", isPresented: $showActiveEventAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("End your current signal before starting a new one.")
            }
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
        makeAnnotationItems(from: viewModel.events, isActive: true) +
        makeAnnotationItems(from: viewModel.upcomingEvents, isActive: false)
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
                creatorPhotoURL: creator?.profilePhotoURL,
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
