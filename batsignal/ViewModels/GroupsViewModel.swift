import Foundation
import Combine
import FirebaseFirestore

@MainActor
class GroupsViewModel: ObservableObject {
    @Published var groups: [FriendGroup] = []
    @Published var errorMessage: String?

    private let groupService = GroupService()
    private var listener: ListenerRegistration?

    func startListening(ownerId: String) {
        listener?.remove()
        guard !ownerId.isEmpty else { return }
        listener = groupService.listenToGroups(ownerId: ownerId) { [weak self] groups in
            Task { @MainActor in
                self?.groups = groups
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func createGroup(name: String, emoji: String?, memberIds: [String]) async {
        do {
            try await groupService.createGroup(name: name, emoji: emoji, memberIds: memberIds)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateGroup(id: String, name: String, emoji: String?, memberIds: [String]) async {
        do {
            try await groupService.updateGroup(id: id, name: name, emoji: emoji, memberIds: memberIds)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteGroup(id: String) async {
        do {
            try await groupService.deleteGroup(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
