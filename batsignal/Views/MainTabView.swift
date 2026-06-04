import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var myEventViewModel = MyActiveEventViewModel()
    @StateObject private var homeViewModel = HomeViewModel()
    @StateObject private var friendsViewModel = FriendsViewModel()

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "antenna.radiowaves.left.and.right")
                }

            FriendsView()
                .tabItem {
                    Label("Friends", systemImage: "person.2")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
                }
        }
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
            homeViewModel.startListening(friendIds: ids, maxRadius: radius)
        }
    }

    private func startAllListeners() {
        let friendIds = authService.currentUser?.friends ?? []
        let radius = authService.currentUser?.maxEventRadius
        myEventViewModel.startListening(activeEventId: authService.currentUser?.activeEventId)
        homeViewModel.startListening(friendIds: friendIds, maxRadius: radius)
        friendsViewModel.startListening(friendIds: friendIds)
    }
}
