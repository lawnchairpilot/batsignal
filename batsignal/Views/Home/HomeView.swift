import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject private var myEventViewModel: MyActiveEventViewModel
    @State private var showCreateEvent = false

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
                        VStack(spacing: 12) {
                            ForEach(viewModel.events) { event in
                                NavigationLink(destination: EventDetailView(event: event)) {
                                    EventCardView(event: event)
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
                    Button(action: { showCreateEvent = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showCreateEvent) {
                CreateEventView()
            }
            .task {
                let friendIds = authService.currentUser?.friends ?? []
                let radius = authService.currentUser?.maxEventRadius
                await viewModel.loadEvents(friendIds: friendIds, maxRadius: radius)
            }
        }
    }
}
