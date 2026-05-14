import SwiftUI

struct MainTabView: View {
    @StateObject private var myEventViewModel = MyActiveEventViewModel()

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
        .onAppear { myEventViewModel.startListening() }
    }
}
