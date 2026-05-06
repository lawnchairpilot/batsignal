import SwiftUI

struct FriendsView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = FriendsViewModel()
    @State private var showAddFriend = false

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.incomingRequests.isEmpty {
                    Section("Requests") {
                        ForEach(viewModel.incomingRequests) { request in
                            FriendRequestRow(request: request) { accept in
                                Task { await viewModel.respond(to: request, accept: accept) }
                            }
                        }
                    }
                }

                Section("Friends") {
                    if viewModel.friends.isEmpty {
                        Text("No friends yet — add some!")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.friends) { friend in
                            Text(friend.displayName)
                        }
                    }
                }
            }
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showAddFriend = true }) {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendView(viewModel: viewModel)
            }
            .task {
                let ids = authService.currentUser?.friends ?? []
                await viewModel.loadFriends(ids: ids)
            }
        }
    }
}

struct FriendRequestRow: View {
    let request: FriendRequest
    let onRespond: (Bool) -> Void

    var body: some View {
        HStack {
            Text(request.fromUserId)  // TODO: resolve to display name
                .font(.subheadline)
            Spacer()
            Button("Accept") { onRespond(true) }
                .buttonStyle(.borderedProminent).controlSize(.small)
            Button("Decline") { onRespond(false) }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }
}
