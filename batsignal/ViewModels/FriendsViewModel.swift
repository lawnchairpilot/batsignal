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
    @Published var searchResult: User? = nil
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
                errorMessage = "That's you!"
            } else if user == nil {
                errorMessage = "No user found with that number."
            } else {
                searchResult = user
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func sendRequest(toUserId: String) async {
        do {
            try await friendService.sendFriendRequest(toUserId: toUserId)
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

    private func resolveSenderNames(for requests: [FriendRequest]) {
        let unresolvedIds = requests
            .map { $0.fromUserId }
            .filter { senderNames[$0] == nil }
        for userId in unresolvedIds {
            Task {
                if let user = try? await friendService.fetchUser(id: userId) {
                    await MainActor.run { self.senderNames[userId] = user.displayName }
                }
            }
        }
    }

    private func resolveRecipientNames(for requests: [FriendRequest]) {
        let unresolvedIds = requests
            .map { $0.toUserId }
            .filter { recipientNames[$0] == nil }
        for userId in unresolvedIds {
            Task {
                if let user = try? await friendService.fetchUser(id: userId) {
                    let name = user.displayName.isEmpty ? user.phoneNumber : user.displayName
                    await MainActor.run { self.recipientNames[userId] = name }
                }
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

