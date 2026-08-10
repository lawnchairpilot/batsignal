import SwiftUI

// Home is the whole app now — profile hangs off its toolbar — so this exists
// to own the view models and their listeners above whatever is on screen.
struct RootView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var myEventViewModel = MyActiveEventViewModel()
    @StateObject private var homeViewModel = HomeViewModel()
    @StateObject private var friendsViewModel = FriendsViewModel()

    var body: some View {
        HomeView()
            .environmentObject(myEventViewModel)
            .environmentObject(homeViewModel)
            .environmentObject(friendsViewModel)
            .onAppear {
                startAllListeners()
            }
            // Fires once the user document loads from Firestore — handles auth timing race
            .onChange(of: authService.currentUser?.id) { _, _ in
                startAllListeners()
            }
            // Update active event listener when user's activeEventId changes
            .onChange(of: authService.currentUser?.activeEventId) { _, newId in
                myEventViewModel.startListening(activeEventId: newId)
            }
            // Re-sync feed and friends list when the friends array changes
            .onChange(of: authService.currentUser?.friends) { _, newIds in
                let ids = newIds ?? []
                let radius = authService.currentUser?.maxEventRadius
                friendsViewModel.reloadFriends(ids: ids)
                homeViewModel.startListening(userId: authService.currentUser?.id ?? "", maxRadius: radius)
            }
    }

    private func startAllListeners() {
        let friendIds = authService.currentUser?.friends ?? []
        let radius = authService.currentUser?.maxEventRadius
        myEventViewModel.startListening(activeEventId: authService.currentUser?.activeEventId)
        homeViewModel.startListening(userId: authService.currentUser?.id ?? "", maxRadius: radius)
        friendsViewModel.startListening(friendIds: friendIds)
    }
}
