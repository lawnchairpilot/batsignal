import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct CommentsSectionView: View {
    let eventId: String

    @State private var comments: [Comment] = []
    @State private var listener: ListenerRegistration?
    @State private var newCommentText = ""
    @State private var isPosting = false
    @FocusState private var isCommentFieldFocused: Bool
    @ObservedObject private var moderation = ModerationService.shared

    // Comments from blocked people, and ones this user reported, never reach
    // the list.
    private var visibleComments: [Comment] {
        comments.filter { !moderation.isHidden(comment: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(Strings.Event.commentsSection, systemImage: "bubble.left")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            if !visibleComments.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleComments) { comment in
                        CommentRow(comment: comment, eventId: eventId)
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    TextField(Strings.Event.commentPlaceholder, text: $newCommentText, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                        .focused($isCommentFieldFocused)
                        .onChange(of: newCommentText) { _, newValue in
                            if newValue.count > Comment.characterLimit {
                                newCommentText = String(newValue.prefix(Comment.characterLimit))
                            }
                        }
                    Text("\(newCommentText.count)/\(Comment.characterLimit)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Button(action: post) {
                    if isPosting {
                        ProgressView()
                            .frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.accentColor)
                    }
                }
                .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
            }
        }
        .onAppear {
            listener = EventService().listenToComments(eventId: eventId) { comments = $0 }
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
    }

    private func post() {
        let text = newCommentText
        isPosting = true
        isCommentFieldFocused = false
        Task {
            try? await EventService().postComment(eventId: eventId, text: text)
            await MainActor.run {
                newCommentText = ""
                isPosting = false
            }
        }
    }
}

private struct CommentRow: View {
    let comment: Comment
    let eventId: String

    private var isMine: Bool {
        comment.authorId == Auth.auth().currentUser?.uid
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            EventIconView(photoURL: comment.authorPhotoURL, label: initials, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(comment.authorName)
                    .font(.caption.bold())
                Text(comment.text)
                    .font(.subheadline)
            }
            Spacer(minLength: 0)
            Text(comment.createdAt.dateValue(), style: .time)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .moderationMenu(
            report: isMine ? nil : ReportTarget.comment(comment, eventId: eventId),
            block: isMine ? nil : BlockTarget(userId: comment.authorId, displayName: comment.authorName)
        )
    }

    private var initials: String? {
        let initials = comment.authorName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return initials.isEmpty ? nil : initials.uppercased()
    }
}
