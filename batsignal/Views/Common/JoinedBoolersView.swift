import SwiftUI

// Who's in, in the two forms every expanded card shows them: a tight stack of
// faces that costs almost no room, and the opened-up row with names. Shared so
// a friend's card and your own count the same heads the same way.

struct JoinedAvatarStack: View {
    let users: [User]
    // Matches whatever card the faces sit on, since the ring between them is
    // the card showing through rather than a color of its own.
    var background: Color = Color(.secondarySystemBackground)

    private let maxVisible = 5
    private let size: CGFloat = 26

    var body: some View {
        HStack(spacing: -8) {
            ForEach(users.prefix(maxVisible)) { user in
                EventIconView(photoURL: user.profilePhotoURL, label: user.initials, size: size)
                    .overlay(Circle().stroke(background, lineWidth: 2))
            }
            if users.count > maxVisible {
                Text("+\(users.count - maxVisible)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Color(.systemGray3))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(background, lineWidth: 2))
            }
        }
    }
}

struct JoinedBoolersRow: View {
    let users: [User]
    let onTap: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(users) { user in
                    VStack(spacing: 4) {
                        EventIconView(photoURL: user.profilePhotoURL, label: user.initials, size: 44)
                        Text(user.displayName)
                            .font(.caption2)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .frame(width: 52)
                    }
                }
            }
            .padding(.vertical, 2)
            // The gesture sits on the row rather than the scroll view so it
            // doesn't fight the horizontal scroll when the list is long.
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
        }
        .scrollEdgeEffectHidden()
    }
}
