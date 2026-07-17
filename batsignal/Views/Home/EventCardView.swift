import SwiftUI
import FirebaseCore

struct EventCardView: View {
    let event: Event
    var creatorName: String?
    var creatorPhotoURL: String?
    var isSelected: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let label = iconLabel {
                EventIconView(photoURL: creatorPhotoURL, label: label)
            } else if creatorPhotoURL != nil {
                EventIconView(photoURL: creatorPhotoURL, label: nil)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let name = creatorName {
                    Text(name)
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                        .bold()
                }
                Text(event.activity)
                    .font(.headline)

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text(startTimeLabel)
                    if !event.durationLabel.isEmpty {
                        Text("· \(event.durationLabel)")
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)

                if let label = event.locationLabel {
                    HStack(spacing: 4) {
                        Image(systemName: locationIcon)
                        Text(label)
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
    }

    private var iconLabel: String? {
        if let emoji = event.emoji { return emoji }
        guard let name = creatorName, !name.isEmpty else { return nil }
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return initials.isEmpty ? nil : initials.uppercased()
    }

    private var startTimeLabel: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let time = formatter.string(from: event.startTime.dateValue())
        if Calendar.current.isDateInTomorrow(event.startTime.dateValue()) {
            return "Tomorrow · \(time)"
        }
        return time
    }

    private var locationIcon: String {
        switch event.locationType {
        case .text:   return "mappin"
        case .fixed:  return "mappin.circle"
        case .live:   return "location.fill"
        }
    }
}

// Reusable circle icon: profile photo → emoji/initials label → person placeholder
struct EventIconView: View {
    var photoURL: String? = nil
    var label: String? = nil
    var size: CGFloat = 44

    private var isEmoji: Bool {
        label?.unicodeScalars.contains { $0.properties.isEmojiPresentation } ?? false
    }

    var body: some View {
        Group {
            if let photoURL, let url = URL(string: photoURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallbackContent
                    }
                }
            } else {
                fallbackContent
            }
        }
        .frame(width: size, height: size)
        .background(Color.accentColor)
        .clipShape(Circle())
    }

    @ViewBuilder
    private var fallbackContent: some View {
        if let label {
            Text(label)
                .font(isEmoji
                    ? .system(size: size * 0.45)
                    : .system(size: size * 0.3, weight: .bold))
                .foregroundStyle(.white)
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.4))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}