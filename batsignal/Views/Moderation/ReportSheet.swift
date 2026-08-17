import SwiftUI

// One sheet for all three kinds of report. What's being reported only changes
// the title and what gets written, so the flow — pick a reason, optionally say
// more, submit — stays the same wherever it's opened from.
struct ReportSheet: View {
    let target: ReportTarget

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason?
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            Group {
                if didSubmit {
                    confirmation
                } else {
                    form
                }
            }
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didSubmit ? Strings.Common.done : Strings.Common.cancel) { dismiss() }
                }
            }
        }
    }

    private var form: some View {
        Form {
            Section(Strings.Moderation.reportReasonPrompt) {
                ForEach(ReportReason.allCases) { option in
                    Button {
                        reason = option
                    } label: {
                        HStack {
                            Text(option.label).foregroundStyle(.primary)
                            Spacer()
                            if reason == option {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }

            Section {
                TextField(Strings.Moderation.reportNotePlaceholder, text: $note, axis: .vertical)
                    .lineLimit(2...5)
                    .onChange(of: note) { _, value in
                        if value.count > Report.noteCharacterLimit {
                            note = String(value.prefix(Report.noteCharacterLimit))
                        }
                    }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).font(.caption).foregroundColor(.red)
                }
            }

            Section {
                Button(action: submit) {
                    HStack {
                        Spacer()
                        Text(isSubmitting ? Strings.Moderation.reportSubmitting : Strings.Moderation.reportSubmit)
                        Spacer()
                    }
                }
                .disabled(reason == nil || isSubmitting)
            }
        }
    }

    private var confirmation: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text(Strings.Moderation.reportThanksTitle)
                .font(.headline)
            Text(Strings.Moderation.reportThanksMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
    }

    private func submit() {
        guard let reason else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await ModerationService.shared.report(
                    targetType: target.type,
                    targetId: target.id,
                    eventId: target.eventId,
                    authorId: target.authorId,
                    reason: reason,
                    note: note
                )
                didSubmit = true
            } catch {
                errorMessage = Strings.Moderation.reportFailed
            }
            isSubmitting = false
        }
    }
}

// What the sheet was opened against. Identifiable so a view can drive the sheet
// straight off an optional of this.
struct ReportTarget: Identifiable, Equatable {
    let type: ReportedContentType
    let id: String
    // The event a reported comment belongs to.
    var eventId: String?
    // Whoever wrote the thing, so a review can reach the account behind it.
    var authorId: String?

    var title: String {
        switch type {
        case .comment: return Strings.Moderation.reportComment
        case .event:   return Strings.Moderation.reportEvent
        case .user:    return Strings.Moderation.reportUser
        }
    }

    static func comment(_ comment: Comment, eventId: String) -> ReportTarget? {
        guard let id = comment.id else { return nil }
        return ReportTarget(type: .comment, id: id, eventId: eventId, authorId: comment.authorId)
    }

    static func event(_ event: Event) -> ReportTarget? {
        guard let id = event.id else { return nil }
        return ReportTarget(type: .event, id: id, authorId: event.creatorId)
    }

    static func user(_ userId: String) -> ReportTarget {
        ReportTarget(type: .user, id: userId, authorId: userId)
    }
}
