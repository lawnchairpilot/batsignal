import Foundation
import Combine

@MainActor
class FriendsViewModel: ObservableObject {
    @Published var friends: [User] = []
    @Published var incomingRequests: [FriendRequest] = []
    @Published var searchResult: User? = nil
    @Published var searchPhone = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let friendService = FriendService()

    func loadFriends(ids: [String]) async {
        isLoading = true
        do {
            friends = try await friendService.fetchFriends(ids: ids)
            incomingRequests = try await friendService.fetchIncomingRequests()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func searchByPhone() async {
        isLoading = true
        errorMessage = nil
        searchResult = nil
        do {
            searchResult = try await friendService.findUser(byPhoneNumber: searchPhone)
            if searchResult == nil { errorMessage = "No user found with that number." }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func sendRequest(toUserId: String) async {
        do {
            try await friendService.sendFriendRequest(toUserId: toUserId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func respond(to request: FriendRequest, accept: Bool) async {
        guard let id = request.id else { return }
        do {
            try await friendService.respondToRequest(requestId: id, accept: accept)
            incomingRequests.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
