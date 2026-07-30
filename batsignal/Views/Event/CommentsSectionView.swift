import SwiftUI
import FirebaseFirestore

struct CommentsSectionView: View {
    let eventId: String

    @State private var comments: [Comment] = []
    @State private var listener: ListenerRegistration?
    @State private var newCommentText = ""
    @State private var isPosting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(Strings.Event.commentsSection, systemImage: "bubble.left")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if !comments.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(comments) { comment in
                        CommentRow(comment: comment)
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    TextField(Strings.Event.commentPlaceholder, text: $newCommentText, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
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
    }

    private var initials: String? {
        let initials = comment.authorName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return initials.isEmpty ? nil : initials.uppercased()
    }
}
