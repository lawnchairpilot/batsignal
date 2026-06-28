import SwiftUI
import FirebaseCore

struct EventCardView: View {
    let event: Event
    var creatorName: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let label = iconLabel {
                EventIconView(label: label)
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

// Reusable circle icon — emoji large, initials smaller bold, white on accentColor
struct EventIconView: View {
    let label: String

    private var isEmoji: Bool {
        label.unicodeScalars.contains { $0.properties.isEmojiPresentation }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 44, height: 44)
            Text(label)
                .font(isEmoji ? .title3 : .caption.bold())
                .foregroundStyle(.white)
        }
    }
}