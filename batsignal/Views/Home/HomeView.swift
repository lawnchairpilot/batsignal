import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject private var viewModel: HomeViewModel
    @EnvironmentObject private var myEventViewModel: MyActiveEventViewModel
    @EnvironmentObject private var friendsViewModel: FriendsViewModel
    @State private var showCreateEvent = false
    @State private var showActiveEventAlert = false

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
                                    let creatorName = friendsViewModel.friends.first { $0.id == event.creatorId }?.displayName
                                    NavigationLink(destination: EventDetailView(event: event, creatorName: creatorName)) {
                                        EventCardView(event: event, creatorName: creatorName)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal)
                                }
                            }

                            if !viewModel.upcomingEvents.isEmpty {
                                Text("Coming up")
                                    .font(.title3).bold()
                                    .padding(.horizontal)
                                    .padding(.top, viewModel.events.isEmpty ? 4 : 8)
                                ForEach(viewModel.upcomingEvents) { event in
                                    let creatorName = friendsViewModel.friends.first { $0.id == event.creatorId }?.displayName
                                    NavigationLink(destination: EventDetailView(event: event, creatorName: creatorName)) {
                                        EventCardView(event: event, creatorName: creatorName)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal)
                                    .opacity(0.6)
                                }
                            }
                        }
                        .padding(.bottom, 16)
                    }
                }
            }
            .navigationTitle("Batsignal")
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
            .alert("Signal already active", isPresented: $showActiveEventAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("End your current signal before starting a new one.")
            }
        }
    }
}
