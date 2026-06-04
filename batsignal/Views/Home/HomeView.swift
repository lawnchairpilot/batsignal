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

                    // My active event — shown at top if one exists
                    if myEventViewModel.activeEvent != nil {
                        MyActiveEventCard(viewModel: myEventViewModel)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    // Friends' events
                    if viewModel.isLoading {
                        ProgressView().padding(.top, 40)
                    } else if viewModel.events.isEmpty {
                        ContentUnavailableView(
                            "No signals yet",
                            systemImage: "antenna.radiowaves.left.and.right",
                            description: Text("When your friends post an event, it'll show up here.")
                        )
                        .padding(.top, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
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
                        .padding(.bottom, 16)
                    }
                }
            }
            .navigationTitle("Batsignal")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        if authService.currentUser?.activeEventId != nil {
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
