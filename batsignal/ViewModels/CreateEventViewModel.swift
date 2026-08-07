import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth
import UIKit

enum DayOption: String, CaseIterable {
    case today = "Today"
    case tomorrow = "Tomorrow"
}

@MainActor
class CreateEventViewModel: ObservableObject {
    @Published var activity = ""
    @Published var emoji: String? = nil
    @Published var description = ""
    @Published var selectedDurationMinutes: Int? = 180
    @Published var selectedVagueLabel: String? = nil
    @Published var commentsEnabled = true
    @Published var selectedImage: UIImage? = nil
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var didCreate = false
    @Published var groups: [FriendGroup] = []
    @Published var selectedGroupIds: Set<String> = []

    private let eventService = EventService()
    private let locationService = LocationService()
    private let groupService = GroupService()
    private let friendService = FriendService()

    func loadGroups() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        groups = (try? await groupService.fetchGroups(ownerId: uid)) ?? []
    }

    var durationLabel: String {
        if let minutes = selectedDurationMinutes {
            return Event.durationOptions.first { $0.minutes == minutes }?.label ?? ""
        }
        return selectedVagueLabel ?? ""
    }

    func submit() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        errorMessage = nil

        var imageURL: String? = nil
        if let selectedImage {
            do {
                imageURL = try await PhotoStorageService().uploadEventImage(selectedImage)
            } catch {
                errorMessage = Strings.Event.imageUploadFailed(error.localizedDescription)
                isLoading = false
                return
            }
        }

        let startTime = Date()
        let endTime = Event.computeEndTime(
            startTime: startTime,
            durationMinutes: selectedDurationMinutes,
            vagueLabel: selectedVagueLabel
        )

        // Coordinate is nil at creation time — LocationService writes the first
        // coordinate to Firestore shortly after the event becomes active.
        let liveFriendIds = (try? await friendService.fetchUser(id: uid))?.friends ?? []
        let recipientIds: [String]
        if selectedGroupIds.isEmpty {
            recipientIds = liveFriendIds
        } else {
            let groupMemberIds = groups
                .filter { selectedGroupIds.contains($0.id ?? "") }
                .flatMap { $0.memberIds }
            recipientIds = Array(Set(groupMemberIds).intersection(liveFriendIds))
        }

        let event = Event(
            creatorId: uid,
            activity: activity,
            emoji: emoji,
            description: description.isEmpty ? nil : description,
            startTime: Timestamp(date: startTime),
            durationMinutes: selectedDurationMinutes,
            durationVagueLabel: selectedVagueLabel,
            endTime: endTime,
            locationType: .live,
            locationLabel: nil,
            locationCoordinate: nil,
            isActive: true,
            createdAt: .init(),
            recipientIds: recipientIds,
            commentsEnabled: commentsEnabled,
            imageURL: imageURL,
            audienceIsAllFriends: selectedGroupIds.isEmpty
        )

        do {
            try await eventService.createEvent(event)
            didCreate = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
