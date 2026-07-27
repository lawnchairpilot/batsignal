import SwiftUI

enum FriendsTab {
    case friends, groups
}

struct FriendsView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject private var viewModel: FriendsViewModel
    @StateObject private var groupsViewModel = GroupsViewModel()
    @State private var selectedTab: FriendsTab = .friends
    @State private var showAddFriend = false
    @State private var showCreateGroup = false
    @State private var editingGroup: FriendGroup?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text(Strings.Friends.title).tag(FriendsTab.friends)
                    Text(Strings.Groups.title).tag(FriendsTab.groups)
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedTab {
                case .friends:
                    friendsList
                case .groups:
                    groupsList
                }
            }
            .navigationTitle(Strings.Friends.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    switch selectedTab {
                    case .friends:
                        Button(action: { showAddFriend = true }) {
                            Image(systemName: "person.badge.plus")
                        }
                    case .groups:
                        Button(action: { showCreateGroup = true }) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendView(viewModel: viewModel)
            }
            .sheet(isPresented: $showCreateGroup) {
                GroupFormView(mode: .create, friends: viewModel.friends, groupsViewModel: groupsViewModel)
            }
            .sheet(item: $editingGroup) { group in
                GroupFormView(mode: .edit(group), friends: viewModel.friends, groupsViewModel: groupsViewModel)
            }
            .onAppear {
                groupsViewModel.startListening(ownerId: authService.currentUser?.id ?? "")
            }
            .onDisappear {
                groupsViewModel.stopListening()
            }
        }
    }

    private var friendsList: some View {
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
    }

    private var groupsList: some View {
        List {
            if groupsViewModel.groups.isEmpty {
                Text(Strings.Groups.noGroupsYet)
                    .foregroundColor(.secondary)
            } else {
                ForEach(groupsViewModel.groups) { group in
                    Button(action: { editingGroup = group }) {
                        HStack(spacing: 12) {
                            if let emoji = group.emoji {
                                Text(emoji).font(.title2)
                            } else {
                                Image(systemName: "person.2.fill")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.name)
                                    .font(.subheadline).bold()
                                    .foregroundColor(.primary)
                                Text(Strings.Groups.memberCount(group.memberIds.count))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        let group = groupsViewModel.groups[index]
                        if let id = group.id {
                            Task { await groupsViewModel.deleteGroup(id: id) }
                        }
                    }
                }
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
