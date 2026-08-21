import Foundation
import Combine
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

// Everything the app needs to know about who this user has cut off and what
// they've already reported, held in memory so a comment row can ask without a
// round trip.
//
// Blocking unfriends both ways, so most of a block enforces itself: the events
// stop arriving because recipientIds no longer includes them. What still needs
// filtering is the overlap that survives — two people who blocked each other
// can both be friends of a third person, and both be on that person's signal.
@MainActor
final class ModerationService: ObservableObject {
    static let shared = ModerationService()

    // Blocks in either direction. Which way a block runs doesn't change what
    // gets hidden, so callers see one combined set.
    @Published private(set) var hiddenUserIds: Set<String> = []
    // Comment and event ids this user has reported, hidden for them alone until
    // the report is reviewed.
    @Published private(set) var reportedTargetIds: Set<String> = []
    @Published private(set) var blockedUserIds: Set<String> = []

    private var blockedByUserIds: Set<String> = []
    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []

    private init() {}

    // MARK: - Listening

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        stopListening()

        // Two queries rather than one, because Firestore can't OR across
        // different fields without a composite index per combination.
        listeners.append(
            db.collection("blocks").whereField("blockerId", isEqualTo: uid)
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let self, let snapshot else { return }
                    let ids = Set(snapshot.documents.compactMap { $0.data()["blockedId"] as? String })
                    self.blockedUserIds = ids
                    self.rebuildHidden()
                }
        )

        listeners.append(
            db.collection("blocks").whereField("blockedId", isEqualTo: uid)
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let self, let snapshot else { return }
                    self.blockedByUserIds = Set(snapshot.documents.compactMap { $0.data()["blockerId"] as? String })
                    self.rebuildHidden()
                }
        )

        listeners.append(
            db.collection("reports").whereField("reporterId", isEqualTo: uid)
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let self, let snapshot else { return }
                    self.reportedTargetIds = Set(snapshot.documents.compactMap { $0.data()["targetId"] as? String })
                }
        )
    }

    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners = []
        hiddenUserIds = []
        blockedUserIds = []
        blockedByUserIds = []
        reportedTargetIds = []
    }

    private func rebuildHidden() {
        hiddenUserIds = blockedUserIds.union(blockedByUserIds)
    }

    // MARK: - Queries

    func isBlocked(_ userId: String) -> Bool {
        blockedUserIds.contains(userId)
    }

    // A signal is out of sight if its host is cut off or this user reported it.
    func isHidden(event: Event) -> Bool {
        if hiddenUserIds.contains(event.creatorId) { return true }
        if let id = event.id, reportedTargetIds.contains(id) { return true }
        return false
    }

    func isHidden(comment: Comment) -> Bool {
        if hiddenUserIds.contains(comment.authorId) { return true }
        if let id = comment.id, reportedTargetIds.contains(id) { return true }
        return false
    }

    func isHidden(userId: String) -> Bool {
        hiddenUserIds.contains(userId)
    }

    // MARK: - Actions

    func report(
        targetType: ReportedContentType,
        targetId: String,
        eventId: String? = nil,
        authorId: String? = nil,
        reason: ReportReason,
        note: String?
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw URLError(.userAuthenticationRequired)
        }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let report = Report(
            reporterId: uid,
            targetType: targetType,
            targetId: targetId,
            eventId: eventId,
            authorId: authorId,
            reason: reason,
            note: (trimmed?.isEmpty ?? true) ? nil : String(trimmed!.prefix(Report.noteCharacterLimit)),
            status: .open,
            createdAt: Timestamp(date: Date())
        )
        _ = try db.collection("reports").addDocument(from: report)
    }

    // Both of these run server-side: a block has to tear down a friendship,
    // which is two users' documents, and no client is allowed to write those.
    func block(userId: String) async throws {
        _ = try await Functions.functions().httpsCallable("blockUser").call(["userId": userId])
    }

    func unblock(userId: String) async throws {
        _ = try await Functions.functions().httpsCallable("unblockUser").call(["userId": userId])
    }

    // Blocked people are gone from the friends list, so their names have to come
    // from somewhere else for the unblock screen to be usable.
    func blockedProfiles() async throws -> [PublicProfile] {
        try await ProfileLookup.profiles(userIds: Array(blockedUserIds))
    }
}
