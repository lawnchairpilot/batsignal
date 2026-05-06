import SwiftUI
import FirebaseCore

struct EventCardView: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.activity)
                .font(.headline)

            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text(event.startTime.dateValue(), style: .time)
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
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    private var locationIcon: String {
        switch event.locationType {
        case .text:   return "mappin"
        case .fixed:  return "mappin.circle"
        case .live:   return "location.fill"
        }
    }
}
