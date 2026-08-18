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
                VStack(spacing: 12) {
                    EventIconView(
                        photoURL: authService.currentUser?.profilePhotoURL,
                        label: authService.currentUser?.initials,
                        size: 140
                    )
                    VStack(spacing: 4) {
                        Text(authService.currentUser?.displayName ?? "")
                            .font(.blipperUI(.title3, weight: 600))
                        Text(authService.currentUser?.phoneNumber ?? "")
                            .font(.blipperUI(.subheadline))
                            .foregroundColor(Blipper.textMuted)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                // Reads as the page's header rather than another row, so it
                // drops the row's card behind it.
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
                            .profileCard()
                        }
                    }
                }

                // Outgoing pending requests
                if !friendsViewModel.outgoingRequests.isEmpty {
                    Section(Strings.Friends.pendingSectionHeader) {
                        ForEach(friendsViewModel.outgoingRequests) { request in
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundColor(Blipper.textMuted)
                                Text(friendsViewModel.recipientNames[request.toUserId] ?? Strings.Friends.pendingEllipsis)
                                    .foregroundColor(Blipper.textMuted)
                                Spacer()
                                Text(Strings.Friends.requestSent)
                                    .font(.blipperUI(.caption1))
                                    .foregroundColor(Blipper.textMuted)
                            }
                            .profileCard()
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
        .blipperBackground()
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

    // The old friends tab's segmented control, on a card of its own like the
    // rows it switches between, so it reads as a switch over those lists rather
    // than another setting. The add button rides along with it because what it
    // adds depends on which side is showing.
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
                        .font(.blipperUI(.body))
                }
                .buttonStyle(.borderless)
            }
            .profileCard()
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
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else if friendsViewModel.friends.isEmpty {
                Text(Strings.Friends.noFriendsYet)
                    .foregroundColor(Blipper.textMuted)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(friendsViewModel.friends) { friend in
                    HStack(spacing: 12) {
                        EventIconView(
                            photoURL: friend.profilePhotoURL,
                            label: friend.initials,
                            size: 36
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.displayName)
                                .font(.blipperUI(.subheadline, weight: 600))
                            if !friend.phoneNumber.isEmpty {
                                Text(friend.phoneNumber)
                                    .font(.blipperUI(.caption1))
                                    .foregroundColor(Blipper.textMuted)
                            }
                        }
                    }
                    .profileCard()
                    .moderationMenu(
                        report: friend.id.map { ReportTarget.user($0) },
                        block: friend.id.map { BlockTarget(userId: $0, displayName: friend.displayName) }
                    )
                }
            }
        }
    }

    private var groupsSection: some View {
        Section {
            if groupsViewModel.groups.isEmpty {
                Text(Strings.Groups.noGroupsYet)
                    .foregroundColor(Blipper.textMuted)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(groupsViewModel.groups) { group in
                    Button(action: { editingGroup = group }) {
                        HStack(spacing: 12) {
                            if let emoji = group.emoji {
                                Text(emoji).font(.title2)
                            } else {
                                Image(systemName: "person.2.fill")
                                    .font(.title2)
                                    .foregroundColor(Blipper.textMuted)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.name)
                                    .font(.blipperUI(.subheadline, weight: 600))
                                    .foregroundColor(Blipper.textPrimary)
                                Text(Strings.Groups.memberCount(group.memberIds.count))
                                    .font(.blipperUI(.caption1))
                                    .foregroundColor(Blipper.textMuted)
                            }
                        }
                        .cardSurface()
                    }
                    .buttonStyle(.plain)
                    .cardRow()
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
                    .font(.blipperUI(.subheadline, weight: 600))
                Text(Strings.Friends.wantsToBeFriends)
                    .font(.blipperUI(.caption1))
                    .foregroundColor(Blipper.textMuted)
            }
            Spacer()
            Button(Strings.Friends.accept) { onRespond(true) }
                .buttonStyle(.borderedProminent).controlSize(.small)
            Button(Strings.Friends.decline) { onRespond(false) }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }
}
