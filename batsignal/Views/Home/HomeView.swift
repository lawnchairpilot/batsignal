import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = HomeViewModel()
    @State private var showCreateEvent = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.events.isEmpty {
                    ContentUnavailableView(
                        "No signals yet",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("When your friends post an event, it'll show up here.")
                    )
                } else {
                    List(viewModel.events) { event in
                        NavigationLink(destination: EventDetailView(event: event)) {
                            EventCardView(event: event)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                    }
                    .listStyle(.plain)
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
