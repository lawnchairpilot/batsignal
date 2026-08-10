import SwiftUI

enum FriendsTab {
    case friends, groups
}

// Pushed from the home screen's profile button, so it leans on that
// navigation stack rather than starting one of its own.
struct ProfileView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject private var friendsViewModel: FriendsViewModel
    @StateObject private var groupsViewModel = GroupsViewModel()
    @State private var selectedTab: FriendsTab = .friends
    @State private var showAddFriend = false
    @State private var showCreateGroup = false
    @State private var editingGroup: FriendGroup?

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    EventIconView(
                        photoURL: authService.currentUser?.profilePhotoURL,
                        label: authService.currentUser?.initials,
                        size: 60
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(authService.currentUser?.displayName ?? "")
                            .font(.headline)
                        Text(authService.currentUser?.phoneNumber ?? "")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                NavigationLink(Strings.Profile.eventRadiusFilter) {
                    RadiusSettingView()
                }
            }

            peopleSelector

            switch selectedTab {
            case .friends:
                // Incoming requests
                if !friendsViewModel.incomingRequests.isEmpty {
                    Section(Strings.Friends.requestsSectionHeader) {
                        ForEach(friendsViewModel.incomingRequests) { request in
                            IncomingRequestRow(
                                request: request,
                                senderName: friendsViewModel.senderNames[request.fromUserId]
                            ) { accept in
                                Task { await friendsViewModel.respond(to: request, accept: accept) }
                            }
                        }
                    }
                }

                // Outgoing pending requests
                if !friendsViewModel.outgoingRequests.isEmpty {
                    Section(Strings.Friends.pendingSectionHeader) {
                        ForEach(friendsViewModel.outgoingRequests) { request in
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundColor(.secondary)
                                Text(friendsViewModel.recipientNames[request.toUserId] ?? Strings.Friends.pendingEllipsis)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(Strings.Friends.requestSent)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                friendsSection
            case .groups:
                groupsSection
            }
        }
        // Grouped lists reserve room between sections for headers that most of
        // these no longer have, which left gaps where the labels used to be.
        .listSectionSpacing(.compact)
        .navigationTitle(Strings.Profile.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(Strings.Profile.settingsTitle)
            }
        }
        .sheet(isPresented: $showAddFriend) {
            AddFriendView(viewModel: friendsViewModel)
        }
        .sheet(isPresented: $showCreateGroup) {
            GroupFormView(mode: .create, friends: friendsViewModel.friends, groupsViewModel: groupsViewModel)
        }
        .sheet(item: $editingGroup) { group in
            GroupFormView(mode: .edit(group), friends: friendsViewModel.friends, groupsViewModel: groupsViewModel)
        }
        .onAppear {
            groupsViewModel.startListening(ownerId: authService.currentUser?.id ?? "")
        }
        // The user document can land after this view first appears, so pick
        // the listener back up once there's an id to own the groups.
        .onChange(of: authService.currentUser?.id) { _, newId in
            groupsViewModel.startListening(ownerId: newId ?? "")
        }
        .onDisappear {
            groupsViewModel.stopListening()
        }
    }

    // The old friends tab's segmented control, kept as a floating strip rather
    // than a list row so it reads as a switch between the two lists below it
    // instead of another setting. The add button rides along with it because
    // what it adds depends on which side is showing.
    private var peopleSelector: some View {
        Section {
            HStack(spacing: 12) {
                Picker("", selection: $selectedTab) {
                    Text(Strings.Friends.title).tag(FriendsTab.friends)
                    Text(Strings.Groups.title).tag(FriendsTab.groups)
                }
                .pickerStyle(.segmented)

                Button(action: { addTapped() }) {
                    Image(systemName: selectedTab == .friends ? "person.badge.plus" : "plus")
                        .font(.body)
                }
                .buttonStyle(.borderless)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
    }

    private func addTapped() {
        switch selectedTab {
        case .friends: showAddFriend = true
        case .groups: showCreateGroup = true
        }
    }

    private var friendsSection: some View {
        Section {
            if friendsViewModel.isLoading {
                ProgressView()
            } else if friendsViewModel.friends.isEmpty {
                Text(Strings.Friends.noFriendsYet)
                    .foregroundColor(.secondary)
            } else {
                ForEach(friendsViewModel.friends) { friend in
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

    private var groupsSection: some View {
        Section {
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

private struct IncomingRequestRow: View {
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
