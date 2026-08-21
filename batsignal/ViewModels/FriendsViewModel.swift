import Foundation
import Combine
import Contacts
import FirebaseFirestore

@MainActor
class FriendsViewModel: ObservableObject {
    @Published var friends: [User] = []
    @Published var incomingRequests: [FriendRequest] = []
    @Published var outgoingRequests: [FriendRequest] = []
    @Published var senderNames: [String: String] = [:]    // fromUserId → displayName
    @Published var recipientNames: [String: String] = [:] // toUserId → displayName or phoneNumber
    @Published var searchResult: PublicProfile? = nil
    @Published var searchPhone = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Contacts
    @Published var contactMatches: [ContactMatch] = []
    @Published var isLoadingContacts = false
    @Published var contactsPermissionDenied = false

    private let friendService = FriendService()
    private let contactsService = ContactsService()
    private var listeners: [ListenerRegistration] = []

    func startListening(friendIds: [String]) {
        loadFriends(ids: friendIds)

        if let r = friendService.listenToIncomingRequests(onChange: { [weak self] requests in
            Task { @MainActor in
                self?.incomingRequests = requests
                self?.resolveSenderNames(for: requests)
            }
        }) { listeners.append(r) }

        if let r = friendService.listenToOutgoingRequests(onChange: { [weak self] requests in
            Task { @MainActor in
                self?.outgoingRequests = requests
                self?.resolveRecipientNames(for: requests)
            }
        }) { listeners.append(r) }
    }

    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners = []
    }

    func reloadFriends(ids: [String]) {
        loadFriends(ids: ids)
    }

    private func loadFriends(ids: [String]) {
        isLoading = true
        Task {
            do {
                friends = try await friendService.fetchFriends(ids: ids)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func searchByPhone(currentUserId: String?) async {
        isLoading = true
        errorMessage = nil
        searchResult = nil
        do {
            let user = try await friendService.findUser(byPhoneNumber: searchPhone)
            if let user, user.id == currentUserId {
                errorMessage = Strings.Friends.thatsYou
            } else if user == nil {
                errorMessage = Strings.Friends.noUserFound
            } else {
                searchResult = user
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func sendRequest(toUserId: String, toUserName: String?) async {
        do {
            try await friendService.sendFriendRequest(toUserId: toUserId, toUserName: toUserName)
            searchResult = nil
            searchPhone = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func respond(to request: FriendRequest, accept: Bool) async {
        guard let id = request.id else { return }
        do {
            try await friendService.respondToRequest(requestId: id, accept: accept)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func hasPendingOutgoingRequest(toUserId: String) -> Bool {
        outgoingRequests.contains { $0.toUserId == toUserId }
    }

    // The request carries both names, so the common case needs no lookup at all
    // and the name is on screen the moment the row is. Only requests sent
    // before those fields existed fall through to the profile call, and that
    // goes in one batch rather than one call per row.
    private func resolveSenderNames(for requests: [FriendRequest]) {
        for request in requests {
            if let name = request.fromUserName, !name.isEmpty {
                senderNames[request.fromUserId] = name
            }
        }
        resolve(
            ids: requests.map(\.fromUserId).filter { senderNames[$0] == nil },
            into: \.senderNames
        )
    }

    private func resolveRecipientNames(for requests: [FriendRequest]) {
        for request in requests {
            if let name = request.toUserName, !name.isEmpty {
                recipientNames[request.toUserId] = name
            }
        }
        resolve(
            ids: requests.map(\.toUserId).filter { recipientNames[$0] == nil },
            into: \.recipientNames
        )
    }

    private func resolve(
        ids: [String],
        into keyPath: ReferenceWritableKeyPath<FriendsViewModel, [String: String]>
    ) {
        guard !ids.isEmpty else { return }
        Task {
            guard let profiles = try? await friendService.fetchProfiles(ids: ids) else { return }
            for profile in profiles where !profile.displayName.isEmpty {
                self[keyPath: keyPath][profile.id] = profile.displayName
            }
        }
    }

    // MARK: - Contacts

    func loadContactMatches(currentUserId: String?) async {
        let status = contactsService.authorizationStatus
        if status == .denied || status == .restricted {
            contactsPermissionDenied = true
            return
        }
        if status == .notDetermined {
            let granted = await contactsService.requestAccess()
            if !granted {
                contactsPermissionDenied = true
                return
            }
        }
        isLoadingContacts = true
        do {
            contactMatches = try await contactsService.fetchMatchedUsers(excludingId: currentUserId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingContacts = false
    }
}

