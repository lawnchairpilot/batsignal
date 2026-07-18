import SwiftUI

struct FriendsView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject private var viewModel: FriendsViewModel
    @State private var showAddFriend = false

    var body: some View {
        NavigationStack {
            List {
                // Incoming requests
                if !viewModel.incomingRequests.isEmpty {
                    Section(Strings.Friends.requestsSectionHeader) {
                        ForEach(viewModel.incomingRequests) { request in
                            IncomingRequestRow(
                                request: request,
                                senderName: viewModel.senderNames[request.fromUserId]
                            ) { accept in
                                Task { await viewModel.respond(to: request, accept: accept) }
                            }
                        }
                    }
                }

                // Outgoing pending requests
                if !viewModel.outgoingRequests.isEmpty {
                    Section(Strings.Friends.pendingSectionHeader) {
                        ForEach(viewModel.outgoingRequests) { request in
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundColor(.secondary)
                                Text(viewModel.recipientNames[request.toUserId] ?? Strings.Friends.pendingEllipsis)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(Strings.Friends.requestSent)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Friends list
                Section(Strings.Friends.title) {
                    if viewModel.isLoading {
                        ProgressView()
                    } else if viewModel.friends.isEmpty {
                        Text(Strings.Friends.noFriendsYet)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.friends) { friend in
                            HStack(spacing: 12) {
                                Image(systemName: "person.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(friend.displayName)
                                        .font(.subheadline).bold()
                                    if !friend.phoneNumber.isEmpty {
                                        Text(friend.phoneNumber)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle(Strings.Friends.title)
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
        }
    }
}

struct IncomingRequestRow: View {
    let request: FriendRequest
    let senderName: String?
    let onRespond: (Bool) -> Void

    var body: some View {
        HStack {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(senderName ?? Strings.Friends.someone)
                    .font(.subheadline).bold()
                Text(Strings.Friends.wantsToBeFriends)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(Strings.Friends.accept) { onRespond(true) }
                .buttonStyle(.borderedProminent).controlSize(.small)
            Button(Strings.Friends.decline) { onRespond(false) }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }
}
