import SwiftUI

// Blocking unfriends, so a blocked person is gone from every other list in the
// app. This is the only place left that can name them, which makes it the only
// way back — without it a block would be permanent by accident.
struct BlockedUsersView: View {
    @ObservedObject private var moderation = ModerationService.shared

    @State private var profiles: [PublicProfile] = []
    @State private var isLoading = true
    @State private var pendingUnblock: PublicProfile?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else if profiles.isEmpty {
                Text(Strings.Moderation.noBlockedUsers)
                    .foregroundColor(Blipper.textMuted)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(profiles) { profile in
                        HStack(spacing: 12) {
                            EventIconView(
                                photoURL: profile.profilePhotoURL,
                                label: profile.initials,
                                size: 36
                            )
                            Text(profile.displayName)
                                .font(.blipperUI(.subheadline, weight: 600))
                            Spacer()
                            Button(Strings.Moderation.unblock) {
                                pendingUnblock = profile
                            }
                            .font(.blipperUI(.subheadline))
                            .buttonStyle(.bordered)
                        }
                        .profileCard()
                    }
                } footer: {
                    Text(Strings.Moderation.blockedSectionFooter)
                        .font(.blipperUI(.caption1))
                }
            }
        }
        .blipperBackground()
        .navigationTitle(Strings.Moderation.blockedUsersTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        // The list is driven by the blocks listener, so unblocking somewhere
        // else keeps this in step too.
        .onChange(of: moderation.blockedUserIds) { _, _ in
            Task { await load() }
        }
        .alert(
            pendingUnblock.map { Strings.Moderation.unblockTitle($0.displayName) } ?? "",
            isPresented: Binding(
                get: { pendingUnblock != nil },
                set: { if !$0 { pendingUnblock = nil } }
            )
        ) {
            Button(Strings.Common.cancel, role: .cancel) { pendingUnblock = nil }
            Button(Strings.Moderation.unblock, role: .destructive) {
                if let target = pendingUnblock { unblock(target) }
                pendingUnblock = nil
            }
        } message: {
            Text(Strings.Moderation.unblockMessage)
        }
        .alert(
            Strings.Moderation.unblockFailed,
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(Strings.Common.ok, role: .cancel) { errorMessage = nil }
        }
    }

    private func load() async {
        guard !moderation.blockedUserIds.isEmpty else {
            profiles = []
            isLoading = false
            return
        }
        profiles = (try? await moderation.blockedProfiles())?
            .sorted { $0.displayName < $1.displayName } ?? []
        isLoading = false
    }

    private func unblock(_ profile: PublicProfile) {
        Task {
            do {
                try await moderation.unblock(userId: profile.id)
            } catch {
                errorMessage = Strings.Moderation.unblockFailed
            }
        }
    }
}
