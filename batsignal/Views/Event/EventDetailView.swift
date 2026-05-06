import SwiftUI
import MapKit
import FirebaseCore

struct EventDetailView: View {
    let event: Event

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Activity + description
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.activity).font(.title.bold())
                    if let desc = event.description {
                        Text(desc).foregroundColor(.secondary)
                    }
                }

                Divider()

                // Time
                VStack(alignment: .leading, spacing: 4) {
                    Label("Time", systemImage: "clock")
                        .font(.subheadline).foregroundColor(.secondary)
                    Text(event.startTime.dateValue(), style: .time)
                        .font(.body)
                    if !event.durationLabel.isEmpty {
                        Text(event.durationLabel)
                            .font(.body).foregroundColor(.secondary)
                    }
                }

                Divider()

                // Location
                VStack(alignment: .leading, spacing: 8) {
                    Label("Location", systemImage: locationIcon)
                        .font(.subheadline).foregroundColor(.secondary)

                    if let label = event.locationLabel {
                        Text(label).font(.body)
                    }

                    if let coord = event.locationCoordinate {
                        MapSnapshotView(coordinate: coord)
                            .frame(height: 180)
                            .cornerRadius(12)
                    }

                    if event.locationType == .live {
                        Label("Live location", systemImage: "location.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var locationIcon: String {
        switch event.locationType {
        case .text:   return "mappin"
        case .fixed:  return "mappin.circle"
        case .live:   return "location.fill"
        }
    }
}

// Placeholder — will be replaced with a real MapKit view
struct MapSnapshotView: View {
    let coordinate: Any

    var body: some View {
        Rectangle()
            .fill(Color(.tertiarySystemBackground))
            .overlay(
                Image(systemName: "map")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
            )
    }
}
