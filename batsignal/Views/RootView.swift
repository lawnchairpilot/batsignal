import SwiftUI

// Home is the whole app now — profile hangs off its toolbar — so this exists
// to own the view models and their listeners above whatever is on screen.
struct RootView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.scenePhase) private var scenePhase
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
            // Fires once the user document loads from Firestore — handles auth
            // timing race — and again with no id when the account goes away,
            // which is what tears the listeners back down.
            .onChange(of: authService.currentUser?.id) { _, _ in
                startAllListeners()
            }
            // Signing out clears the user document too, but not always before
            // the credentials go, so auth loss is its own teardown trigger.
            .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                if !isAuthenticated { stopAllListeners() }
            }
            // Timers don't run while backgrounded, so what's on the map is as
            // stale as the time spent away until this re-derives it.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { homeViewModel.refreshNow() }
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

    // Without a signed-in user behind them these queries are only rejected —
    // starting them against an empty id was how signing out ended up attaching
    // a fresh set of listeners that could do nothing but fail on permissions.
    private func startAllListeners() {
        guard let user = authService.currentUser, let userId = user.id else {
            stopAllListeners()
            return
        }
        myEventViewModel.startListening(activeEventId: user.activeEventId)
        homeViewModel.startListening(userId: userId, maxRadius: user.maxEventRadius)
        friendsViewModel.startListening(friendIds: user.friends)
        ModerationService.shared.startListening()
    }

    // Firestore keeps serving an attached listener after sign-out, so anything
    // left open fails with a permission error the moment the credentials go.
    // That's the noise in the log when an account is deleted, and it reads like
    // the deletion broke something when nothing actually went wrong.
    private func stopAllListeners() {
        myEventViewModel.stopListening()
        homeViewModel.stopListening()
        friendsViewModel.stopListening()
        ModerationService.shared.stopListening()
    }
}
