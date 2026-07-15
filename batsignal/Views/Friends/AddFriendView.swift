import SwiftUI

enum AddFriendTab {
    case search, contacts
}

struct AddFriendView: View {
    @ObservedObject var viewModel: FriendsViewModel
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: AddFriendTab = .search

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Search").tag(AddFriendTab.search)
                    Text("Contacts").tag(AddFriendTab.contacts)
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedTab {
                case .search:
                    searchTab
                case .contacts:
                    contactsTab
                }
            }
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .contacts {
                Task { await viewModel.loadContactMatches(currentUserId: authService.currentUser?.id) }
            }
        }
    }

    // MARK: - Search tab

    private var searchTab: some View {
        VStack(spacing: 20) {
            TextField("+1 (555) 000-0000", text: $viewModel.searchPhone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

            Button(action: { Task { await viewModel.searchByPhone(currentUserId: authService.currentUser?.id) } }) {
                Text("Search")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(viewModel.searchPhone.isEmpty || viewModel.isLoading)

            if let error = viewModel.errorMessage {
                Text(error).foregroundColor(.red).font(.caption)
            }

            if let user = viewModel.searchResult {
                ContactResultRow(
                    name: user.displayName,
                    phone: user.phoneNumber,
                    userId: user.id,
                    friends: viewModel.friends,
                    outgoingRequests: viewModel.outgoingRequests
                ) {
                    Task {
                        guard let id = user.id else { return }
                        await viewModel.sendRequest(toUserId: id)
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Contacts tab

    @ViewBuilder
    private var contactsTab: some View {
        if viewModel.contactsPermissionDenied {
            ContentUnavailableView(
                "Contacts Access Denied",
                systemImage: "person.crop.circle.badge.xmark",
                description: Text("Enable Contacts access in Settings to find friends on batsignal.")
            )
        } else if viewModel.isLoadingContacts {
            ProgressView("Finding friends…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.contactMatches.isEmpty {
            ContentUnavailableView(
                "No Contacts on batsignal",
                systemImage: "person.2.slash",
                description: Text("None of your contacts have joined yet.")
            )
        } else {
            List(viewModel.contactMatches) { match in
                ContactResultRow(
                    name: match.contactName,
                    phone: match.user.phoneNumber,
                    userId: match.user.id,
                    friends: viewModel.friends,
                    outgoingRequests: viewModel.outgoingRequests
                ) {
                    Task {
                        guard let id = match.user.id else { return }
                        await viewModel.sendRequest(toUserId: id)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Shared result row

private struct ContactResultRow: View {
    let name: String
    let phone: String
    let userId: String?
    let friends: [User]
    let outgoingRequests: [FriendRequest]
    let onAdd: () -> Void

    private var alreadyFriend: Bool {
        friends.contains { $0.id == userId }
    }

    private var pendingRequest: Bool {
        guard let id = userId else { return false }
        return outgoingRequests.contains { $0.toUserId == id }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(phone).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if alreadyFriend {
                Text("Friends")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if pendingRequest {
                Text("Requested")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Button("Add", action: onAdd)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }
}
